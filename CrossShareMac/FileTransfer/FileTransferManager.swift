import Foundation
import Network

class FileTransferManager: FileTransferServiceProtocol, FileTransferConnectionHandler, FileTransferDataHandler, FileTransferServerProtocol {
    static let shared = FileTransferManager()
    var listener: NWListener?
    weak var progressDelegate: FileTransferProgressDelegate?
    private let config = NetworkConfiguration.shared
    
    private init() {
        startServer(port: config.servicePort)
    }
    
    // MARK: - FileTransferServiceProtocol
    func startServer(port: UInt16) {
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            setupServerHandlers()
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener?.start(queue: .main)
        } catch {
            print("🔴 Failed to start server: \(error)")
            if let nwError = error as? NWError {
                handleServerState(.failed(nwError))
            } else {
                // For non-NWError types, we'll still log but handle differently
                print("🔴 Server initialization error: \(error)")
                handleServerState(.failed(NWError.posix(.ECONNABORTED)))
            }
        }
    }
    
    func sendFile(to ip: String, port: UInt16, fileURL: URL) {
        guard config.isValidIPv4(ip) else {
            progressDelegate?.transferDidComplete(fileName: fileURL.lastPathComponent, error: FileTransferError.invalidIPAddress)
            return
        }
        
        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, for: connection)
            if case .ready = state {
                self?.sendFileData(connection: connection, fileURL: fileURL)
            }
        }
        
        connection.start(queue: .main)
    }
    
    // MARK: - FileTransferServerProtocol
    func setupServerHandlers() {
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleServerState(state)
        }
    }
    
    func handleServerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("✅ Server running on port \(listener?.port?.rawValue ?? 0)")
        case .failed(let error):
            print("🔴 Server error: \(error)")
        case .waiting(let error):
            print("🟡 Server waiting: \(error)")
        default: break
        }
    }
    
    // MARK: - FileTransferConnectionHandler
    func handleNewConnection(_ connection: NWConnection) {
        print("🔗 New connection from \(connection.endpoint)")
        receiveFile(connection: connection)
        connection.start(queue: .main)
    }
    
    func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection) {
        switch state {
        case .failed(let error):
            print("🔴 Connection failed: \(error)")
            progressDelegate?.transferDidComplete(fileName: "", error: FileTransferError.connectionFailed(error))
        case .waiting(let error):
            print("🟡 Connection waiting: \(error)")
        default: break
        }
    }
    
    // MARK: - FileTransferDataHandler
    func sendFileData(connection: NWConnection, fileURL: URL) {
        do {
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            
            progressDelegate?.transferDidStart(fileName: fileName, fileSize: fileData.count)
            
            // Send metadata
            let metadata = "\(fileName)\(config.metadataDelimiter)\(fileData.count)"
            guard let metadataData = metadata.data(using: .utf8) else {
                throw FileTransferError.invalidMetadata
            }
            
            var metadataLength = UInt32(metadataData.count).bigEndian
            let lengthData = Data(bytes: &metadataLength, count: 4)
            
            // Send file data in chunks
            self.sendDataInChunks(connection: connection, lengthData: lengthData, metadataData: metadataData, fileData: fileData, fileName: fileName)
            
        } catch {
            progressDelegate?.transferDidComplete(fileName: fileURL.lastPathComponent, error: FileTransferError.fileReadError(error))
        }
    }
    
    private func sendDataInChunks(connection: NWConnection, lengthData: Data, metadataData: Data, fileData: Data, fileName: String) {
        connection.send(content: lengthData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.progressDelegate?.transferDidComplete(fileName: fileName, error: FileTransferError.networkError(error))
                return
            }
            
            connection.send(content: metadataData, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.progressDelegate?.transferDidComplete(fileName: fileName, error: FileTransferError.networkError(error))
                    return
                }
                
                self?.sendFileChunks(connection: connection, fileData: fileData, fileName: fileName)
            })
        })
    }
    
    private func sendFileChunks(connection: NWConnection, fileData: Data, fileName: String) {
        var totalSent = 0
        let chunkSize = config.chunkSize
        
        func sendNextChunk() {
            let remainingBytes = fileData.count - totalSent
            let chunkLength = min(chunkSize, remainingBytes)
            
            if chunkLength <= 0 {
                progressDelegate?.transferDidComplete(fileName: fileName, error: nil)
                connection.cancel()
                return
            }
            
            let chunk = fileData.subdata(in: totalSent..<(totalSent + chunkLength))
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.progressDelegate?.transferDidComplete(fileName: fileName, error: FileTransferError.networkError(error))
                    connection.cancel()
                    return
                }
                
                totalSent += chunkLength
                let progress = Double(totalSent) / Double(fileData.count)
                self?.progressDelegate?.transferDidProgress(fileName: fileName, progress: progress)
                sendNextChunk()
            })
        }
        
        sendNextChunk()
    }
    
    func receiveFile(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            if let error = error {
                self?.progressDelegate?.transferDidComplete(fileName: "", error: FileTransferError.networkError(error))
                return
            }
            
            guard let data = data, data.count == 4 else {
                self?.progressDelegate?.transferDidComplete(fileName: "", error: FileTransferError.invalidMetadata)
                return
            }
            
            let metadataLength = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self?.receiveMetadata(connection: connection, length: Int(metadataLength))
        }
    }
    
    private func receiveMetadata(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            if let error = error {
                self?.progressDelegate?.transferDidComplete(fileName: "", error: FileTransferError.networkError(error))
                return
            }
            
            guard let metadataData = data,
                  let metadata = String(data: metadataData, encoding: .utf8),
                  let separatorIndex = metadata.firstIndex(of: Character(self?.config.metadataDelimiter ?? "|")) else {
                self?.progressDelegate?.transferDidComplete(fileName: "", error: FileTransferError.invalidMetadata)
                return
            }
            
            let fileName = String(metadata[..<separatorIndex])
            let fileSize = Int(metadata[metadata.index(after: separatorIndex)...]) ?? 0
            self?.receiveFileData(connection: connection, fileName: fileName, fileSize: fileSize)
        }
    }
    
    func receiveFileData(connection: NWConnection, fileName: String, fileSize: Int) {
        progressDelegate?.transferDidStart(fileName: fileName, fileSize: fileSize)
        var receivedData = Data()
        
        func receiveNextChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: config.chunkSize) { [weak self] data, _, isComplete, error in
                if let error = error {
                    self?.progressDelegate?.transferDidComplete(fileName: fileName, error: FileTransferError.networkError(error))
                    return
                }
                
                if let data = data {
                    receivedData.append(data)
                    let progress = Double(receivedData.count) / Double(fileSize)
                    self?.progressDelegate?.transferDidProgress(fileName: fileName, progress: progress)
                }
                
                if receivedData.count >= fileSize || isComplete {
                    self?.saveReceivedFile(fileName: fileName, data: receivedData)
                    return
                }
                
                receiveNextChunk()
            }
        }
        
        receiveNextChunk()
    }
    
    private func saveReceivedFile(fileName: String, data: Data) {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            progressDelegate?.transferDidComplete(fileName: fileName, error: nil)
        } catch {
            progressDelegate?.transferDidComplete(fileName: fileName, error: FileTransferError.fileWriteError(error))
        }
    }
}
