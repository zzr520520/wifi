import Foundation
import UIKit

class AirCrackRunner: ObservableObject {
    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var keyFound: String? = nil

    private var taskRunner: AsyncTaskRunner?

    func startCrack(capPath: String, dictPath: String, bssid: String) {
        self.isRunning = true
        self.logs = "🚀 正在初始化 ARM64 爆破引擎...\n"
        self.keyFound = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

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

            // 构造参数：-a 2 (WPA/WPA2), -b (目标BSSID), -w (字典路径), cap文件
            var args = ["-a", "2", "-w", dictPath, capPath]
            if !bssid.isEmpty {
                args.append(contentsOf: ["-b", bssid])
            }

            DispatchQueue.main.async {
                let runner = AsyncTaskRunner()
                self.taskRunner = runner

                runner.onOutput = { [weak self] output in
                    guard let self = self else { return }
                    guard let output = output else { return }
                    // 过滤回车符，实时更新日志
                    let cleanStr = output.replacingOccurrences(of: "\r", with: "\n")
                    self.logs += cleanStr

                    // 检测 KEY FOUND!
                    if cleanStr.contains("KEY FOUND!") {
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

                runner.onCompletion = { [weak self] status in
                    guard let self = self else { return }
                    self.isRunning = false
                    if let found = self.keyFound {
                        self.logs += "\n🎉🎉🎉 爆破成功！密码: [ \(found) ] (已自动复制到剪贴板)\n"
                    } else {
                        self.logs += "\n⚠️ 任务结束：当前字典已全部跑完，未找到匹配密码。\n"
                    }
                }

                runner.launch(withPath: binaryPath, arguments: args)
            }
        }
    }

    func stopCrack() {
        taskRunner?.terminate()
        isRunning = false
        logs += "\n⏹️ 任务已手动终止。\n"
    }
}
