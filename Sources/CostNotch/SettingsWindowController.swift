import AppKit
import CursorCostCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: UsageStore
    private let updates: AppUpdateController
    private var window: NSWindow?
    var onClose: (() -> Void)?
    var isVisible: Bool { window?.isVisible == true }

    init(settings: AppSettings, store: UsageStore, updates: AppUpdateController) {
        self.settings = settings
        self.store = store
        self.updates = updates
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, store: store, updates: updates)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Cost Notch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose?()
    }
}
