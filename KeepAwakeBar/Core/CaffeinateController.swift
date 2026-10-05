import Foundation
import Combine

@MainActor
final class CaffeinateController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStopping = false
    @Published private(set) var pid: Int32?
    @Published private(set) var errorMessage: String?
    private var process: Process?

    func start(options: CaffeinateOptions) {
        guard process == nil, options.isValid else { return }
        errorMessage = nil
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        child.arguments = options.arguments(ownerPID: ProcessInfo.processInfo.processIdentifier)
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                let expected = self.isStopping
                self.process = nil
                self.isRunning = false
                self.isStopping = false
                self.pid = nil
                if !expected {
                    self.errorMessage = "Caffeinate exited (status \(ended.terminationStatus))."
                }
            }
        }
        do {
            try child.run()
            process = child
            pid = child.processIdentifier
            isRunning = child.isRunning
        } catch {
            errorMessage = "Could not start Caffeinate: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let process else { return }
        isStopping = true
        if process.isRunning { process.terminate() }
    }

    func stopForQuit() {
        // -w also covers forced termination; never kill other caffeinate instances.
        if let process, process.isRunning { process.terminate() }
    }
}
