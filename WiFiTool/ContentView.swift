import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var cracker = CrackManager()
    @State private var wifiList: [[String: Any]] = []

    @State private var selectedSSID: String = ""
    @State private var selectedBSSID: String = ""
    @State private var selectedCapURL: URL? = nil
    @State private var showFilePicker: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // 1. 扫描与目标选择
                Section(header: Text("周边 WiFi (点击自动选择)")) {
                    Button(action: scanWiFi) {
                        Label("刷新周边 WiFi", systemImage: "wifi")
                    }

                    ForEach(wifiList.indices, id: \.self) { index in
                        let item = wifiList[index]
                        let ssid = item["ssid"] as? String ?? "未知"
                        let bssid = item["bssid"] as? String ?? ""
                        let rssi = item["rssi"] as? NSNumber ?? 0

                        Button(action: {
                            self.selectedSSID = ssid
                            self.selectedBSSID = bssid
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(ssid).font(.headline).foregroundColor(.primary)
                                    Text(bssid).font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                Text("\(rssi) dBm").font(.caption2)
                            }
                        }
                    }
                }

                // 2. 目标与握手包状态
                Section(header: Text("破解配置")) {
                    HStack {
                        Text("当前目标")
                        Spacer()
                        Text(selectedSSID.isEmpty ? "未选择" : "\(selectedSSID) (\(selectedBSSID))")
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("握手包")
                        Spacer()
                        Button(selectedCapURL == nil ? "选择 .cap 文件" : selectedCapURL!.lastPathComponent) {
                            showFilePicker = true
                        }
                    }

                    HStack {
                        Text("字典模式")
                        Spacer()
                        Text("内置精简常见字典 (内置)")
                            .foregroundColor(.secondary)
                    }

                    Button(action: startCrack) {
                        HStack {
                            Spacer()
                            Label("开始爆破", systemImage: "key.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(cracker.isRunning || selectedCapURL == nil || selectedBSSID.isEmpty)
                }

                // 3. 输出日志
                Section(header: Text("执行日志")) {
                    ScrollView {
                        Text(cracker.progressLogs.isEmpty ? "等待任务开始..." : cracker.progressLogs)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                }
            }
            .navigationTitle("WiFiTool")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let fileManager = FileManager.default
                    let tempDest = fileManager.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? fileManager.removeItem(at: tempDest)
                    _ = url.startAccessingSecurityScopedResource()
                    try? fileManager.copyItem(at: url, to: tempDest)
                    url.stopAccessingSecurityScopedResource()
                    self.selectedCapURL = tempDest
                }
            }
        }
    }

    private func scanWiFi() {
        DispatchQueue.global(qos: .userInitiated).async {
            let res = WiFiScanner.scanAvailableNetworks()
            DispatchQueue.main.async {
                if let results = res as? [[String: Any]] {
                    self.wifiList = results
                }
            }
        }
    }

    private func startCrack() {
        guard let capURL = selectedCapURL else { return }
        let defaultDictPath = Bundle.main.path(forResource: "password", ofType: "txt") ?? ""
        cracker.runAircrack(capFilePath: capURL.path, wordlistPath: defaultDictPath, bssid: selectedBSSID)
    }
}
