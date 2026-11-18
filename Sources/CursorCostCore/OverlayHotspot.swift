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

    public static func contains(_ point: CGPoint, screenFrame: CGRect) -> Bool {
        let edge = topEdgeFrame(screenFrame: screenFrame)
        let xInside = point.x >= edge.minX && point.x < edge.maxX
        let yInside = point.y >= edge.minY && point.y <= edge.maxY
        return xInside && yInside
    }

    public static func pickOverlayScreen(
        builtIn: CGRect?,
        notched: CGRect?,
        fallback: CGRect?
    ) -> CGRect? {
        builtIn ?? notched ?? fallback
    }
}
