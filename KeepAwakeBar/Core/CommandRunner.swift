import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
}

/// No shell interpretation. Only the authorization adapter uses a fixed AppleScript command.
enum CommandRunner {
    static func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                    // Drain before waiting so a full pipe cannot deadlock the subprocess.
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: CommandResult(
                        status: process.terminationStatus,
                        output: String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
