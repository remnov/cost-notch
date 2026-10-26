import AppKit
import Combine
import CursorCostCore
import SwiftUI

@MainActor
final class NotchWindowController: NSObject {
    private let store: UsageStore
    private let settings: AppSettings
    private let onOpenSettings: () -> Void
    private let viewModel: NotchViewModel
    private var panel: NotchPanel
    private var trackingView: NotchTrackingView?
    private var cancellables: Set<AnyCancellable> = []
    private var collapseWork: DispatchWorkItem?
    private var isExpanded = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(store: UsageStore, settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        let geometry = NotchGeometry.preferredScreen().map(NotchGeometry.detect)
            ?? NotchGeometry(screenFrame: .zero, notchWidth: 185, notchHeight: 32, hasNotch: false)
        self.viewModel = NotchViewModel(geometry: geometry)
        let frame = geometry.collapsedFrame()
        self.panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        installContent(geometry: geometry)
        panel.setFrame(frame, display: true)
        applyVisibility()
        startMouseMonitor()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)
        settings.$preferences
            .map(\.showNotch)
            .removeDuplicates()
            .sink { [weak self] show in
                self?.applyVisibility(show)
            }
            .store(in: &cancellables)
    }

    func destroy() {
        collapseWork?.cancel()
        stopMouseMonitor()
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    func applyVisibility() {
        applyVisibility(settings.preferences.showNotch)
    }

    private func applyVisibility(_ show: Bool) {
        if show {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func installContent(geometry: NotchGeometry) {
        let tracking = NotchTrackingView(frame: NSRect(origin: .zero, size: geometry.collapsedFrame().size))
        tracking.autoresizingMask = [.width, .height]
        tracking.onMouseEntered = { [weak self] in self?.expand() }
        tracking.onMouseExited = { [weak self] in self?.scheduleCollapse() }

        let root = NotchContentView(
            store: store,
            viewModel: viewModel,
            onOpenSettings: { [weak self] in
                self?.collapse()
                self?.onOpenSettings()
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = tracking.bounds
        hosting.autoresizingMask = [.width, .height]
        tracking.addSubview(hosting)
        panel.contentView = tracking
        trackingView = tracking
    }

    private func startMouseMonitor() {
        let handler: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                self?.handleMouseMove()
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { _ in
            handler()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { event in
            handler()
            return event
        }
    }

    private func stopMouseMonitor() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func handleMouseMove() {
        guard settings.preferences.showNotch else { return }
        let point = NSEvent.mouseLocation
        guard let screen = NotchGeometry.screen(containing: point) else {
            scheduleCollapse()
            return
        }
        let geometry = NotchGeometry.detect(screen: screen)
        let overHotspot = geometry.containsActivation(point)
        let overPanel = panel.frame.insetBy(dx: -18, dy: -18).contains(point)
        if overHotspot || overPanel {
            expand(on: screen)
            return
        }
        scheduleCollapse()
    }

    private func expand() {
        expand(on: activeScreen())
    }

    private func expand(on screen: NSScreen?) {
        collapseWork?.cancel()
        guard let screen else { return }
        let geometry = NotchGeometry.detect(screen: screen)
        let screenChanged = geometry.screenFrame != viewModel.geometry.screenFrame
        if isExpanded, !screenChanged {
            return
        }
        if isExpanded {
            viewModel.geometry = geometry
            panel.setFrame(geometry.expandedFrame(), display: true)
            return
        }
        if screenChanged {
            viewModel.geometry = geometry
            panel.setFrame(geometry.collapsedFrame(), display: true)
        }
        isExpanded = true
        viewModel.isExpanded = true
        viewModel.geometry = geometry
        trackingView?.interactiveInset = geometry.shadowPadding
        animate(to: geometry.expandedFrame())
        Task { await store.refresh() }
    }

    private func scheduleCollapse() {
        guard isExpanded else { return }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            if self.panel.frame.insetBy(dx: -18, dy: -18).contains(point) {
                return
            }
            if let screen = NotchGeometry.screen(containing: point),
               NotchGeometry.detect(screen: screen).containsActivation(point) {
                return
            }
            self.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        viewModel.isExpanded = false
        trackingView?.interactiveInset = 0
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry.detect(screen: screen)
        let screenChanged = geometry.screenFrame != viewModel.geometry.screenFrame
        viewModel.geometry = geometry
        if screenChanged {
            panel.setFrame(geometry.collapsedFrame(), display: true)
        } else {
            animate(to: geometry.collapsedFrame())
        }
    }

    private func reposition(animated: Bool) {
        guard let screen = isExpanded ? activeScreen() : NotchGeometry.preferredScreen() else { return }
        viewModel.geometry = NotchGeometry.detect(screen: screen)
        let frame = isExpanded ? viewModel.geometry.expandedFrame() : viewModel.geometry.collapsedFrame()
        if animated {
            animate(to: frame)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func activeScreen() -> NSScreen? {
        NotchGeometry.screenMatching(viewModel.geometry.screenFrame)
            ?? NotchGeometry.screen(containing: NSEvent.mouseLocation)
            ?? NotchGeometry.preferredScreen()
    }

    private func animate(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.36
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}
