import SwiftUI

struct ContentView: View {
    @StateObject private var advertiser = MacAdvertiser()
    @StateObject private var browser = AndroidBrowser()
    
    var body: some View {
        VStack {
            Text("Mac Device")
                .font(.title)
            
            // Discovered Android Devices
            List(browser.discoveredDevices, id: \.name) { service in
                Text("Android: \(service.name)")
            }
        }
        .padding()
        .onAppear {
            advertiser.startAdvertising()
            browser.startBrowsing()
        }
    }
}
