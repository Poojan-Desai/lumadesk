import AppKit
import SwiftUI

@main
struct LumaDeskApp: App {
    @StateObject private var model: WorkspaceModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        let temporary = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("LumaDesk-demo-\(UUID().uuidString)/library.json") : nil
        _model = StateObject(wrappedValue: WorkspaceModel(storageURL: temporary, demoMode: demo))
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .tint(.indigo)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Documents…") { model.chooseFiles() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.isBusy || model.isDemo)
                Button("Export Search Results…") { model.exportResults() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.canExportResults)
            }
            CommandGroup(after: .appInfo) {
                Button("Privacy & Local AI") { model.showPrivacy = true }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
