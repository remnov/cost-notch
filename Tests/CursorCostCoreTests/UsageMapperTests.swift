import CursorCostCore
import Foundation
import Testing

struct UsageMapperTests {
    @Test
    func mapEvents_givenSamplePayload_thenKeepsPricedQueriesAndDropsMissingTimestamp() throws {
        let given = try json(Self.eventsJSON)

        let then = UsageMapper.mapEventsPayload(given)

        #expect(then.count == 3)
        #expect(then[0].model == "cursor-default")
        #expect(then[0].costUsd == 0.03)
        #expect(then[0].tokens == 13_024)
        #expect(then[1].costUsd == 1.21)
        #expect(then[2].costUsd == 0.45)
        #expect(then.allSatisfy { $0.model != "should-drop-no-timestamp" })
    }

    @Test
    func pickUsagePool_givenSampleSummary_thenUsesPersonalOnDemandCents() throws {
        let given = try json(Self.summaryJSON)

        let then = UsageMapper.pickUsagePool(given)

        #expect(then?.source == .individualOnDemand)
        #expect(then?.usedCents == 379)
        #expect(then?.limitCents == 25_000)
    }

    @Test
    func buildUsageReady_givenSampleSummaryAndEvents_thenComputesCurrentTodayAndRecent() throws {
        let givenSummary = try json(Self.summaryJSON)
        let givenEvents = try json(Self.eventsJSON)
        let givenNow = Date(timeIntervalSince1970: 1_756_718_712)

        let then = UsageMapper.buildUsageReady(
            summary: givenSummary,
            events: givenEvents,
            now: givenNow,
            email: "dev@example.com"
        )

        #expect(then.plan == "pro")
        #expect(then.usedUsd == 3.79)
        #expect(then.limitUsd == 250)
        #expect(then.recentQueries.count == 3)
        #expect(then.email == "dev@example.com")
    }

    @Test
    func presentation_givenTeamStyleReadyState_thenShowsDollarCurrentAndSpikeMarker() {
        let givenQuery = UsageQuery(
            timestamp: 1,
            model: "cursor-default",
            kind: "USAGE_EVENT_KIND_USAGE_BASED",
            costUsd: 1.2,
            tokens: 1_200_000,
            inputTokens: 1_200_000,
            outputTokens: 0,
            cacheWriteTokens: 0,
            cacheReadTokens: 0
        )
        let given = UsageReady(
            email: nil,
            plan: "business",
            spendDisplay: .usd,
            includedQuotas: [],
            usedUsd: 30.66,
            limitUsd: 250,
            remainingUsd: 219.34,
            todayUsedUsd: 3.79,
            dailyBudgetUsd: 11.19,
            workingDaysLeft: 22,
            billingCycleStart: nil,
            billingCycleEnd: nil,
            isUnlimited: false,
            includedLine: nil,
            onDemandLine: "30.66 $ / 250.00 $",
            recentQueries: [givenQuery]
        )

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.currentText == "30.66 $ / 250.00 $")
        #expect(then.currentCompact == "$30.66")
        #expect(then.todayText?.hasPrefix("3.79 $ /") == true)
        #expect(then.currentTone == .green)
        #expect(then.currentProgress == 30.66 / 250)
        #expect(then.recent.first?.text == "! 1.20 $ - 1.2M")
        #expect(then.recent.first?.tone == .red)
    }

    @Test
    func presentation_givenTodayOverDailyBudget_thenTodayProgressExceedsOneAndToneIsRed() {
        let givenNow = Date(timeIntervalSince1970: 1_756_718_712)
        let givenDays = UsageMapper.budgetDaysLeftInMonth(givenNow, basis: .workingDays)
        let given = UsageReady(
            email: nil,
            plan: "pro",
            spendDisplay: .usd,
            includedQuotas: [],
            usedUsd: 143.06,
            limitUsd: 250,
            remainingUsd: 13.37 * Double(givenDays),
            todayUsedUsd: 23.50,
            dailyBudgetUsd: 13.37,
            workingDaysLeft: givenDays,
            billingCycleStart: nil,
            billingCycleEnd: nil,
            isUnlimited: false,
            includedLine: nil,
            onDemandLine: nil,
            recentQueries: []
        )

        let then = UsageMapper.presentation(.ready(given), now: givenNow)

        #expect(then.currentProgress == 143.06 / 250)
        #expect(then.todayProgress == 23.50 / 13.37)
        #expect(then.todayTone == .red)
        #expect(then.currentTone == .green)
    }

    @Test
    func presentation_givenUnlimitedPlan_thenOmitsProgressBars() {
        let given = UsageReady(
            email: nil,
            plan: "ultra",
            spendDisplay: .usd,
            includedQuotas: [],
            usedUsd: 12,
            limitUsd: nil,
            remainingUsd: nil,
            todayUsedUsd: 4,
            dailyBudgetUsd: nil,
            workingDaysLeft: nil,
            billingCycleStart: nil,
            billingCycleEnd: nil,
            isUnlimited: true,
            includedLine: nil,
            onDemandLine: nil,
            recentQueries: []
        )

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.currentProgress == nil)
        #expect(then.todayProgress == nil)
        #expect(then.todayText == nil)
    }

    @Test
    func pickUsagePool_givenEnterpriseSummary_thenUsesOverallDollarsNotPlanRequests() throws {
        let given = try json(Self.enterpriseSummaryJSON)

        let then = UsageMapper.pickUsagePool(given)
        let ready = UsageMapper.buildUsageReady(summary: given, eventsAvailable: false)

        #expect(then?.source == .overall)
        #expect(then?.usedCents == 71)
        #expect(then?.limitCents == 10_000)
        #expect(ready.isUnlimited == false)
        #expect(ready.usedUsd == 0.71)
        #expect(ready.limitUsd == 100)
        #expect(ready.spendDisplay == .usd)
    }

    @Test
    func presentation_givenSpikeWarningOff_thenKeepsSpendTones() {
        let given = UsageReady(
            email: nil,
            plan: "pro",
            spendDisplay: .usd,
            includedQuotas: [],
            usedUsd: 30.66,
            limitUsd: 250,
            remainingUsd: 4,
            todayUsedUsd: 20,
            dailyBudgetUsd: 10,
            workingDaysLeft: 22,
            billingCycleStart: nil,
            billingCycleEnd: nil,
            isUnlimited: false,
            includedLine: nil,
            onDemandLine: nil,
            recentQueries: []
        )
        var givenPreferences = NotchPreferences.standard
        givenPreferences.showSpikeWarning = false

        let then = UsageMapper.presentation(.ready(given), preferences: givenPreferences)

        #expect(then.currentTone == .green)
        #expect(then.todayTone == .red)
        #expect(then.todayCompact == "$20.00")
    }

    @Test
    func presentation_givenPercentPlanAtCap_thenCurrentToneIsRed() {
        let given = UsageReady(
            email: nil,
            plan: "pro",
            spendDisplay: .percent,
            includedQuotas: [
                IncludedQuota(name: "Cursor Models", used: 100, limit: 100, percent: 100),
                IncludedQuota(name: "Other Models", used: 100, limit: 100, percent: 100),
            ],
            usedUsd: 0,
            limitUsd: nil,
            remainingUsd: nil,
            todayUsedUsd: 0,
            dailyBudgetUsd: nil,
            workingDaysLeft: 22,
            billingCycleStart: nil,
            billingCycleEnd: nil,
            isUnlimited: false,
            includedLine: nil,
            onDemandLine: nil,
            recentQueries: []
        )

        let then = UsageMapper.presentation(.ready(given))

        #expect(then.currentTone == .red)
        #expect(then.currentProgress == 1)
    }

    @Test
    func proCurrentStatusText_givenIncludedQuotas_thenAveragesCyclePercent() {
        let given = [
            IncludedQuota(name: "Cursor Models", used: 32, limit: 100, percent: 32),
            IncludedQuota(name: "Other Models", used: 40, limit: 100, percent: 40),
        ]

        let then = UsageMapper.proCurrentStatusText(given)

        #expect(then == "36% / 100%")
    }
}

private extension UsageMapperTests {
    static let summaryJSON = """
        {
          "billingCycleStart": "2026-08-01T00:00:00.000Z",
          "billingCycleEnd": "2026-09-01T00:00:00.000Z",
          "membershipType": "pro",
          "limitType": "user",
          "isUnlimited": false,
          "individualUsage": {
            "plan": { "enabled": true, "used": 1200, "limit": 20000, "remaining": 18800 },
            "onDemand": { "enabled": true, "used": 379, "limit": 25000, "remaining": 24621 }
          }
        }
        """

    static let enterpriseSummaryJSON = """
        {
          "billingCycleStart": "2026-07-01T00:00:00.000Z",
          "billingCycleEnd": "2026-08-01T00:00:00.000Z",
          "membershipType": "enterprise",
          "limitType": "team",
          "isUnlimited": false,
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 2000,
              "limit": 2000,
              "remaining": 0,
              "autoPercentUsed": 0,
              "apiPercentUsed": 100
            },
            "onDemand": { "enabled": true, "used": 2309, "limit": null, "remaining": null },
            "overall": { "enabled": true, "used": 71, "limit": 10000, "remaining": 9929 }
          },
          "teamUsage": {
            "onDemand": { "enabled": true, "used": 0, "limit": 5000000, "remaining": 5000000 },
            "pooled": { "enabled": true, "used": 3479810, "limit": 60000000, "remaining": 56520190 }
          }
        }
        """

    static let eventsJSON = """
        {
          "usageEventsDisplay": [
            {
              "timestamp": "1756718712000",
              "model": "cursor-default",
              "kind": "USAGE_EVENT_KIND_INCLUDED_IN_BUSINESS",
              "chargedCents": 3,
              "tokenUsage": {
                "inputTokens": 12856,
                "outputTokens": 168,
                "cacheReadTokens": 0,
                "cacheWriteTokens": 0
              }
            },
            {
              "timestamp": "1756715112000",
              "model": "claude-4.6-sonnet",
              "kind": "USAGE_EVENT_KIND_USAGE_BASED",
              "tokenUsage": {
                "inputTokens": 100,
                "outputTokens": 50,
                "cacheWriteTokens": 20,
                "totalCents": 121
              }
            },
            {
              "timestamp": "1756628712000",
              "model": "composer-2",
              "usageBasedCosts": "$0.45",
              "tokenUsage": { "inputTokens": "10", "outputTokens": "5" }
            },
            { "model": "should-drop-no-timestamp", "chargedCents": 50 }
          ]
        }
        """
}

private func json(_ raw: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(raw.utf8))
}
