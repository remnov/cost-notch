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
        topEdgeFrame(screenFrame: screenFrame).contains(point)
            || collapsedFrame.insetBy(dx: -16, dy: -6).contains(point)
    }

    public static func screenFrame(containing point: CGPoint, screens: [CGRect]) -> CGRect? {
        screens.first { $0.contains(point) }
    }
}
