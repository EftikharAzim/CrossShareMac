import Foundation
import Combine

class AndroidBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate {
    private var browser: NetServiceBrowser!
    @Published var discoveredDevices: [NetService] = []
    private var resolvingServices = Set<String>() // Track resolving services
    
    func startBrowsing() {
        browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_fileshare._tcp", inDomain: "")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser,
                          didFind service: NetService,
                          moreComing: Bool) {
        print("netServiceBrowser[+]")
        guard !service.name.starts(with: "Mac-") else { return }
        
        // Skip if already resolving or discovered
        guard !resolvingServices.contains(service.name),
              !discoveredDevices.contains(where: { $0.name == service.name })
        else { return }
        
        print("Adding devices...")
        resolvingServices.insert(service.name) // Mark as resolving
        discoveredDevices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
        print("netServiceBrowser[+]")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser,
                          didRemove service: NetService,
                          moreComing: Bool) {
        print("netServiceBrowser[+]")
        print("Remvoing devices...")
        DispatchQueue.main.async { [weak self] in
            self?.discoveredDevices.removeAll { $0.name == service.name }
            self?.resolvingServices.remove(service.name)
        }
        print("netServiceBrowser[+]")
    }
}

extension AndroidBrowser: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("netServiceDidResolveAddress[+]")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Add to discoveredDevices if not already present
            if !self.discoveredDevices.contains(where: { $0.name == sender.name }) {
                self.discoveredDevices.append(sender)
            }
            self.resolvingServices.remove(sender.name) // Remove from resolving set
        }
        print("netServiceDidResolveAddress[-]")
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("netService[+]")
        DispatchQueue.main.async { [weak self] in
            self?.resolvingServices.remove(sender.name) // Cleanup on failure
        }
        print("netService[-]")
    }
}
