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
        showNotch: Bool = true
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
        clamp()
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
}
