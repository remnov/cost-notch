import CursorCostCore
import Foundation
import Testing

struct SessionTests {
    @Test
    func jwtFromStoredValue_givenPrefixedAndEncodedToken_thenReturnsJwt() {
        let given = "user%3A%3AeyJhbGciOiJIUzI1NiJ9.e30.sig"

        let then = CursorSessionStore.jwtFromStoredValue(given)

        #expect(then == "eyJhbGciOiJIUzI1NiJ9.e30.sig")
    }

    @Test
    func decodeJwtSub_givenPayloadWithSub_thenReturnsSubject() throws {
        let givenPayload = base64URL(from: #"{"sub":"user_123"}"#)
        let given = "aaa.\(givenPayload).sig"

        let then = CursorSessionStore.decodeJwtSub(given)

        #expect(then == "user_123")
    }

    @Test
    func buildWorkosCookie_givenSubAndToken_thenMatchesCursorPluginFormat() {
        let givenSub = "user_123"
        let givenToken = "jwt-token"

        let then = CursorSessionStore.buildWorkosCookie(sub: givenSub, accessToken: givenToken)

        #expect(then == "WorkosCursorSessionToken=user_123::jwt-token")
    }

    @Test
    func needsRefresh_givenExpiredJwt_thenReturnsTrue() {
        let given = jwt(exp: 1_700_000_000, sub: "user_123")
        let givenNow = Date(timeIntervalSince1970: 1_700_000_120)

        let then = CursorSessionStore.needsRefresh(given, now: givenNow)

        #expect(then)
    }

    @Test
    func needsRefresh_givenValidJwt_thenReturnsFalse() {
        let given = jwt(exp: 1_800_000_000, sub: "user_123")
        let givenNow = Date(timeIntervalSince1970: 1_700_000_000)

        let then = CursorSessionStore.needsRefresh(given, now: givenNow)

        #expect(!then)
    }

    @Test
    func parseRefreshResponse_givenAccessToken_thenReturnsToken() throws {
        let given = try JSONSerialization.data(withJSONObject: [
            "access_token": "new-access-jwt",
            "shouldLogout": false,
        ])

        let then = try CursorAPIClient.parseRefreshResponse(given)

        #expect(then == "new-access-jwt")
    }

    @Test
    func parseRefreshResponse_givenShouldLogout_thenThrowsSignIn() throws {
        let given = try JSONSerialization.data(withJSONObject: [
            "access_token": "",
            "shouldLogout": true,
        ])

        #expect(throws: CursorCostError.signIn) {
            try CursorAPIClient.parseRefreshResponse(given)
        }
    }

    @Test
    func session_givenRefreshedAccessToken_thenCookieUsesNewToken() throws {
        let given = jwt(exp: 1_800_000_000, sub: "user_123")

        let then = try CursorSessionStore.session(accessToken: given, email: "dev@example.com")

        #expect(then.cookie == CursorSessionStore.buildWorkosCookie(sub: "user_123", accessToken: given))
        #expect(then.email == "dev@example.com")
    }
}

struct BudgetDaysTests {
    @Test
    func workingDaysLeftInMonth_givenWeekdayInSeptember2026_thenCountsRemainingWeekdays() {
        var given = DateComponents()
        given.year = 2026
        given.month = 9
        given.day = 21
        given.hour = 12
        let givenDate = Calendar(identifier: .gregorian).date(from: given)!

        let then = UsageMapper.workingDaysLeftInMonth(givenDate)

        #expect(then == 8)
    }

    @Test
    func dailyBudgetUsd_givenRemainingAndDays_thenSplitsEvenly() {
        let givenRemaining = 219.34
        let givenDays = 8

        let then = UsageMapper.dailyBudgetUsd(givenRemaining, days: givenDays)

        #expect(then == 219.34 / 8)
    }
}

private func jwt(exp: Int, sub: String) -> String {
    "aaa.\(base64URL(from: "{\"sub\":\"\(sub)\",\"exp\":\(exp)}")).sig"
}

private func base64URL(from json: String) -> String {
    Data(json.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
