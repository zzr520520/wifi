import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var cracker = AirCrackRunner()
    @State private var wifiList: [[String: Any]] = []
    @State private var isScanning: Bool = false

    // 目标与文件状态
    @State private var selectedSSID: String = ""
    @State private var selectedBSSID: String = ""
    @State private var selectedCapURL: URL? = nil
    @State private var selectedDictURL: URL? = nil

    @State private var showCapPicker: Bool = false
    @State private var showDictPicker: Bool = false
    @State private var useBuiltinDict: Bool = true

    var body: some View {
        NavigationView {
            Form {
                // 1. 周边 WiFi 扫描
                Section(header: Text("周边热点 (点击自动填入 BSSID)")) {
                    Button(action: scanWiFi) {
                        HStack {
                            Label(isScanning ? "正在扫描..." : "刷新周边 WiFi", systemImage: "wifi")
                            if isScanning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isScanning || cracker.isRunning)

                    List(wifiList, id: \.description) { item in
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
                                    Text(bssid).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(rssi) dBm").font(.caption2).foregroundColor(.blue)
                            }
                        }
                    }
                }

                // 2. CAP 爆破配置
                Section(header: Text("CAP 握手包极速爆破")) {
                    HStack {
                        Text("目标 AP")
                        Spacer()
                        Text(selectedSSID.isEmpty ? "未选择" : "\(selectedSSID)")
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("握手包 (.cap)")
                        Spacer()
                        Button(selectedCapURL == nil ? "选择文件" : selectedCapURL!.lastPathComponent) {
                            showCapPicker = true
                        }
                        .foregroundColor(selectedCapURL == nil ? .red : .green)
                    }

                    Toggle("使用内置百万精选字典", isOn: $useBuiltinDict)

                    if !useBuiltinDict {
                        HStack {
                            Text("外置字典 (.txt)")
                            Spacer()
                            Button(selectedDictURL == nil ? "选择外部大字典" : selectedDictURL!.lastPathComponent) {
                                showDictPicker = true
                            }
                            .foregroundColor(.orange)
                        }
                    }

                    if cracker.isRunning {
                        Button(action: { cracker.stopCrack() }) {
                            HStack {
                                Spacer()
                                Label("停止计算", systemImage: "stop.fill").foregroundColor(.red).fontWeight(.bold)
                                Spacer()
                            }
                        }
                    } else {
                        Button(action: startOfflineCrack) {
                            HStack {
                                Spacer()
                                Label("开始极速跑包", systemImage: "bolt.fill").fontWeight(.bold)
                                Spacer()
                            }
                        }
                        .disabled(selectedCapURL == nil)
                    }
                }

                // 3. 实时终端日志
                Section(header: Text("计算引擎日志 (每秒数万次)")) {
                    ScrollView {
                        Text(cracker.logs.isEmpty ? "等待任务启动...\n" : cracker.logs)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
            }
            .navigationTitle("WiFiTool Pro")
            // 握手包选择器
            .fileImporter(isPresented: $showCapPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { res in
                if case .success(let urls) = res, let url = urls.first {
                    self.selectedCapURL = copyToSandbox(url: url)
                }
            }
            // 外部字典选择器
            .fileImporter(isPresented: $showDictPicker, allowedContentTypes: [.plainText, .item], allowsMultipleSelection: false) { res in
                if case .success(let urls) = res, let url = urls.first {
                    self.selectedDictURL = copyToSandbox(url: url)
                }
            }
        }
    }

    private func scanWiFi() {
        self.isScanning = true
        WiFiScanner.scanAvailableNetworks { results, _ in
            self.isScanning = false
            if let list = results, !list.isEmpty { self.wifiList = list }
        }
    }

    private func copyToSandbox(url: URL) -> URL? {
        let fm = FileManager.default
        let dest = fm.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: dest)
        _ = url.startAccessingSecurityScopedResource()
        try? fm.copyItem(at: url, to: dest)
        url.stopAccessingSecurityScopedResource()
        return dest
    }

    private func startOfflineCrack() {
        guard let capURL = selectedCapURL else { return }
        var finalDictPath = ""

        if useBuiltinDict {
            finalDictPath = Bundle.main.path(forResource: "wordlist", ofType: "txt") ?? ""
        } else if let customDict = selectedDictURL {
            finalDictPath = customDict.path
        }

        if finalDictPath.isEmpty || !FileManager.default.fileExists(atPath: finalDictPath) {
            cracker.logs = "❌ 未找到有效字典文件！\n"
            return
        }

        cracker.startCrack(capPath: capURL.path, dictPath: finalDictPath, bssid: selectedBSSID)
    }
}
