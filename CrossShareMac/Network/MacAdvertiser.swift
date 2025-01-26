//
//  MacAdvertiser.swift
//  CrossShareMac
//
//  Created by Eftikhar Azim on 23/1/25.
//

import Foundation
import Network

class MacAdvertiser: NSObject, ObservableObject, NetServiceDelegate {
    private var netService: NetService!
    
    func startAdvertising() {
        netService = NetService(domain: "",
                               type: "_fileshare._tcp",
                               name: "Mac-\(Host.current().name!)",
                               port: 1234)
        netService.delegate = self
        netService.publish()
    }
    func netServiceDidPublish(_ sender: NetService) {
        print("✅ Service published: \(sender.name)")
    }
    // Handle errors
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("⚠️ MacAdvertiser Error: \(errorDict)")
    }
}
