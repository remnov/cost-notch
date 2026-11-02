import CoreGraphics
import CursorCostCore
import Foundation
import Testing

struct OverlayHotspotTests {
    @Test
    func contains_givenPointOnTopEdgeOfOverlayScreen_thenActivates() {
        let givenScreen = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let givenPoint = CGPoint(x: 2000, y: 1435)

        let then = OverlayHotspot.contains(givenPoint, screenFrame: givenScreen)

        #expect(then)
    }

    @Test
    func contains_givenPointOnLowerPill_thenDoesNotActivate() {
        let givenScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenPoint = CGPoint(x: 756, y: 960)

        let then = OverlayHotspot.contains(givenPoint, screenFrame: givenScreen)

        #expect(!then)
    }

    @Test
    func contains_givenPointOnTopEdgeOverPill_thenActivates() {
        let givenScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenPoint = CGPoint(x: 756, y: 978)

        let then = OverlayHotspot.contains(givenPoint, screenFrame: givenScreen)

        #expect(then)
    }

    @Test
    func contains_givenPointBelowTopEdgeAndOutsideCollapsed_thenDoesNotActivate() {
        let givenScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenPoint = CGPoint(x: 100, y: 900)

        let then = OverlayHotspot.contains(givenPoint, screenFrame: givenScreen)

        #expect(!then)
    }

    @Test
    func contains_givenPointOnExternalMonitor_thenDoesNotActivate() {
        let givenMacScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenPoint = CGPoint(x: 2000, y: 1435)

        let then = OverlayHotspot.contains(givenPoint, screenFrame: givenMacScreen)

        #expect(!then)
    }

    @Test
    func pickOverlayScreen_givenBuiltInAndExternal_thenUsesBuiltIn() {
        let givenBuiltIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenExternal = CGRect(x: 1512, y: -458, width: 2560, height: 1440)

        let then = OverlayHotspot.pickOverlayScreen(
            builtIn: givenBuiltIn,
            notched: givenBuiltIn,
            fallback: givenExternal
        )

        #expect(then == givenBuiltIn)
    }

    @Test
    func pickOverlayScreen_givenNoBuiltIn_thenUsesNotchedThenFallback() {
        let givenNotched = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let givenFallback = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

        let thenNotched = OverlayHotspot.pickOverlayScreen(
            builtIn: nil,
            notched: givenNotched,
            fallback: givenFallback
        )
        let thenFallback = OverlayHotspot.pickOverlayScreen(
            builtIn: nil,
            notched: nil,
            fallback: givenFallback
        )

        #expect(thenNotched == givenNotched)
        #expect(thenFallback == givenFallback)
    }
}
