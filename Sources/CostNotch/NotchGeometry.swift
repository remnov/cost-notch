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
    var dualExpandedHeight: CGFloat { 580 }
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
        let screens = NSScreen.screens
        let builtIn = screens.first(where: isBuiltIn)?.frame
        let notched = screens.first { detect(screen: $0).hasNotch }?.frame
        let fallback = (NSScreen.main ?? screens.first)?.frame
        guard let frame = OverlayHotspot.pickOverlayScreen(
            builtIn: builtIn,
            notched: notched,
            fallback: fallback
        ) else {
            return nil
        }
        return screens.first { $0.frame == frame }
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(displayID) != 0
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

    func expandedFrame(dualView: Bool = false) -> NSRect {
        let width = expandedWidth + shadowPadding * 2
        let height = (dualView ? dualExpandedHeight : expandedHeight) + shadowPadding
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
