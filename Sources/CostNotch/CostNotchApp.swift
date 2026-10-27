import AppKit
import Combine
import CursorCostCore
import SwiftUI

@main
struct CostNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Cost Notch Settings…") {
                    NotificationCenter.default.post(name: .openCostNotchSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openCostNotchSettings = Notification.Name("openCostNotchSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let store: UsageStore
    private var notch: NotchWindowController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var criticalAlerts: CriticalAlertController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        store = UsageStore(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let openSettings: () -> Void = { [weak self] in
            guard let window = self?.settingsWindow else { return }
            window.show()
        }
        settingsWindow = SettingsWindowController(settings: settings, store: store)
        settingsWindow?.onClose = { [weak self] in
            self?.notch?.applyVisibility()
        }
        NotificationCenter.default.publisher(for: .openCostNotchSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsWindow?.show()
            }
            .store(in: &cancellables)
        criticalAlerts = CriticalAlertController(
            settings: settings,
            store: store,
            isSettingsVisible: { [weak self] in
                self?.settingsWindow?.isVisible == true
            }
        )
        menuBar = MenuBarController(store: store, onOpenSettings: openSettings)
        notch = NotchWindowController(store: store, settings: settings, onOpenSettings: openSettings)
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.destroy()
    }
}
