import Foundation

public struct NotchPreferences: Equatable, Codable, Sendable {
    public static let standard = NotchPreferences()

    public var pollIntervalMinutes: Int
    public var showToday: Bool
    public var minimalMode: Bool
    public var recentQueryCount: Int
    public var spikeTokenThreshold: Double
    public var showSpikeWarning: Bool
    public var showCriticalAlert: Bool
    public var criticalTokenThreshold: Double
    public var criticalCostUsdThreshold: Double
    public var budgetDayBasis: BudgetDayBasis
    public var showNotch: Bool
    public var costProvider: CostProvider
    public var dualView: Bool
    public var pillLeftProvider: CostProvider

    public init(
        pollIntervalMinutes: Int = 1,
        showToday: Bool = true,
        minimalMode: Bool = false,
        recentQueryCount: Int = 3,
        spikeTokenThreshold: Double = 1_000_000,
        showSpikeWarning: Bool = true,
        showCriticalAlert: Bool = true,
        criticalTokenThreshold: Double = 10_000_000,
        criticalCostUsdThreshold: Double = 5,
        budgetDayBasis: BudgetDayBasis = .workingDays,
        showNotch: Bool = true,
        costProvider: CostProvider = .cursor,
        dualView: Bool = false,
        pillLeftProvider: CostProvider = .cursor
    ) {
        self.pollIntervalMinutes = pollIntervalMinutes
        self.showToday = showToday
        self.minimalMode = minimalMode
        self.recentQueryCount = recentQueryCount
        self.spikeTokenThreshold = spikeTokenThreshold
        self.showSpikeWarning = showSpikeWarning
        self.showCriticalAlert = showCriticalAlert
        self.criticalTokenThreshold = criticalTokenThreshold
        self.criticalCostUsdThreshold = criticalCostUsdThreshold
        self.budgetDayBasis = budgetDayBasis
        self.showNotch = showNotch
        self.costProvider = costProvider
        self.dualView = dualView
        self.pillLeftProvider = pillLeftProvider
        clamp()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pollIntervalMinutes: try container.decodeIfPresent(Int.self, forKey: .pollIntervalMinutes) ?? 1,
            showToday: try container.decodeIfPresent(Bool.self, forKey: .showToday) ?? true,
            minimalMode: try container.decodeIfPresent(Bool.self, forKey: .minimalMode) ?? false,
            recentQueryCount: try container.decodeIfPresent(Int.self, forKey: .recentQueryCount) ?? 3,
            spikeTokenThreshold: try container.decodeIfPresent(Double.self, forKey: .spikeTokenThreshold) ?? 1_000_000,
            showSpikeWarning: try container.decodeIfPresent(Bool.self, forKey: .showSpikeWarning) ?? true,
            showCriticalAlert: try container.decodeIfPresent(Bool.self, forKey: .showCriticalAlert) ?? true,
            criticalTokenThreshold: try container.decodeIfPresent(Double.self, forKey: .criticalTokenThreshold) ?? 10_000_000,
            criticalCostUsdThreshold: try container.decodeIfPresent(Double.self, forKey: .criticalCostUsdThreshold) ?? 5,
            budgetDayBasis: try container.decodeIfPresent(BudgetDayBasis.self, forKey: .budgetDayBasis) ?? .workingDays,
            showNotch: try container.decodeIfPresent(Bool.self, forKey: .showNotch) ?? true,
            costProvider: try container.decodeIfPresent(CostProvider.self, forKey: .costProvider) ?? .cursor,
            dualView: try container.decodeIfPresent(Bool.self, forKey: .dualView) ?? false,
            pillLeftProvider: try container.decodeIfPresent(CostProvider.self, forKey: .pillLeftProvider) ?? .cursor
        )
    }

    public var pillRightProvider: CostProvider {
        pillLeftProvider.other
    }

    public var visibleProviders: [CostProvider] {
        dualView ? [pillLeftProvider, pillRightProvider] : [costProvider]
    }

    public func shows(_ provider: CostProvider) -> Bool {
        visibleProviders.contains(provider)
    }

    public var spikeTokenThresholdK: Int {
        get { Int((spikeTokenThreshold / 1000).rounded()) }
        set { spikeTokenThreshold = Double(max(1, newValue)) * 1000 }
    }

    public var criticalTokenThresholdK: Int {
        get { Int((criticalTokenThreshold / 1000).rounded()) }
        set { criticalTokenThreshold = Double(max(1, newValue)) * 1000 }
    }

    public mutating func clamp() {
        pollIntervalMinutes = min(60, max(1, pollIntervalMinutes))
        recentQueryCount = min(10, max(1, recentQueryCount))
        spikeTokenThreshold = max(1_000, spikeTokenThreshold)
        criticalTokenThreshold = max(1_000, criticalTokenThreshold)
        criticalCostUsdThreshold = max(0.01, criticalCostUsdThreshold)
    }

    enum CodingKeys: String, CodingKey {
        case pollIntervalMinutes
        case showToday
        case minimalMode
        case recentQueryCount
        case spikeTokenThreshold
        case showSpikeWarning
        case showCriticalAlert
        case criticalTokenThreshold
        case criticalCostUsdThreshold
        case budgetDayBasis
        case showNotch
        case costProvider
        case dualView
        case pillLeftProvider
    }
}
