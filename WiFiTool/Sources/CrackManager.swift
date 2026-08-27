import Foundation

// ========================================================================
// CrackManager.swift - 方案B：握手包爆破调用桥接
// 在 App 沙盒内部执行编译好的 aircrack-ng ARM64 CLI 工具
// 通过 Process 调用子进程，实时捕获输出并更新 UI
// ========================================================================

class CrackManager: ObservableObject {
    @Published var progressLogs: String = ""
    @Published var isRunning: Bool = false

    func runAircrack(capFilePath: String, wordlistPath: String, bssid: String) {
        self.isRunning = true
        self.progressLogs = "开始解析任务...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let binaryPath = Bundle.main.path(forResource: "aircrack-ng", ofType: nil) else {
                DispatchQueue.main.async { self.progressLogs += "错误：未找到 aircrack-ng 执行文件\n"; self.isRunning = false }
                return
            }

            // 赋予执行权限
            chmod(binaryPath, 0o755)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: binaryPath)
            task.arguments = ["-a", "2", "-b", bssid, "-w", wordlistPath, capFilePath]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    DispatchQueue.main.async {
                        self.progressLogs += output
                    }
                }
            }

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.progressLogs += "执行失败: \(error.localizedDescription)\n"
                }
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.progressLogs += "\n任务结束。"
            }
        }
    }
}
