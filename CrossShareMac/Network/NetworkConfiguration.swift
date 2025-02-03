import Foundation

struct NetworkConfiguration {
    static let shared = NetworkConfiguration()
    
    // Service Discovery
    let serviceDomain = ""
    let serviceType = "_fileshare._tcp"
    let servicePort: UInt16 = 8080
    
    // File Transfer
    let chunkSize = 4096
    let metadataDelimiter = "|"
    
    // Connection Timeouts
    let connectionTimeout: TimeInterval = 30
    let transferTimeout: TimeInterval = 300
    
    private init() {}
    
    func generateDeviceName() -> String {
        return "Mac-\(Host.current().name!)"
    }
    
    func isValidIPv4(_ ip: String) -> Bool {
        return ip.contains(".")
    }
}