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
        store.$snapshot
            .combineLatest(store.$isRefreshing)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
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
        let presentation = store.presentation
        currentItem.button?.title = " \(presentation.currentCompact)"
        currentItem.button?.toolTip = "Current · \(presentation.currentText)"
        currentItem.button?.contentTintColor = NSColor.tone(presentation.currentTone)

        if let today = presentation.todayCompact ?? presentation.todayText {
            todayItem.isVisible = true
            todayItem.button?.title = " \(today)"
            todayItem.button?.toolTip = presentation.todayText.map { "Today · \($0)" } ?? "Today"
            todayItem.button?.contentTintColor = NSColor.tone(presentation.todayTone)
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
        let presentation = store.presentation
        menu.addItem(header("Cursor"))
        menu.addItem(header("Current  \(presentation.currentText)"))
        if let today = presentation.todayText {
            menu.addItem(header("Today  \(today)"))
        }
        if !presentation.recent.isEmpty {
            menu.addItem(.separator())
            for query in presentation.recent {
                menu.addItem(header("\(query.model)  \(query.text)"))
            }
        }
        menu.addItem(.separator())
        menu.addItem(action("Refresh", #selector(refresh)))
        menu.addItem(action("Settings…", #selector(openSettings)))
        menu.addItem(action("Open Cursor Dashboard", #selector(openDashboard)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Cost Notch", #selector(quit)))
        return menu
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
        NSWorkspace.shared.open(CursorLinks.dashboard)
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
