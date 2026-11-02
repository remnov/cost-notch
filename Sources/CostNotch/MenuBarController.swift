import AppKit
import Combine
import CursorCostCore

@MainActor
final class MenuBarController: NSObject {
    private let store: UsageStore
    private let updates: AppUpdateController
    private let onOpenSettings: () -> Void
    private let currentItem: NSStatusItem
    private let todayItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore, updates: AppUpdateController, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.updates = updates
        self.onOpenSettings = onOpenSettings
        self.todayItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.currentItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        style(currentItem.button)
        style(todayItem.button)
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
        updates.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.render()
            }
            .store(in: &cancellables)
        render()
    }

    private func style(_ button: NSStatusBarButton?) {
        button?.font = Self.menuBarFont
    }

    private func setTitle(_ title: String, on button: NSStatusBarButton?) {
        guard let button else { return }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Self.menuBarFont,
            .foregroundColor: NSColor.menuBarTitle,
        ])
        button.contentTintColor = nil
    }

    private func render() {
        let presentations = store.visiblePresentations
        let left = presentations.first?.presentation ?? store.presentation
        let dual = store.isDualView && presentations.count > 1
        showAppIcon(true, on: currentItem.button)
        setTitle(" \(left.currentCompact)", on: currentItem.button)
        currentItem.button?.toolTip = "\(left.providerTitle) · \(left.currentText)\n\(left.statusMessage)"

        if dual, let right = presentations.dropFirst().first {
            todayItem.isVisible = true
            showAppIcon(true, on: todayItem.button)
            setTitle(" \(right.presentation.currentCompact)", on: todayItem.button)
            todayItem.button?.toolTip = "\(right.presentation.providerTitle) · \(right.presentation.currentText)\n\(right.presentation.statusMessage)"
        } else if let today = left.todayCompact ?? left.todayText {
            todayItem.isVisible = true
            showAppIcon(true, on: todayItem.button)
            setTitle(" \(today)", on: todayItem.button)
            todayItem.button?.toolTip = (left.todayText.map { "\(left.todayLabel) · \($0)" } ?? left.todayLabel)
                + "\n\(left.statusMessage)"
        } else {
            todayItem.isVisible = false
        }
        rebuildMenu()
    }

    private func showAppIcon(_ show: Bool, on button: NSStatusBarButton?) {
        guard let button else { return }
        if show, let icon = Self.statusIcon?.copy() as? NSImage {
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
        }
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
        if let message = updates.statusMessage {
            menu.addItem(header(message))
        }
        let checkTitle = updates.isChecking ? "Checking…" : "Check for Updates"
        let check = action(checkTitle, #selector(checkForUpdates))
        check.isEnabled = !updates.isChecking && !updates.isInstalling
        menu.addItem(check)
        if let version = updates.offeredVersion {
            let title = updates.isInstalling ? "Updating…" : "Update to \(version)"
            let item = action(title, #selector(installUpdate))
            item.isEnabled = !updates.isInstalling
            menu.addItem(item)
        }
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

    private static let statusIcon: NSImage? = makeStatusIcon()

    private static func makeStatusIcon() -> NSImage? {
        guard let source = loadAppIcon(),
              let tiff = source.tiffRepresentation,
              let sourceRep = NSBitmapImageRep(data: tiff),
              let sourceData = sourceRep.bitmapData else { return nil }
        let sourceWidth = sourceRep.pixelsWide
        let sourceHeight = sourceRep.pixelsHigh
        let sourceBytes = max(sourceRep.bitsPerPixel / 8, 1)
        let points: CGFloat = 18
        let pixels = 72
        let radius = Double(pixels) * 0.2237
        let side = Double(pixels)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixels * 4,
            bitsPerPixel: 32
        ), let destination = rep.bitmapData else { return nil }
        rep.size = NSSize(width: points, height: points)
        for y in 0..<pixels {
            for x in 0..<pixels {
                let sourceX = min(sourceWidth - 1, x * sourceWidth / pixels)
                let sourceY = min(sourceHeight - 1, y * sourceHeight / pixels)
                let sourceOffset = sourceY * sourceRep.bytesPerRow + sourceX * sourceBytes
                let luminance = Self.luminance(sourceData, sourceOffset)
                var mask = Self.iconCoverage(x: Double(x) + 0.5, y: Double(y) + 0.5, side: side, radius: radius)
                if y < pixels * 16 / 100, luminance < 28 {
                    mask = 0
                }
                if luminance > 100 {
                    mask = 0
                } else if luminance > 72 {
                    mask *= Double(100 - luminance) / 28
                }
                let offset = y * rep.bytesPerRow + x * 4
                destination[offset] = 0
                destination[offset + 1] = 0
                destination[offset + 2] = 0
                destination[offset + 3] = UInt8(min(255, max(0, Int(mask * 255))))
            }
        }
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func iconCoverage(x: Double, y: Double, side: Double, radius: Double) -> Double {
        let centerX = min(max(x, radius), side - radius)
        let centerY = min(max(y, radius), side - radius)
        let dx = x - centerX
        let dy = y - centerY
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= radius - 0.6 {
            return 1
        }
        if distance >= radius + 0.6 {
            return 0
        }
        return (radius + 0.6 - distance) / 1.2
    }

    private static func luminance(_ data: UnsafeMutablePointer<UInt8>, _ offset: Int) -> Int {
        let red = Int(data[offset])
        let green = Int(data[offset + 1])
        let blue = Int(data[offset + 2])
        return (red * 30 + green * 59 + blue * 11) / 100
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

    @objc private func checkForUpdates() {
        Task { await updates.checkForUpdates() }
    }

    @objc private func installUpdate() {
        Task { await updates.install() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension MenuBarController {
    static let menuBarFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
}

private extension NSColor {
    static let menuBarTitle = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .white
        }
        return .black
    }
}
