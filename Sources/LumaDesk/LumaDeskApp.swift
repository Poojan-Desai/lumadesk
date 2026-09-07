import AppKit
import SwiftUI

@main
struct LumaDeskApp: App {
    @StateObject private var model = WorkspaceModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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
                    .disabled(model.isBusy)
                Button("Export Search Results…") { model.exportResults() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.hits.isEmpty)
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
