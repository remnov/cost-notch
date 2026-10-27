import CoreGraphics
import Foundation

public enum OverlayHotspot {
    public static let topEdgeHeight: CGFloat = 10

    public static func topEdgeFrame(screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - topEdgeHeight,
            width: screenFrame.width,
            height: topEdgeHeight
        )
    }

    public static func contains(
        _ point: CGPoint,
        screenFrame: CGRect,
        collapsedFrame: CGRect
    ) -> Bool {
        guard screenFrame.contains(point) else { return false }
        return topEdgeFrame(screenFrame: screenFrame).contains(point)
            || collapsedFrame.insetBy(dx: -16, dy: -6).contains(point)
    }

    public static func pickOverlayScreen(
        builtIn: CGRect?,
        notched: CGRect?,
        fallback: CGRect?
    ) -> CGRect? {
        builtIn ?? notched ?? fallback
    }
}
