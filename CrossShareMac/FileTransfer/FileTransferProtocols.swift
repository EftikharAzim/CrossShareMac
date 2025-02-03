import Foundation
import Network

// MARK: - File Transfer Service Protocol
protocol FileTransferServiceProtocol: AnyObject {
    func startServer(port: UInt16)
    func sendFile(to ip: String, port: UInt16, fileURL: URL)
}

// MARK: - File Transfer Connection Handler Protocol
protocol FileTransferConnectionHandler: AnyObject {
    func handleNewConnection(_ connection: NWConnection)
    func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection)
}

// MARK: - File Transfer Data Handler Protocol
protocol FileTransferDataHandler: AnyObject {
    func sendFileData(connection: NWConnection, fileURL: URL)
    func receiveFile(connection: NWConnection)
    func receiveFileData(connection: NWConnection, fileName: String, fileSize: Int)
}

// MARK: - File Transfer Server Protocol
protocol FileTransferServerProtocol: AnyObject {
    var listener: NWListener? { get set }
    func setupServerHandlers()
    func handleServerState(_ state: NWListener.State)
}

// MARK: - File Transfer Progress Protocol
protocol FileTransferProgressDelegate: AnyObject {
    func transferDidStart(fileName: String, fileSize: Int)
    func transferDidProgress(fileName: String, progress: Double)
    func transferDidComplete(fileName: String, error: Error?)
}