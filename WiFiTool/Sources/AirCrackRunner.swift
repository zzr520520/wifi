import Foundation
import UIKit

class AirCrackRunner: ObservableObject {
    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var keyFound: String? = nil

    private var process: Process?

    func startCrack(capPath: String, dictPath: String, bssid: String) {
        self.isRunning = true
        self.logs = "🚀 正在初始化 ARM64 爆破引擎...\n"
        self.keyFound = nil

        DispatchQueue.global(qos: .userInitiated).async {
            // 1. 定位打包在 App 内的 aircrack-ng 执行文件
            guard let binaryPath = Bundle.main.path(forResource: "aircrack-ng", ofType: nil) else {
                DispatchQueue.main.async {
                    self.logs += "❌ 错误：App 内部缺少 aircrack-ng 内核文件！\n"
                    self.isRunning = false
                }
                return
            }

            // 赋予执行权限
            chmod(binaryPath, 0o755)

            let task = Process()
            self.process = task
            task.executableURL = URL(fileURLWithPath: binaryPath)

            // 构造参数：-a 2 (WPA/WPA2), -b (目标BSSID), -w (字典路径), cap文件
            var args = ["-a", "2", "-w", dictPath, capPath]
            if !bssid.isEmpty {
                args.append(contentsOf: ["-b", bssid])
            }
            task.arguments = args

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            let outHandle = pipe.fileHandleForReading
            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        // 过滤终端控制字符，实时提取成功信息
                        let cleanStr = str.replacingOccurrences(of: "\r", with: "\n")
                        self.logs += cleanStr

                        if cleanStr.contains("KEY FOUND!") {
                            // 提取匹配到的密码
                            if let match = cleanStr.range(of: "\\[ (.*) \\]", options: .regularExpression) {
                                let key = String(cleanStr[match])
                                    .replacingOccurrences(of: "[", with: "")
                                    .replacingOccurrences(of: "]", with: "")
                                    .trimmingCharacters(in: .whitespaces)
                                self.keyFound = key
                                UIPasteboard.general.string = key
                            }
                        }
                    }
                }
            }

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.logs += "执行异常: \(error.localizedDescription)\n"
                }
            }

            DispatchQueue.main.async {
                self.isRunning = false
                if let found = self.keyFound {
                    self.logs += "\n🎉🎉🎉 爆破成功！密码: [ \(found) ] (已自动复制到剪贴板)\n"
                } else {
                    self.logs += "\n⚠️ 任务结束：当前字典已全部跑完，未找到匹配密码。\n"
                }
            }
        }
    }

    func stopCrack() {
        process?.terminate()
        self.isRunning = false
        self.logs += "\n⏹️ 任务已手动终止。\n"
    }
}
