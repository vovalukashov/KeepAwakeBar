import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var systemDisabled: Bool?
    @Published private(set) var isBusy = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var options: CaffeinateOptions {
        didSet {
            if let data = try? JSONEncoder().encode(options) {
                UserDefaults.standard.set(data, forKey: "caffeinateOptions")
            }
        }
    }
    let caffeinate = CaffeinateController()
    private let sleepService = SystemSleepService(authorizer: SessionSleepAuthorizer.shared)
    @Published private(set) var administratorReady = false
    private var pollingTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "caffeinateOptions"),
           let saved = try? JSONDecoder().decode(CaffeinateOptions.self, from: data) {
            options = saved
        } else { options = CaffeinateOptions() }
        // Explicit one-time relaunch after an update. Normal launches stay off.
        if CommandLine.arguments.contains("--resume-caffeinate") {
            caffeinate.start(options: options)
        }
        isBusy = true
        Task {
            do {
                try await SessionSleepAuthorizer.shared.prepare()
                administratorReady = true
            } catch {
                showError(error.localizedDescription)
            }
            isBusy = false
            await refresh()
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { break }
            }
        }
    }

    func refresh() async {
        guard !isBusy, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            systemDisabled = try await sleepService.readDisabled()
            errorMessage = nil
        } catch {
            systemDisabled = nil
            errorMessage = error.localizedDescription
        }
    }

    func setSystemDisabled(_ disabled: Bool) {
        guard administratorReady, !isBusy, !isRefreshing, systemDisabled != nil else { return }
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                systemDisabled = try await sleepService.setDisabled(disabled)
            } catch {
                let failure = error.localizedDescription
                // Cancellation/failure is never treated as a successful toggle.
                systemDisabled = try? await sleepService.readDisabled()
                errorMessage = failure
                showError(failure)
            }
        }
    }

    func showError(_ message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "KeepAwakeBar"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func quit() {
        guard !isBusy else { return }
        pollingTask?.cancel()
        caffeinate.stopForQuit()
        NSApplication.shared.terminate(nil)
    }
}
