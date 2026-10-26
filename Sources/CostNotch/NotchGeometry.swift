import AppKit
import CursorCostCore
import SwiftUI

struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    var collapsedWidth: CGFloat {
        notchWidth + (hasNotch ? 114 : 90)
    }

    var expandedWidth: CGFloat { 420 }
    var expandedHeight: CGFloat { 400 }
    var shadowPadding: CGFloat { 18 }

    static func detect(screen: NSScreen) -> NotchGeometry {
        var width: CGFloat = 185
        var height: CGFloat = max(screen.frame.maxY - screen.visibleFrame.maxY, 32)
        var hasNotch = false
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let measured = screen.frame.width - left.width - right.width
            if measured > 80 {
                width = measured + 4
                hasNotch = true
            }
        }
        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
            hasNotch = true
        }
        return NotchGeometry(
            screenFrame: screen.frame,
            notchWidth: width,
            notchHeight: height,
            hasNotch: hasNotch
        )
    }

    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { detect(screen: $0).hasNotch }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        let frames = NSScreen.screens.map(\.frame)
        guard let frame = OverlayHotspot.screenFrame(containing: point, screens: frames) else {
            return nil
        }
        return NSScreen.screens.first { $0.frame == frame }
    }

    static func screenMatching(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame == frame }
    }

    func containsActivation(_ point: NSPoint) -> Bool {
        OverlayHotspot.contains(point, screenFrame: screenFrame, collapsedFrame: collapsedFrame())
    }

    func collapsedFrame() -> NSRect {
        NSRect(
            x: screenFrame.midX - collapsedWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: collapsedWidth,
            height: notchHeight
        )
    }

    func expandedFrame() -> NSRect {
        let width = expandedWidth + shadowPadding * 2
        let height = expandedHeight + shadowPadding
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}

final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}

final class NotchTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var interactiveInset: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inset = interactiveInset
        let interactive = bounds.insetBy(dx: inset, dy: 0)
        if point.x < interactive.minX || point.x > interactive.maxX {
            return nil
        }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
