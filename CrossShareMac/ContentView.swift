import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var advertiser = MacAdvertiser()
    @StateObject private var browser = AndroidBrowser()
    @State private var selectedFileURL: URL?
    @State private var selectedDevice: NetService?
    @StateObject private var transferService = FileTransferService.shared
    
    var body: some View {
        VStack {
            Text("Mac File Share")
                .font(.title)
                .padding()
            
            // Discovered Android Devices
            List(browser.discoveredDevices, id: \.name) { service in
                Text(service.name)
                    .onTapGesture {
                        selectedDevice = service
                    }
                    .contextMenu {
                        Button("Send File") {
                            selectFile()
                        }
                    }
            }
            
            // Selected File
            if let fileURL = selectedFileURL {
                Text("Selected: \(fileURL.lastPathComponent)")
                    .padding()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers: providers)
        }
        .onAppear {
            advertiser.startAdvertising()
            browser.startBrowsing()
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            startFileTransfer()
        }
    }
    
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    selectedFileURL = url
                    startFileTransfer()
                }
            }
        }
        return true
    }
    
    private func startFileTransfer() {
        guard let device = selectedDevice else {
            print("⚠️ No device selected. Please select a device first.")
            return
        }
        
        guard let addresses = device.addresses else {
            print("⚠️ Device addresses not resolved")
            return
        }
        
        guard let port = device.port != -1 ? device.port : nil else {
            print("⚠️ Invalid port number")
            return
        }
        
        guard let fileURL = selectedFileURL else {
            print("⚠️ No file selected. Please select a file first.")
            return
        }
        
        // Find IPv4 address
        var targetIP: String?
        for address in addresses {
            let data = address as NSData
            var addr = sockaddr_in()
            data.getBytes(&addr, length: MemoryLayout<sockaddr_in>.size)
            let ip = String(cString: inet_ntoa(addr.sin_addr))
            if ip.contains(".") { // Simple IPv4 check
                targetIP = ip
                break
            }
        }
        
        guard let ip = targetIP else {
            print("🔴 No IPv4 address found in device addresses")
            return
        }
        
        print("🔗 Connecting to \(ip):\(port)")
        FileTransferService.shared.sendFile(to: ip, port: UInt16(port), fileURL: fileURL)
    }
}
