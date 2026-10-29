import CursorCostCore
import Foundation
import Testing

struct CodexUsageTests {
    @Test
    func buildCodexUsageReady_givenFiveHourAndWeeklyWindows_thenMapsPercentQuotasInWindowOrder() throws {
        let given = try json(Self.usageJSON)

        let then = UsageMapper.buildCodexUsageReady(usage: given, email: "fallback@example.com")

        #expect(then.provider == .codex)
        #expect(then.plan == "plus")
        #expect(then.email == "dev@example.com")
        #expect(then.spendDisplay == .percent)
        #expect(!then.isUnlimited)
        #expect(then.includedQuotas.map(\.name) == ["5-hour", "Weekly"])
        #expect(then.includedQuotas.map(\.percent) == [4, 18])
        #expect(then.includedLine == "5-hour 4% · Weekly 18%")
        #expect(then.recentQueries.isEmpty)
    }

    @Test
    func buildCodexUsageReady_givenWeeklyPrimaryOnly_thenUsesWeeklyAsCurrent() throws {
        let given = try json("""
            {
              "plan_type": "team",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 9,
                  "limit_window_seconds": 604800,
                  "reset_at": 1784530149
                },
                "secondary_window": null
              }
            }
            """)

        let then = UsageMapper.buildCodexUsageReady(usage: given)

        #expect(then.plan == "team")
        #expect(then.includedQuotas.map(\.name) == ["Weekly"])
        #expect(then.includedQuotas.first?.percent == 9)
    }

    @Test
    func buildCodexUsageReady_givenSwappedWindowNames_thenIdentifiesBySeconds() throws {
        let given = try json("""
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 18,
                  "limit_window_seconds": 604800
                },
                "secondary_window": {
                  "used_percent": 4,
                  "limit_window_seconds": 18000
                }
              }
            }
            """)

        let then = UsageMapper.buildCodexUsageReady(usage: given)

        #expect(then.includedQuotas.map(\.name) == ["5-hour", "Weekly"])
        #expect(then.includedQuotas.map(\.percent) == [4, 18])
    }

    @Test
    func buildCodexUsageReady_givenUnlimitedCredits_thenMarksUnlimitedAndCreditLine() throws {
        let given = try json("""
            {
              "credits": { "has_credits": true, "unlimited": true, "balance": 150 },
              "rate_limit": {
                "primary_window": { "used_percent": 0, "limit_window_seconds": 18000 }
              }
            }
            """)

        let then = UsageMapper.buildCodexUsageReady(usage: given)

        #expect(then.isUnlimited)
        #expect(then.onDemandLine == "150.00 $")
    }

    @Test
    func presentation_givenCodexWindows_thenShowsFiveHourCurrentAndWeeklySecondary() throws {
        let given = UsageMapper.buildCodexUsageReady(usage: try json(Self.usageJSON))

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.providerTitle == "Codex")
        #expect(then.currentLabel == "5-hour")
        #expect(then.todayLabel == "Weekly")
        #expect(then.currentText == "4% / 100%")
        #expect(then.currentCompact == "4%")
        #expect(then.todayText == "18% / 100%")
        #expect(then.todayCompact == "18%")
        #expect(then.currentProgress == 0.04)
        #expect(then.todayProgress == 0.18)
        #expect(then.currentTone == .green)
        #expect(then.todayTone == .green)
        #expect(then.recent.isEmpty)
    }

    @Test
    func presentation_givenCodexShowTodayOff_thenHidesWeekly() throws {
        let given = UsageMapper.buildCodexUsageReady(usage: try json(Self.usageJSON))
        var givenPreferences = NotchPreferences.standard
        givenPreferences.showToday = false

        let then = UsageMapper.presentation(.ready(given), preferences: givenPreferences)

        #expect(then.currentText == "4% / 100%")
        #expect(then.todayText == nil)
        #expect(then.todayProgress == nil)
    }

    @Test
    func presentation_givenCodexWeeklyOnlyAndShowToday_thenOmitsSecondaryBar() throws {
        let given = UsageMapper.buildCodexUsageReady(usage: try json("""
            {
              "rate_limit": {
                "primary_window": { "used_percent": 61, "limit_window_seconds": 604800 }
              }
            }
            """))

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.currentLabel == "Weekly")
        #expect(then.currentText == "61% / 100%")
        #expect(then.todayText == nil)
        #expect(then.todayProgress == nil)
    }

    @Test
    func presentation_givenCodexWindowAtCap_thenCurrentToneIsRed() throws {
        let given = UsageMapper.buildCodexUsageReady(usage: try json("""
            {
              "rate_limit": {
                "primary_window": { "used_percent": 100, "limit_window_seconds": 18000 }
              }
            }
            """))

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.currentTone == .red)
        #expect(then.currentProgress == 1)
    }

    @Test
    func presentation_givenCodexUnlimited_thenOmitsProgressBars() throws {
        let given = UsageMapper.buildCodexUsageReady(usage: try json("""
            {
              "credits": { "unlimited": true },
              "rate_limit": {
                "primary_window": { "used_percent": 4, "limit_window_seconds": 18000 },
                "secondary_window": { "used_percent": 18, "limit_window_seconds": 604800 }
              }
            }
            """))

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.currentText == "Unlimited")
        #expect(then.currentCompact == "∞")
        #expect(then.todayText == nil)
        #expect(then.currentProgress == nil)
        #expect(then.todayProgress == nil)
    }

    @Test
    func decodePreferences_givenLegacyPayloadWithoutProvider_thenDefaultsToCursor() throws {
        let given = try JSONEncoder().encode(NotchPreferences.standard)
        var object = try JSONSerialization.jsonObject(with: given) as! [String: Any]
        object.removeValue(forKey: "costProvider")
        let givenData = try JSONSerialization.data(withJSONObject: object)

        let then = try JSONDecoder().decode(NotchPreferences.self, from: givenData)

        #expect(then.costProvider == .cursor)
    }

    @Test
    func readAuth_givenFileBasedTokens_thenReturnsAccessAccountAndJwtEmail() throws {
        let givenDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: givenDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: givenDir) }
        let givenToken = openaiJWT(accountId: "acct_jwt", email: "dev@example.com", exp: 1_800_000_000)
        let givenPath = givenDir.appendingPathComponent("auth.json")
        try Data("""
            {"tokens":{"access_token":"\(givenToken)","refresh_token":"refresh-1","account_id":"acct_file"}}
            """.utf8).write(to: givenPath)

        let then = try CodexSessionStore.readAuth(authPath: givenPath)

        #expect(then.accessToken == givenToken)
        #expect(then.refreshToken == "refresh-1")
        #expect(then.accountId == "acct_file")
        #expect(then.email == "dev@example.com")
    }

    @Test
    func readAuth_givenAccountIdOnlyInJwt_thenUsesClaim() throws {
        let givenDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: givenDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: givenDir) }
        let givenToken = openaiJWT(accountId: "acct_jwt", email: "dev@example.com", exp: 1_800_000_000)
        let givenPath = givenDir.appendingPathComponent("auth.json")
        try Data("""
            {"tokens":{"access_token":"\(givenToken)"}}
            """.utf8).write(to: givenPath)

        let then = try CodexSessionStore.readAuth(authPath: givenPath)

        #expect(then.accountId == "acct_jwt")
    }

    @Test
    func defaultAuthPath_givenCodexHome_thenUsesEnvironmentDirectory() {
        let then = CodexSessionStore.defaultAuthPath(
            home: "/tmp/unused-home",
            environment: ["CODEX_HOME": "/tmp/codex-home"]
        )

        #expect(then.path == "/tmp/codex-home/auth.json")
    }

    @Test
    func defaultAuthPath_givenNoCodexHome_thenUsesDotCodexInHome() {
        let then = CodexSessionStore.defaultAuthPath(home: "/Users/dev", environment: [:])

        #expect(then.path == "/Users/dev/.codex/auth.json")
    }

    @Test
    func readAuth_givenMissingFile_thenAsksToSignIn() {
        let given = URL(fileURLWithPath: "/tmp/missing-codex-auth-\(UUID().uuidString).json")

        #expect(throws: CursorCostError.signInCodex) {
            try CodexSessionStore.readAuth(authPath: given)
        }
    }

    @Test
    func readAuth_givenAuthFileWithoutAccessToken_thenAsksToSignIn() throws {
        let givenDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: givenDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: givenDir) }
        let givenPath = givenDir.appendingPathComponent("auth.json")
        try Data(#"{"tokens":{}}"#.utf8).write(to: givenPath)

        #expect(throws: CursorCostError.signInCodex) {
            try CodexSessionStore.readAuth(authPath: givenPath)
        }
    }

    @Test
    func parseRefreshResponse_givenAccessToken_thenKeepsAccountAndUpdatesAccess() throws {
        let givenCurrent = CodexAuthTokens(
            accessToken: "old",
            refreshToken: "refresh-1",
            idToken: nil,
            accountId: "acct_file",
            email: "dev@example.com"
        )
        let given = try JSONSerialization.data(withJSONObject: [
            "access_token": "new-access",
            "refresh_token": "refresh-2",
        ])

        let then = try CodexAPIClient.parseRefreshResponse(given, current: givenCurrent)

        #expect(then.accessToken == "new-access")
        #expect(then.refreshToken == "refresh-2")
        #expect(then.accountId == "acct_file")
        #expect(then.email == "dev@example.com")
    }
}

private extension CodexUsageTests {
    static let usageJSON = """
        {
          "email": "dev@example.com",
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 4,
              "limit_window_seconds": 18000,
              "reset_at": 1793301007
            },
            "secondary_window": {
              "used_percent": 18,
              "limit_window_seconds": 604800,
              "reset_at": 1793787671
            }
          }
        }
        """
}

private func json(_ raw: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(raw.utf8))
}

private func openaiJWT(accountId: String, email: String, exp: Int) -> String {
    let payload = """
        {"exp":\(exp),"https://api.openai.com/profile":{"email":"\(email)"},"https://api.openai.com/auth":{"chatgpt_account_id":"\(accountId)"}}
        """
    return "aaa.\(base64URL(from: payload)).sig"
}

private func base64URL(from json: String) -> String {
    Data(json.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
