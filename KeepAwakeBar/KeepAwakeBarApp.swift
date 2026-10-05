import SwiftUI
import AppKit

@main
struct KeepAwakeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            AwakeMenu(model: model, caffeinate: model.caffeinate)
                .onAppear {
                    delegate.model = model
                    Task { await model.refresh() }
                }
        } label: {
            StatusIcon(model: model, caffeinate: model.caffeinate)
                .onAppear { delegate.model = model }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Do not abandon an authorization request which may still change global state.
        model?.isBusy == true ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.caffeinate.stopForQuit()
    }
}

private struct StatusIcon: View {
    @ObservedObject var model: AppModel
    @ObservedObject var caffeinate: CaffeinateController
    private var state: OwlState {
        OwlState.resolve(systemDisabled: model.systemDisabled, caffeinate: caffeinate.isRunning)
    }
    var body: some View {
        Image(state.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("KeepAwakeBar")
            .accessibilityValue(state.description)
            .help(state.description)
    }
}

private struct AwakeMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var caffeinate: CaffeinateController

    var body: some View {
        Toggle("Caffeinate", isOn: Binding(
            get: { caffeinate.isRunning },
            set: { if $0 { caffeinate.start(options: model.options) } else { caffeinate.stop() } }))
            .disabled(caffeinate.isStopping)
        Toggle("Disable Sleep", isOn: Binding(
            get: { model.systemDisabled ?? false },
            set: { model.setSystemDisabled($0) }))
            .disabled(model.isBusy || model.isRefreshing || !model.administratorReady || model.systemDisabled == nil)
        Divider()
        Button("Quit") { model.quit() }
            .keyboardShortcut("q")
            .disabled(model.isBusy)
        .onChange(of: caffeinate.errorMessage) { message in
            if let message { model.showError(message) }
        }
    }
}
