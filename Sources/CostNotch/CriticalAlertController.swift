import AppKit
import Combine
import CursorCostCore

@MainActor
final class CriticalAlertController {
    private let settings: AppSettings
    private let isSettingsVisible: () -> Bool
    private var cancellable: AnyCancellable?

    init(settings: AppSettings, store: UsageStore, isSettingsVisible: @escaping () -> Bool = { false }) {
        self.settings = settings
        self.isSettingsVisible = isSettingsVisible
        cancellable = store.$cursorSnapshot.sink { [weak self] snapshot in
            self?.handle(snapshot)
        }
    }

    private func handle(_ snapshot: UsageSnapshot) {
        guard settings.preferences.showCriticalAlert else { return }
        guard case .ready(let data) = snapshot else { return }
        guard let newest = data.recentQueries.max(by: { $0.timestamp < $1.timestamp }) else {
            return
        }
        let ageMs = Date().timeIntervalSince1970 * 1000 - newest.timestamp
        if ageMs > 5 * 60 * 1000 {
            return
        }
        let key = UsageMapper.queryAlertKey(newest)
        if settings.lastAlertedQueryKey == key {
            return
        }
        guard UsageMapper.isCritical(newest, preferences: settings.preferences) else {
            return
        }
        settings.lastAlertedQueryKey = key
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Cost Notch · Cursor"
        alert.informativeText =
            "This Cursor query used \(Formatting.tokens(newest.tokens)) tokens and \(Formatting.dollars(newest.costUsd))."
        alert.addButton(withTitle: "OK")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            if !self.isSettingsVisible() {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
