import CoreGraphics
import CursorCostCore
import Foundation
import Testing

struct OverlayHotspotTests {
    @Test
    func contains_givenPointOnTopEdgeOfAnyScreen_thenActivates() {
        let givenScreen = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let givenCollapsed = CGRect(x: 3100, y: 1408, width: 200, height: 32)
        let givenPoint = CGPoint(x: 2000, y: 1435)

        let then = OverlayHotspot.contains(
            givenPoint,
            screenFrame: givenScreen,
            collapsedFrame: givenCollapsed
        )

        #expect(then)
    }

    @Test
    func contains_givenPointBelowTopEdgeAndOutsideCollapsed_thenDoesNotActivate() {
        let givenScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenCollapsed = CGRect(x: 656, y: 950, width: 200, height: 32)
        let givenPoint = CGPoint(x: 100, y: 900)

        let then = OverlayHotspot.contains(
            givenPoint,
            screenFrame: givenScreen,
            collapsedFrame: givenCollapsed
        )

        #expect(!then)
    }

    @Test
    func screenFrame_givenPointOnSecondDisplay_thenReturnsThatScreen() {
        let givenScreens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: -458, width: 2560, height: 1440),
        ]
        let givenPoint = CGPoint(x: 2000, y: 900)

        let then = OverlayHotspot.screenFrame(containing: givenPoint, screens: givenScreens)

        #expect(then == givenScreens[1])
    }
}
