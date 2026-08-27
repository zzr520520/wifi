import Foundation

// ========================================================================
// CrackManager.swift - 方案B：握手包爆破调用桥接
// iOS 上 Process 不可用，改用 posix_spawn + pipe 捕获输出
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

            // 赋予执行权限
            chmod(binaryPath, 0o755)

            // 使用 popen 执行子进程并捕获输出
            let command = "\(binaryPath) -a 2 -b \(bssid) -w \(wordlistPath) \(capFilePath) 2>&1"

            guard let pipe = popen(command, "r") else {
                DispatchQueue.main.async {
                    self.progressLogs += "错误：无法启动进程\n"
                    self.isRunning = false
                }
                return
            }

            var output = ""
            var buffer = [CChar](repeating: 0, count: 4096)

            while let bytesRead = fgets(&buffer, Int32(buffer.count), pipe) {
                let line = String(cString: bytesRead)
                output += line

                if output.count > 500 {
                    let chunk = String(output.prefix(500))
                    output = String(output.dropFirst(500))
                    DispatchQueue.main.async {
                        self.progressLogs += chunk
                    }
                }
            }

            let status = pclose(pipe)
            DispatchQueue.main.async {
                self.progressLogs += output
                self.isRunning = false
                if status == 0 {
                    self.progressLogs += "\n任务完成 (退出码: \(status))"
                } else {
                    self.progressLogs += "\n任务结束 (退出码: \(status))"
                }
            }
        }
    }
}
