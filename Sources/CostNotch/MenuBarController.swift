import AppKit
import Combine
import CursorCostCore

@MainActor
final class MenuBarController: NSObject {
    private let store: UsageStore
    private let onOpenSettings: () -> Void
    private let currentItem: NSStatusItem
    private let todayItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.todayItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.currentItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        style(currentItem.button)
        style(todayItem.button)
        if let icon = Self.loadAppIcon() {
            icon.size = NSSize(width: 16, height: 16)
            icon.isTemplate = true
            currentItem.button?.image = icon
            currentItem.button?.imagePosition = .imageLeading
        }
        rebuildMenu()
        store.$cursorSnapshot
            .combineLatest(store.$codexSnapshot, store.$isRefreshing)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.render()
            }
            .store(in: &cancellables)
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.render() }
            }
            .store(in: &cancellables)
        render()
    }

    private func style(_ button: NSStatusBarButton?) {
        button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    }

    private func render() {
        let presentations = store.visiblePresentations
        let left = presentations.first?.presentation ?? store.presentation
        currentItem.button?.title = " \(left.currentCompact)"
        currentItem.button?.toolTip = "\(left.providerTitle) · \(left.currentText)\n\(left.statusMessage)"
        currentItem.button?.contentTintColor = NSColor.tone(left.currentTone)

        if store.isDualView, let right = presentations.dropFirst().first?.presentation {
            todayItem.isVisible = true
            todayItem.button?.title = " \(right.currentCompact)"
            todayItem.button?.toolTip = "\(right.providerTitle) · \(right.currentText)\n\(right.statusMessage)"
            todayItem.button?.contentTintColor = NSColor.tone(right.currentTone)
        } else if let today = left.todayCompact ?? left.todayText {
            todayItem.isVisible = true
            todayItem.button?.title = " \(today)"
            todayItem.button?.toolTip = (left.todayText.map { "\(left.todayLabel) · \($0)" } ?? left.todayLabel)
                + "\n\(left.statusMessage)"
            todayItem.button?.contentTintColor = NSColor.tone(left.todayTone)
        } else {
            todayItem.isVisible = false
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        currentItem.menu = makeMenu()
        todayItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let presentations = store.visiblePresentations
        for (index, item) in presentations.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            append(item.presentation, to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(action("Refresh", #selector(refresh)))
        menu.addItem(action("Settings…", #selector(openSettings)))
        if store.isDualView {
            for item in presentations {
                let menuItem = NSMenuItem(
                    title: item.provider.dashboardMenuTitle,
                    action: #selector(openProviderDashboard(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item.provider.rawValue
                menu.addItem(menuItem)
            }
        } else {
            menu.addItem(action(store.dashboardMenuTitle, #selector(openDashboard)))
        }
        menu.addItem(.separator())
        menu.addItem(action("Quit Cost Notch", #selector(quit)))
        return menu
    }

    private func append(_ presentation: UsagePresentation, to menu: NSMenu) {
        menu.addItem(header(presentation.providerTitle))
        menu.addItem(header(presentation.statusMessage))
        menu.addItem(header("\(presentation.currentLabel)  \(presentation.currentText)"))
        if let today = presentation.todayText {
            menu.addItem(header("\(presentation.todayLabel)  \(today)"))
        }
        if !presentation.recent.isEmpty {
            menu.addItem(.separator())
            for query in presentation.recent {
                menu.addItem(header("\(query.model)  \(query.text)"))
            }
        }
    }

    private static func loadAppIcon() -> NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openDashboard() {
        NSWorkspace.shared.open(store.dashboardURL)
    }

    @objc private func openProviderDashboard(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = CostProvider(rawValue: raw) else {
            return
        }
        NSWorkspace.shared.open(store.dashboardURL(for: provider))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSColor {
    static func tone(_ tone: SpendTone) -> NSColor {
        switch tone {
        case .red:
            return NSColor(srgbRed: 0.945, green: 0.298, blue: 0.298, alpha: 1)
        case .green:
            return NSColor(srgbRed: 0.537, green: 0.820, blue: 0.522, alpha: 1)
        case .default:
            return .labelColor
        }
    }
}
