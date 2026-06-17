import Foundation

/// Minimal helper for running a command-line tool and capturing its stdout.
/// stderr is discarded so tool warnings don't pollute parsing.
enum Shell {
    /// Run `executablePath` with `arguments`, returning stdout. If `timeout` is
    /// given and the process outlives it, the process is terminated and "" is
    /// returned — used to keep an unreachable daemon (e.g. docker) from stalling.
    static func run(_ executablePath: String,
                    _ arguments: [String],
                    timeout: TimeInterval? = nil) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                return ""
            }
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
