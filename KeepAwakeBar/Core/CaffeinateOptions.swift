import Foundation

struct CaffeinateOptions: Codable, Equatable {
    var display = true
    var idleSystem = true
    var disk = true
    var acSystem = true
    var userActivity = true

    var flags: [String] {
        [(display, "-d"), (idleSystem, "-i"), (disk, "-m"),
         (acSystem, "-s"), (userActivity, "-u")].compactMap { $0.0 ? $0.1 : nil }
    }
    var isValid: Bool { !flags.isEmpty }
    var summary: String { flags.joined(separator: " ") }
    func arguments(ownerPID: Int32) -> [String] {
        // Release assertions even if the app crashes or is killed.
        flags + ["-w", String(ownerPID)]
    }
}
