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
    public var provider: CostProvider

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
        recentQueries: [UsageQuery],
        provider: CostProvider = .cursor
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
        self.provider = provider
    }
}

public enum UsageSnapshot: Sendable, Equatable {
    case loading
    case ready(UsageReady)
    case stale(UsageReady, String)
    case error(String)

    func failing(with message: String) -> UsageSnapshot {
        switch self {
        case .ready(let data), .stale(let data, _):
            return .stale(data, message)
        case .loading, .error:
            return .error(message)
        }
    }
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
    public var isStale: Bool = false
    public var plan: String?
    public var email: String?
    public var currentProgress: Double?
    public var todayProgress: Double?
    public var todayCompact: String?
    public var currentLabel: String
    public var todayLabel: String
    public var providerTitle: String

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
        todayCompact: String? = nil,
        currentLabel: String = "Current",
        todayLabel: String = "Today",
        providerTitle: String = "Cursor"
    ) {
        self.currentText = currentText
        self.currentCompact = currentCompact
        self.todayText = todayText
        self.currentTone = currentTone
        self.todayTone = todayTone
        self.recent = recent
        self.statusMessage = statusMessage
        self.isLoading = isLoading
        self.isStale = false
        self.plan = plan
        self.email = email
        self.currentProgress = currentProgress
        self.todayProgress = todayProgress
        self.todayCompact = todayCompact
        self.currentLabel = currentLabel
        self.todayLabel = todayLabel
        self.providerTitle = providerTitle
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

public struct CodexAuthTokens: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var accountId: String?
    public var email: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        idToken: String?,
        accountId: String?,
        email: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountId = accountId
        self.email = email
    }
}

public enum CursorCostError: Error, Equatable, LocalizedError {
    case signIn
    case sessionRead
    case unsupportedSessionFormat
    case sessionDecryption
    case sessionExpired
    case keychainAccessDenied
    case keychainInteractionRequired
    case keychainItemMissing
    case keychainUnavailable
    case loadUsage
    case cancelled
    case httpStatus(Int)
    case signInCodex
    case sessionReadCodex
    case sessionExpiredCodex

    public var errorDescription: String? {
        switch self {
        case .signIn:
            return "Sign in to Cursor"
        case .sessionRead:
            return "Could not read Cursor session"
        case .unsupportedSessionFormat:
            return "Unsupported Cursor session format. Update Cost Notch."
        case .sessionDecryption:
            return "Could not decrypt Cursor session. Open Cursor, then Refresh."
        case .sessionExpired:
            return "Cursor session expired. Open Cursor, then Refresh."
        case .keychainAccessDenied:
            return "Cursor Keychain access denied. Choose Refresh to retry."
        case .keychainInteractionRequired:
            return "Choose Refresh to allow Cursor Keychain access. Unlock your Keychain if needed."
        case .keychainItemMissing:
            return "Cursor encryption key missing. Open Cursor and sign in, then Refresh."
        case .keychainUnavailable:
            return "Cursor Keychain unavailable. Unlock your Keychain, then Refresh."
        case .loadUsage:
            return "Could not load usage"
        case .cancelled:
            return "Cancelled"
        case .httpStatus(401):
            return "Cursor session expired. Open Cursor, then Refresh."
        case .httpStatus(403):
            return "Cursor denied usage access. Check your account permissions."
        case .httpStatus:
            return "Could not load usage"
        case .signInCodex:
            return "Sign in to Codex. Run codex login, then Refresh."
        case .sessionReadCodex:
            return "Could not read Codex session"
        case .sessionExpiredCodex:
            return "Codex session expired. Run codex login, then Refresh."
        }
    }
}

public enum BudgetDayBasis: String, Sendable, Codable {
    case workingDays
    case calendarDays
}

public enum CostProvider: String, Sendable, Codable, CaseIterable {
    case cursor
    case codex

    public var title: String {
        switch self {
        case .cursor:
            return "Cursor"
        case .codex:
            return "Codex"
        }
    }

    public var currentLabel: String {
        switch self {
        case .cursor:
            return "Current"
        case .codex:
            return "5-hour"
        }
    }

    public var secondaryLabel: String {
        switch self {
        case .cursor:
            return "Today"
        case .codex:
            return "Weekly"
        }
    }

    public var dashboardURL: URL {
        switch self {
        case .cursor:
            return URL(string: "https://cursor.com/dashboard")!
        case .codex:
            return URL(string: "https://chatgpt.com/codex")!
        }
    }

    public var dashboardMenuTitle: String {
        "Open \(title) Dashboard"
    }
}
