import Foundation

// ========================================================================
// CrackManager.swift - 方案B：握手包爆破调用桥接
// 使用 ProcessRunner (ObjC posix_spawn 包装) 执行子进程
// ========================================================================

class CrackManager: ObservableObject {
    @Published var progressLogs: String = ""
    @Published var isRunning: Bool = false

    func runAircrack(capFilePath: String, wordlistPath: String, bssid: String) {
        self.isRunning = true
        self.progressLogs = "开始解析任务...\n"

        DispatchQueue.global(qos: .userInitiated).async {
            guard let binaryPath = Bundle.main.path(forResource: "aircrack-ng", ofType: nil) else {
                DispatchQueue.main.async {
                    self.progressLogs += "错误：未找到 aircrack-ng 执行文件\n"
                    self.isRunning = false
                }
                return
            }

            chmod(binaryPath, 0o755)

            let arguments = ["-a", "2", "-b", bssid, "-w", wordlistPath, capFilePath]
            let output = ProcessRunner.runCommand(binaryPath, arguments: arguments)

            DispatchQueue.main.async {
                self.progressLogs += output
                self.progressLogs += "\n任务结束。"
                self.isRunning = false
            }
        }
    }
}
