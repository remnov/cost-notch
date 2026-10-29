import CursorCostCore
import Foundation
import Testing

struct DualViewTests {
    @Test
    func visibleProviders_givenDualView_thenReturnsLeftThenRight() {
        var given = NotchPreferences.standard
        given.dualView = true
        given.pillLeftProvider = .codex

        #expect(given.visibleProviders == [.codex, .cursor])
        #expect(given.pillRightProvider == .cursor)
        #expect(given.shows(.cursor))
        #expect(given.shows(.codex))
    }

    @Test
    func visibleProviders_givenSingleProvider_thenReturnsCostProviderOnly() {
        var given = NotchPreferences.standard
        given.dualView = false
        given.costProvider = .codex
        given.pillLeftProvider = .cursor

        #expect(given.visibleProviders == [.codex])
        #expect(!given.shows(.cursor))
        #expect(given.shows(.codex))
    }

    @Test
    func decodePreferences_givenLegacyPayloadWithoutDualView_thenDefaultsOff() throws {
        let given = try JSONEncoder().encode(NotchPreferences.standard)
        var object = try JSONSerialization.jsonObject(with: given) as! [String: Any]
        object.removeValue(forKey: "dualView")
        object.removeValue(forKey: "pillLeftProvider")
        let givenData = try JSONSerialization.data(withJSONObject: object)

        let then = try JSONDecoder().decode(NotchPreferences.self, from: givenData)

        #expect(!then.dualView)
        #expect(then.pillLeftProvider == .cursor)
        #expect(then.pillRightProvider == .codex)
    }

    @Test
    func presentation_givenLoadingCodexWhileCursorIsSelected_thenUsesCodexLabels() {
        var givenPreferences = NotchPreferences.standard
        givenPreferences.costProvider = .cursor

        let then = UsageMapper.presentation(
            .loading,
            preferences: givenPreferences,
            provider: .codex
        )

        #expect(then.providerTitle == "Codex")
        #expect(then.currentLabel == "5-hour")
        #expect(then.todayLabel == "Weekly")
    }
}
