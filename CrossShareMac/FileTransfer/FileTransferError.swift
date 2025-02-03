import Foundation

enum FileTransferError: LocalizedError {
    case invalidMetadata
    case fileReadError(Error)
    case fileWriteError(Error)
    case networkError(Error)
    case connectionFailed(Error)
    case serverError(Error)
    case invalidIPAddress
    case invalidPort
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "Invalid file metadata received"
        case .fileReadError(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .fileWriteError(let error):
            return "Failed to write file: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .serverError(let error):
            return "Server error: \(error.localizedDescription)"
        case .invalidIPAddress:
            return "Invalid IP address"
        case .invalidPort:
            return "Invalid port number"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}