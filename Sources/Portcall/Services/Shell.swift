import Foundation

/// Minimal helper for running a command-line tool and capturing its stdout.
/// stderr is discarded so tool warnings don't pollute parsing.
enum Shell {
    static func run(_ executablePath: String, _ arguments: [String]) -> String {
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
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
