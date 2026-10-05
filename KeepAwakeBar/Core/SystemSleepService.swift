import Foundation
import IOKit

enum SleepControlError: LocalizedError {
    case unreadableState
    case commandFailed(String)
    case authorizationCancelled
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableState:
            return "macOS did not report SleepDisabled. The state is unknown. Try Refresh system state."
        case .commandFailed(let detail): return detail
        case .authorizationCancelled: return "Administrator authorization was cancelled."
        case .verificationFailed: return "The command completed, but macOS did not confirm the requested state."
        }
    }
}

/// Narrow replacement boundary for a future signed SMAppService + XPC helper.
protocol SystemSleepAuthorizing {
    func setDisabled(_ disabled: Bool) async throws
}

struct AppleScriptSleepAuthorizer: SystemSleepAuthorizing {
    static func script(disabled: Bool) -> String {
        // Only a Bool enters this command. Never interpolate paths, user text or passwords.
        "do shell script \"/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)\" with administrator privileges"
    }

    func setDisabled(_ disabled: Bool) async throws {
        let result = try await CommandRunner.run("/usr/bin/osascript", arguments: ["-e", Self.script(disabled: disabled)])
        guard result.status == 0 else {
            if result.output.contains("(-128)") { throw SleepControlError.authorizationCancelled }
            throw SleepControlError.commandFailed("Administrator command failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

struct SystemSleepService {
    let authorizer: any SystemSleepAuthorizing
    init(authorizer: any SystemSleepAuthorizing = AppleScriptSleepAuthorizer()) {
        self.authorizer = authorizer
    }

    /// Match the system-wide key exactly; `sleep 0` is a different setting.
    static func parseDisabled(_ output: String) throws -> Bool {
        var values: [Bool] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let key = words.first?.lowercased(),
                  key == "sleepdisabled" || key == "disablesleep" else { continue }
            guard words.count == 2, words[1] == "0" || words[1] == "1" else {
                throw SleepControlError.unreadableState
            }
            values.append(words[1] == "1")
        }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else {
            throw SleepControlError.unreadableState
        }
        return first
    }

    func readDisabled() async throws -> Bool {
        let result = try await CommandRunner.run("/usr/bin/pmset", arguments: ["-g"])
        guard result.status == 0 else {
            throw SleepControlError.commandFailed("Cannot read power settings: \(result.output)")
        }
        do { return try Self.parseDisabled(result.output) }
        catch {
            // On a fresh system pmset can omit the persisted key. Read the actual
            // kernel power-domain property via public IOKit registry APIs.
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            guard service != 0 else { throw SleepControlError.unreadableState }
            defer { IOObjectRelease(service) }
            guard let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  CFGetTypeID(value) == CFBooleanGetTypeID(),
                  let number = value as? NSNumber else { throw SleepControlError.unreadableState }
            return number.boolValue
        }
    }

    func setDisabled(_ disabled: Bool) async throws -> Bool {
        try await authorizer.setDisabled(disabled)
        let actual = try await readDisabled()
        guard actual == disabled else { throw SleepControlError.verificationFailed }
        return actual
    }
}
