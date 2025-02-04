import Foundation
import Network
import os.log

// Create a logger for FileTransferService
private let logger = Logger(subsystem: "com.eftikharazim.CrossShareMac", category: "FileTransferService")

class FileTransferService : ObservableObject {
    static let shared = FileTransferService()
    private var listener: NWListener?
    
    init() {
        logger.info("Initializing FileTransferService")
        startServer(port: 8080)
    }
    
    private func setupServerHandlers() {
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("Server ready and running on port \(self.listener?.port?.rawValue ?? 0)")
            case .failed(let error):
                logger.error("Server failed: \(error.localizedDescription)")
            case .waiting(let error):
                logger.warning("Server waiting: \(error.localizedDescription)")
            default:
                logger.debug("Server state changed to: \(state)")
                break
            }
        }
    }
    
    // MARK: - Server
    func startServer(port: UInt16) {
        logger.info("Starting server on port \(port)")
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            //            listener = try NWListener(using: .tcp, on: .any)
            setupServerHandlers()
            
            listener?.newConnectionHandler = { [weak self] connection in
                logger.info("New connection established from \(connection.endpoint)")
                self?.receiveFile(connection: connection)
                connection.start(queue: .main)
            }
            
            listener?.start(queue: .main)
        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Client
    func sendFile(to ip: String, port: UInt16, fileURL: URL) {
        logger.info("Initiating connection to \(ip):\(port)")
        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                logger.info("Connection ready")
                self?.sendFileData(connection: connection, fileURL: fileURL)
            case .failed(let error):
                logger.error("Connection failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    // MARK: - Private Methods
    private func sendFileData(connection: NWConnection, fileURL: URL) {
        do {
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            
            // 1. Prepare metadata (name|size)
            let metadata = "\(fileName)|\(fileData.count)"
            guard let metadataData = metadata.data(using: .utf8) else {
                logger.error("Failed to encode metadata")
                return
            }
            
            // 2. Send metadata length (4 bytes)
            var metadataLength = UInt32(metadataData.count).bigEndian
            let lengthData = Data(bytes: &metadataLength, count: 4)
            
            connection.send(content: lengthData, completion: .contentProcessed { error in
                if let error = error {
                    logger.error("Metadata length send error: \(error.localizedDescription)")
                    return
                }
                
                // 3. Send metadata
                connection.send(content: metadataData, completion: .contentProcessed { error in
                    if let error = error {
                        logger.error("Metadata send error: \(error.localizedDescription)")
                        return
                    }
                    
                    // 4. Send file in chunks
                    let chunkSize = 4096
                    fileData.withUnsafeBytes { buffer in
                        var offset = 0
                        
                        func sendChunk() {
                            let remaining = fileData.count - offset
                            let thisChunk = min(chunkSize, remaining)
                            
                            if thisChunk <= 0 {
                                logger.info("File sent successfully")
                                connection.cancel()
                                return
                            }
                            
                            let chunk = Data(bytes: buffer.baseAddress! + offset, count: thisChunk)
                            connection.send(content: chunk, completion: .contentProcessed { error in
                                if let error = error {
                                    logger.error("Chunk send error: \(error.localizedDescription)")
                                    connection.cancel()
                                    return
                                }
                                
                                offset += thisChunk
                                sendChunk()
                            })
                        }
                        
                        sendChunk()
                    }
                })
            })
        } catch {
            logger.error("File read error: \(error.localizedDescription)")
        }
    }
    
    private func receiveFile(connection: NWConnection) {
        // 1. Read metadata length (4 bytes)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let data = data, data.count == 4 else {
                logger.error("Failed to read metadata length")
                return
            }
            
            // 2. Extract metadata length (big-endian UInt32)
            let metadataLength = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // 3. Read metadata bytes
            connection.receive(minimumIncompleteLength: Int(metadataLength), maximumLength: Int(metadataLength)) { data, _, _, _ in
                guard let metadataData = data,
                      let metadata = String(data: metadataData, encoding: .utf8),
                      let separatorIndex = metadata.firstIndex(of: "|") else {
                    logger.error("Invalid metadata")
                    return
                }
                
                // 4. Process file data
                let fileName = String(metadata[..<separatorIndex])
                let fileSize = Int(metadata[metadata.index(after: separatorIndex)...]) ?? 0
                self?.receiveFileData(connection: connection, fileName: fileName, fileSize: fileSize)
            }
        }
    }
    
    private func receiveFileData(connection: NWConnection, fileName: String, fileSize: Int) {
        connection.receive(minimumIncompleteLength: fileSize, maximumLength: fileSize) { data, _, _, _ in
            guard let fileData = data else { return }
            
            // Save to Downloads with original name (e.g., "photo.jpg")
            let downloadsDir = FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first!
            let fileURL = downloadsDir.appendingPathComponent(fileName)
            
            do {
                try fileData.write(to: fileURL)
                logger.info("File saved: \(fileURL.path)")
            } catch {
                logger.error("Save error: \(error.localizedDescription)")
            }
            connection.cancel()
        }
    }
}
