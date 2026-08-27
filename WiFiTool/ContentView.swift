import SwiftUI

struct ContentView: View {
    @StateObject private var crackManager = CrackManager()
    @State private var networks: [NSDictionary] = []
    @State private var isScanning = false
    @State private var selectedNetwork: String = ""
    @State private var capFilePath = ""
    @State private var wordlistPath = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    Section(header: Text("WiFi 扫描结果")) {
                        if isScanning {
                            HStack {
                                ProgressView()
                                Text("扫描中...")
                                    .foregroundColor(.gray)
                            }
                        }
                        ForEach(networks.indices, id: \.self) { index in
                            let net = networks[index]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(net["ssid"] as? String ?? "未知网络")
                                    .font(.headline)
                                HStack {
                                    Text(net["bssid"] as? String ?? "")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("RSSI: \(net["rssi"] as? Int ?? 0)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .onTapGesture {
                                selectedNetwork = net["bssid"] as? String ?? ""
                            }
                        }
                    }

                    Section(header: Text("握手包爆破")) {
                        TextField("CAP 文件路径", text: $capFilePath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("字典文件路径", text: $wordlistPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("目标 BSSID", text: $selectedNetwork)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            crackManager.runAircrack(
                                capFilePath: capFilePath,
                                wordlistPath: wordlistPath,
                                bssid: selectedNetwork
                            )
                        }) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text("开始爆破")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(crackManager.isRunning ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(crackManager.isRunning)
                    }

                    if !crackManager.progressLogs.isEmpty {
                        Section(header: Text("爆破日志")) {
                            ScrollView {
                                Text(crackManager.progressLogs)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 200)
                        }
                    }
                }

                HStack {
                    Button(action: {
                        isScanning = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            let results = WiFiScanner.scanAvailableNetworks()
                            DispatchQueue.main.async {
                                networks = results
                                isScanning = false
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "wifi")
                            Text("扫描周边WiFi")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isScanning)
                    .padding()
                }
            }
            .navigationTitle("WiFiTool")
        }
    }
}
