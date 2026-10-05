import Foundation
import Darwin

/// One authorization per app session. Only our PID may talk to the root helper.
actor SessionSleepAuthorizer: SystemSleepAuthorizing {
    static let shared = SessionSleepAuthorizer()
    private var socketPath: String?

    func prepare() async throws {
        if let socketPath, (try? exchange(path: socketPath, command: 80)) != nil { return }
        socketPath = nil
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/KeepAwakeBarHelper").path
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            throw SleepControlError.commandFailed("Не найден помощник KeepAwakeBar. Переустановите приложение.")
        }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, size) == size else {
            throw SleepControlError.commandFailed("Не удалось проверить процесс приложения.")
        }
        let path = "/private/tmp/KeepAwakeBar-\(UUID().uuidString).sock"
        let command = "\(Self.shellQuote(helper)) \(getpid()) \(getuid()) \(info.pbi_start_tvsec) \(Self.shellQuote(path)) </dev/null >/dev/null 2>&1 &"
        // Only system paths and generated numeric/UUID data, never passwords or user commands.
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(literal)\" with administrator privileges"
        let result = try await CommandRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.status == 0 else {
            if result.output.contains("(-128)") { throw SleepControlError.authorizationCancelled }
            throw SleepControlError.commandFailed("Не удалось запустить помощника: \(result.output)")
        }
        for _ in 0..<50 {
            if (try? exchange(path: path, command: 80)) != nil {
                socketPath = path
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw SleepControlError.commandFailed("Помощник не ответил. Перезапустите приложение, чтобы повторить авторизацию.")
    }

    func setDisabled(_ disabled: Bool) async throws {
        guard let socketPath else {
            throw SleepControlError.commandFailed("Нужны права администратора. Перезапустите приложение и подтвердите запрос macOS.")
        }
        try exchange(path: socketPath, command: disabled ? 49 : 48)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func exchange(path: String, command: UInt8) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 12, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw failure }
        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = path.withCString { strlcpy(destination, $0, capacity) }
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        var uid: uid_t = 1
        var gid: gid_t = 1
        guard connected == 0, getpeereid(fd, &uid, &gid) == 0, uid == 0 else { throw failure }
        var byte = command
        guard write(fd, &byte, 1) == 1, read(fd, &byte, 1) == 1, byte == 75 else { throw failure }
    }
    private var failure: SleepControlError {
        .commandFailed("Помощник недоступен или команда не выполнена. Перезапустите приложение для повторной авторизации.")
    }
}
