import Foundation

public struct UsageQuery: Sendable, Equatable {
    public var timestamp: Double
    public var model: String?
    public var kind: String?
    public var costUsd: Double
    public var tokens: Double
    public var inputTokens: Double
    public var outputTokens: Double
    public var cacheWriteTokens: Double
    public var cacheReadTokens: Double

    public init(
        timestamp: Double,
        model: String?,
        kind: String?,
        costUsd: Double,
        tokens: Double,
        inputTokens: Double,
        outputTokens: Double,
        cacheWriteTokens: Double,
        cacheReadTokens: Double
    ) {
        self.timestamp = timestamp
        self.model = model
        self.kind = kind
        self.costUsd = costUsd
        self.tokens = tokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

public struct IncludedQuota: Sendable, Equatable {
    public var name: String
    public var used: Double
    public var limit: Double
    public var percent: Double
    public init(name: String, used: Double, limit: Double, percent: Double) {
        self.name = name
        self.used = used
        self.limit = limit
        self.percent = percent
    }
}

public enum SpendDisplay: String, Sendable, Equatable {
    case usd
    case percent
}

public enum UsagePoolSource: String, Sendable, Equatable {
    case individualOnDemand
    case plan
    case teamOnDemand
    case overall
}

public struct UsagePool: Sendable, Equatable {
    public var usedCents: Double
    public var limitCents: Double?
    public var remainingCents: Double?
    public var source: UsagePoolSource

    public init(
        usedCents: Double,
        limitCents: Double?,
        remainingCents: Double?,
        source: UsagePoolSource
    ) {
        self.usedCents = usedCents
        self.limitCents = limitCents
        self.remainingCents = remainingCents
        self.source = source
    }
}

public struct UsageReady: Sendable, Equatable {
    public var email: String?
    public var plan: String?
    public var spendDisplay: SpendDisplay
    public var includedQuotas: [IncludedQuota]
    public var usedUsd: Double
    public var limitUsd: Double?
    public var remainingUsd: Double?
    public var todayUsedUsd: Double?
    public var dailyBudgetUsd: Double?
    public var workingDaysLeft: Int?
    public var billingCycleStart: String?
    public var billingCycleEnd: String?
    public var isUnlimited: Bool
    public var includedLine: String?
    public var onDemandLine: String?
    public var recentQueries: [UsageQuery]

    public init(
        email: String?,
        plan: String?,
        spendDisplay: SpendDisplay,
        includedQuotas: [IncludedQuota],
        usedUsd: Double,
        limitUsd: Double?,
        remainingUsd: Double?,
        todayUsedUsd: Double?,
        dailyBudgetUsd: Double?,
        workingDaysLeft: Int?,
        billingCycleStart: String?,
        billingCycleEnd: String?,
        isUnlimited: Bool,
        includedLine: String?,
        onDemandLine: String?,
        recentQueries: [UsageQuery]
    ) {
        self.email = email
        self.plan = plan
        self.spendDisplay = spendDisplay
        self.includedQuotas = includedQuotas
        self.usedUsd = usedUsd
        self.limitUsd = limitUsd
        self.remainingUsd = remainingUsd
        self.todayUsedUsd = todayUsedUsd
        self.dailyBudgetUsd = dailyBudgetUsd
        self.workingDaysLeft = workingDaysLeft
        self.billingCycleStart = billingCycleStart
        self.billingCycleEnd = billingCycleEnd
        self.isUnlimited = isUnlimited
        self.includedLine = includedLine
        self.onDemandLine = onDemandLine
        self.recentQueries = recentQueries
    }
}

public enum UsageSnapshot: Sendable, Equatable {
    case loading
    case ready(UsageReady)
    case error(String)
}

public enum SpendTone: String, Sendable, Equatable {
    case `default`
    case green
    case red
}

public struct RecentQueryView: Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var model: String
    public var detail: String
    public var tone: SpendTone

    public init(id: String, text: String, model: String, detail: String, tone: SpendTone) {
        self.id = id
        self.text = text
        self.model = model
        self.detail = detail
        self.tone = tone
    }
}

public struct UsagePresentation: Sendable, Equatable {
    public var currentText: String
    public var currentCompact: String
    public var todayText: String?
    public var currentTone: SpendTone
    public var todayTone: SpendTone
    public var recent: [RecentQueryView]
    public var statusMessage: String
    public var isLoading: Bool
    public var plan: String?
    public var email: String?
    public var currentProgress: Double?
    public var todayProgress: Double?
    public var todayCompact: String?

    public init(
        currentText: String,
        currentCompact: String,
        todayText: String?,
        currentTone: SpendTone,
        todayTone: SpendTone,
        recent: [RecentQueryView],
        statusMessage: String,
        isLoading: Bool,
        plan: String?,
        email: String?,
        currentProgress: Double? = nil,
        todayProgress: Double? = nil,
        todayCompact: String? = nil
    ) {
        self.currentText = currentText
        self.currentCompact = currentCompact
        self.todayText = todayText
        self.currentTone = currentTone
        self.todayTone = todayTone
        self.recent = recent
        self.statusMessage = statusMessage
        self.isLoading = isLoading
        self.plan = plan
        self.email = email
        self.currentProgress = currentProgress
        self.todayProgress = todayProgress
        self.todayCompact = todayCompact
    }
}

public struct CursorSession: Sendable, Equatable {
    public var cookie: String
    public var email: String?

    public init(cookie: String, email: String?) {
        self.cookie = cookie
        self.email = email
    }
}

public struct CursorAuthTokens: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var email: String?

    public init(accessToken: String, refreshToken: String?, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.email = email
    }
}

public enum CursorCostError: Error, Equatable, LocalizedError {
    case signIn
    case sessionRead
    case loadUsage
    case cancelled
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .signIn:
            return "Sign in to Cursor"
        case .sessionRead:
            return "Could not read Cursor session"
        case .loadUsage:
            return "Could not load usage"
        case .cancelled:
            return "Cancelled"
        case .httpStatus(401), .httpStatus(403):
            return "Sign in to Cursor"
        case .httpStatus:
            return "Could not load usage"
        }
    }
}

public enum BudgetDayBasis: String, Sendable, Codable {
    case workingDays
    case calendarDays
}

public enum CostProvider: String, Sendable, CaseIterable {
    case cursor

    public var title: String {
        switch self {
        case .cursor:
            return "Cursor"
        }
    }
}
