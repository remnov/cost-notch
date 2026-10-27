import AppKit
import CursorCostCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let store: UsageStore
    private var window: NSWindow?
    var onClose: (() -> Void)?
    var isVisible: Bool { window?.isVisible == true }

    init(settings: AppSettings, store: UsageStore) {
        self.settings = settings
        self.store = store
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, store: store)
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
