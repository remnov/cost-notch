@testable import CursorCostCore
import Foundation
import Testing

struct StaleUsageTests {
    @Test
    func failing_givenSuccessfulUsageAndRepeatedFailures_thenKeepsFiguresAndLatestError() {
        let given = UsageMapper.buildUsageReady(summary: ["individualUsage": ["onDemand": ["used": 500, "limit": 1000]]], events: [:])
        let when = UsageSnapshot.ready(given).failing(with: "First failure").failing(with: "Keychain denied")

        let then = UsageMapper.presentation(when)
        let fresh = UsageMapper.presentation(.ready(given))

        #expect(when == .stale(given, "Keychain denied"))
        #expect(then.isStale)
        #expect(then.currentText == fresh.currentText)
        #expect(then.currentCompact == fresh.currentCompact + "*")
        #expect(then.todayCompact == fresh.todayCompact.map { $0 + "*" })
        #expect(then.statusMessage == "Stale · Keychain denied")
        #expect(!UsageMapper.presentation(.ready(given)).isStale)
    }

    @Test
    func failing_givenNoSuccessfulUsage_thenShowsActionableErrorWithoutStaleFigures() {
        let when = UsageSnapshot.loading.failing(with: "Choose Refresh to allow Cursor Keychain access.")

        let then = UsageMapper.presentation(when)

        #expect(then.currentCompact == "N/A")
        #expect(then.statusMessage == "Choose Refresh to allow Cursor Keychain access.")
        #expect(!then.isStale)
    }

    @Test
    func session_givenExpiredTokenWithoutRefreshToken_thenReportsExpiredSession() async {
        let given = CursorAuthTokens(accessToken: "aaa.eyJzdWIiOiJ1c2VyX3Rlc3QiLCJleHAiOjF9.sig", refreshToken: nil, email: nil)

        await #expect(throws: CursorCostError.sessionExpired) {
            try await CursorAPIClient().session(from: given)
        }
    }
}
