import Foundation

public enum UsageMapper {
    public static let personalMonthlyPoolMaxCents: Double = 1_000_000
    public static let defaultHistoryLimit = 100
    public static let spikeTokenThreshold: Double = 1_000_000
    public static let recentQueryCount = 3

    public static func centsToUsd(_ cents: Double) -> Double {
        cents.isFinite ? cents / 100 : 0
    }

    public static func parseJSON(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public static func mapEventsPayload(_ raw: Any, limit: Int = defaultHistoryLimit) -> [UsageQuery] {
        let list: [Any]
        if let array = JSON.array(raw) {
            list = array
        } else if let object = JSON.object(raw), let events = JSON.array(object["usageEventsDisplay"]) {
            list = events
        } else {
            list = []
        }

        var queries: [UsageQuery] = []
        queries.reserveCapacity(list.count)
        for item in list {
            if let query = mapEventToQuery(item) {
                queries.append(query)
            }
        }
        queries.sort { $0.timestamp > $1.timestamp }
        return Array(queries.prefix(max(0, limit)))
    }

    public static func mapEventToQuery(_ raw: Any) -> UsageQuery? {
        guard let object = JSON.object(raw) else { return nil }
        guard let timestamp = readTimestamp(object) else { return nil }
        let usage = JSON.object(object["tokenUsage"])
        let inputTokens = usage.map { tokenField($0, "inputTokens", "input_tokens") } ?? 0
        let outputTokens = usage.map { tokenField($0, "outputTokens", "output_tokens") } ?? 0
        let cacheRead = usage.map { tokenField($0, "cacheReadTokens", "cache_read_tokens") } ?? 0
        let cacheWrite = usage.map { tokenField($0, "cacheWriteTokens", "cache_write_tokens") } ?? 0
        return UsageQuery(
            timestamp: timestamp,
            model: JSON.string(object["model"]),
            kind: JSON.string(object["kind"]),
            costUsd: eventCostUsd(object, usage: usage),
            tokens: inputTokens + outputTokens + cacheRead + cacheWrite,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead
        )
    }

    public static func pickUsagePool(_ summary: Any) -> UsagePool? {
        guard let object = JSON.object(summary) else { return nil }
        let individual = JSON.object(object["individualUsage"])
        let team = JSON.object(object["teamUsage"])
        let plan = membershipPlan(summary)
        if isTeamSpendPlan(summary, plan: plan) {
            let teamCandidates: [(Any?, UsagePoolSource)] = [
                (individual?["overall"], .overall),
                (team?["pooled"], .teamOnDemand),
                (team?["onDemand"], .teamOnDemand),
                (object["overall"], .overall),
            ]
            for (raw, source) in teamCandidates {
                if let pool = readCappedMoneyPool(raw, source: source) {
                    return pool
                }
            }
            return nil
        }

        let personalCandidates: [(Any?, UsagePoolSource)] = [
            (individual?["onDemand"], .individualOnDemand),
            (individual?["overall"], .overall),
            (object["overall"], .overall),
            (individual?["plan"], .plan),
        ]
        for (raw, source) in personalCandidates {
            if source == .plan, isRequestCountPool(raw) {
                continue
            }
            guard isPersonalMonthlyPool(raw), let pool = readCappedMoneyPool(raw, source: source) else {
                continue
            }
            return pool
        }
        return nil
    }

    public static func buildUsageReady(
        summary: Any,
        queries: [UsageQuery]? = nil,
        events: Any? = nil,
        now: Date = Date(),
        email: String? = nil,
        eventsAvailable: Bool = true,
        budgetDayBasis: BudgetDayBasis = .workingDays
    ) -> UsageReady {
        let pool = pickUsagePool(summary)
        let unlimited = isUnlimited(pool, summary: summary)
        let usedUsd = pool.map { centsToUsd($0.usedCents) } ?? 0
        let limitUsd = pool.flatMap { pool in pool.limitCents.map(centsToUsd) }
        let remainingUsd: Double?
        if let remaining = pool?.remainingCents {
            remainingUsd = centsToUsd(remaining)
        } else if let limitUsd {
            remainingUsd = limitUsd - usedUsd
        } else {
            remainingUsd = nil
        }

        let recentQueries: [UsageQuery]
        if !eventsAvailable {
            recentQueries = []
        } else if let queries {
            recentQueries = queries
        } else if let events {
            recentQueries = mapEventsPayload(events)
        } else {
            recentQueries = []
        }

        let days = budgetDaysLeftInMonth(now, basis: budgetDayBasis)
        let plan = membershipPlan(summary)
        let spendDisplay = spendDisplayFor(summary, plan: plan)
        let includedQuotas = spendDisplay == .percent ? readIncludedQuotas(summary) : []
        let pools = readBillingPoolLines(summary, plan: plan)

        return UsageReady(
            email: email,
            plan: plan,
            spendDisplay: spendDisplay,
            includedQuotas: includedQuotas,
            usedUsd: usedUsd,
            limitUsd: limitUsd,
            remainingUsd: remainingUsd,
            todayUsedUsd: eventsAvailable ? sumTodayUsedUsd(recentQueries, now: now) : nil,
            dailyBudgetUsd: unlimited ? nil : dailyBudgetUsd(remainingUsd, days: days),
            workingDaysLeft: unlimited ? nil : days,
            billingCycleStart: isoField(summary, "billingCycleStart"),
            billingCycleEnd: isoField(summary, "billingCycleEnd"),
            isUnlimited: unlimited,
            includedLine: pools.included,
            onDemandLine: pools.onDemand,
            recentQueries: recentQueries
        )
    }

    public static func presentation(
        _ snapshot: UsageSnapshot,
        now: Date = Date(),
        refreshing: Bool = false,
        preferences: NotchPreferences = .standard
    ) -> UsagePresentation {
        switch snapshot {
        case .loading:
            return UsagePresentation(
                currentText: "…",
                currentCompact: "…",
                todayText: nil,
                currentTone: .default,
                todayTone: .default,
                recent: [],
                statusMessage: "Loading usage…",
                isLoading: true,
                plan: nil,
                email: nil
            )
        case .error(let message):
            return UsagePresentation(
                currentText: "N/A",
                currentCompact: "N/A",
                todayText: nil,
                currentTone: .default,
                todayTone: .default,
                recent: [],
                statusMessage: message,
                isLoading: refreshing,
                plan: nil,
                email: nil
            )
        case .ready(let data):
            let adjusted = applyBudgetDayBasis(data, basis: preferences.budgetDayBasis, now: now)
            let todayVisible =
                !preferences.minimalMode
                && preferences.showToday
                && !adjusted.isUnlimited
                && adjusted.todayUsedUsd != nil
            let recent = preferences.minimalMode
                ? []
                : recentViews(
                    adjusted.recentQueries,
                    count: preferences.recentQueryCount,
                    spikeThreshold: preferences.spikeTokenThreshold,
                    showSpikeWarning: preferences.showSpikeWarning
                )
            return UsagePresentation(
                currentText: currentText(adjusted),
                currentCompact: currentCompact(adjusted),
                todayText: todayVisible ? todayText(adjusted, now: now, basis: preferences.budgetDayBasis) : nil,
                currentTone: currentTone(adjusted),
                todayTone: todayTone(adjusted, now: now, basis: preferences.budgetDayBasis),
                recent: recent,
                statusMessage: statusMessage(adjusted),
                isLoading: refreshing,
                plan: adjusted.plan,
                email: adjusted.email,
                currentProgress: currentProgress(adjusted),
                todayProgress: todayVisible
                    ? todayProgress(adjusted, now: now, basis: preferences.budgetDayBasis)
                    : nil,
                todayCompact: todayVisible ? todayCompact(adjusted, now: now, basis: preferences.budgetDayBasis) : nil
            )
        }
    }

    public static func applyBudgetDayBasis(
        _ data: UsageReady,
        basis: BudgetDayBasis,
        now: Date = Date()
    ) -> UsageReady {
        var next = data
        if data.isUnlimited {
            next.dailyBudgetUsd = nil
            next.workingDaysLeft = nil
            return next
        }
        let days = budgetDaysLeftInMonth(now, basis: basis)
        next.workingDaysLeft = days
        next.dailyBudgetUsd = dailyBudgetUsd(data.remainingUsd, days: days)
        return next
    }

    public static func isCritical(_ query: UsageQuery, preferences: NotchPreferences) -> Bool {
        query.tokens >= preferences.criticalTokenThreshold
            || query.costUsd >= preferences.criticalCostUsdThreshold
    }

    public static func queryAlertKey(_ query: UsageQuery) -> String {
        "\(query.timestamp)-\(query.tokens)-\(query.costUsd)"
    }

    public static func workingDaysLeftInMonth(_ from: Date) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: from)
        let month = calendar.component(.month, from: from)
        let start = calendar.component(.day, from: from)
        let last = lastDateOfMonth(from, calendar: calendar)
        var count = 0
        for day in start...last {
            if isWeekend(year: year, month: month, day: day, calendar: calendar) {
                continue
            }
            count += 1
        }
        return max(1, count)
    }

    public static func calendarDaysLeftInMonth(_ from: Date) -> Int {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: from)
        return max(1, lastDateOfMonth(from, calendar: calendar) - day + 1)
    }

    public static func budgetDaysLeftInMonth(_ from: Date, basis: BudgetDayBasis) -> Int {
        basis == .calendarDays ? calendarDaysLeftInMonth(from) : workingDaysLeftInMonth(from)
    }

    public static func budgetDaysInMonth(_ from: Date, basis: BudgetDayBasis) -> Int {
        let calendar = Calendar.current
        let last = lastDateOfMonth(from, calendar: calendar)
        if basis == .calendarDays {
            return last
        }
        let year = calendar.component(.year, from: from)
        let month = calendar.component(.month, from: from)
        var count = 0
        for day in 1...last {
            if !isWeekend(year: year, month: month, day: day, calendar: calendar) {
                count += 1
            }
        }
        return count
    }

    public static func dailyBudgetUsd(_ remainingUsd: Double?, days: Int) -> Double? {
        guard let remainingUsd, remainingUsd.isFinite, days > 0 else { return nil }
        return remainingUsd / Double(days)
    }

    public static func sumTodayUsedUsd(_ events: [UsageQuery], now: Date) -> Double {
        let today = localDayKey(now)
        return events.reduce(0) { partial, event in
            localDayKey(Date(timeIntervalSince1970: event.timestamp / 1000)) == today
                ? partial + event.costUsd
                : partial
        }
    }

    public static func sumMonthUsedUsd(_ events: [UsageQuery], now: Date) -> Double {
        let month = localMonthKey(now)
        return events.reduce(0) { partial, event in
            localMonthKey(Date(timeIntervalSince1970: event.timestamp / 1000)) == month
                ? partial + event.costUsd
                : partial
        }
    }

    public static func todayAttributedPercent(todayUsd: Double, monthUsd: Double, cyclePercent: Double) -> Double {
        if !(todayUsd > 0) {
            return 0
        }
        if monthUsd > 0.000001 {
            return (todayUsd / monthUsd) * max(0, cyclePercent)
        }
        return max(0, cyclePercent)
    }

    public static func averageCyclePercent(_ quotas: [IncludedQuota]) -> Double? {
        average(quotas.map(\.percent))
    }

    public static func averageTodayPercent(_ quotas: [IncludedQuota], todayUsd: Double, monthUsd: Double) -> Double? {
        guard !quotas.isEmpty else { return nil }
        return average(quotas.map { todayAttributedPercent(todayUsd: todayUsd, monthUsd: monthUsd, cyclePercent: $0.percent) })
    }

    public static func dailyPacePercent(_ now: Date, basis: BudgetDayBasis) -> Double? {
        let days = budgetDaysInMonth(now, basis: basis)
        guard days > 0 else { return nil }
        return 100 / Double(days)
    }

    public static func proCurrentStatusText(_ quotas: [IncludedQuota]) -> String? {
        guard let avg = averageCyclePercent(quotas) else { return nil }
        return "\(Formatting.percentPoint(avg)) / 100%"
    }

    public static func proTodayStatusText(
        quotas: [IncludedQuota],
        todayUsd: Double,
        monthUsd: Double,
        dailyPct: Double?
    ) -> String? {
        guard let avg = averageTodayPercent(quotas, todayUsd: todayUsd, monthUsd: monthUsd) else {
            return nil
        }
        let sum = Formatting.dollars(todayUsd)
        guard let dailyPct else {
            return "\(Formatting.percentPoint(avg)) (\(sum))"
        }
        return "\(Formatting.percentPoint(avg)) / \(Formatting.percentPoint(dailyPct)) (\(sum))"
    }
}

private extension UsageMapper {
    static let teamPlanNames: Set<String> = ["business", "team", "enterprise", "company"]
    static let otherModelKeys = ["namedModels", "otherModels", "api", "other", "includedApi"]

    static func isPersonalMonthlyPool(_ raw: Any?) -> Bool {
        guard let object = JSON.object(raw), object["enabled"] as? Bool != false else {
            return false
        }
        let used = poolUsedCents(object)
        let limit = poolLimitCents(object)
        if used == nil && limit == nil {
            return false
        }
        guard let limit else { return true }
        return limit <= personalMonthlyPoolMaxCents
    }

    static func readMoneyPool(_ raw: Any?, source: UsagePoolSource) -> UsagePool? {
        guard let object = JSON.object(raw), object["enabled"] as? Bool != false else {
            return nil
        }
        let used = poolUsedCents(object)
        let limit = poolLimitCents(object)
        if used == nil && limit == nil {
            return nil
        }
        return UsagePool(
            usedCents: used ?? 0,
            limitCents: limit,
            remainingCents: JSON.number(object["remainingCents"]) ?? JSON.number(object["remaining"]),
            source: source
        )
    }

    static func poolUsedCents(_ raw: [String: Any]) -> Double? {
        JSON.number(raw["usedCents"]) ?? JSON.number(raw["used"])
    }

    static func poolLimitCents(_ raw: [String: Any]) -> Double? {
        JSON.number(raw["limitCents"]) ?? JSON.number(raw["limit"])
    }

    static func isTeamSpendPlan(_ summary: Any, plan: String?) -> Bool {
        if let object = JSON.object(summary), let limitType = JSON.string(object["limitType"])?.lowercased() {
            if limitType == "team" || limitType == "organization" || limitType == "org" {
                return true
            }
        }
        guard let plan else { return false }
        return teamPlanNames.contains(plan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func roundPercent(_ value: Double) -> Double {
        value.isFinite ? max(0, value.rounded()) : 0
    }

    static func quotaFromPercent(name: String, percent: Double?) -> IncludedQuota? {
        guard let percent else { return nil }
        return IncludedQuota(name: name, used: percent, limit: 100, percent: roundPercent(percent))
    }

    static func parsePercentFromMessage(_ value: Any?) -> Double? {
        guard let string = JSON.string(value) else { return nil }
        guard let match = string.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) else {
            return nil
        }
        let body = String(string[match]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return JSON.number(body)
    }

    static func readIncludedQuota(_ raw: Any?, name: String) -> IncludedQuota? {
        guard let object = JSON.object(raw), object["enabled"] as? Bool != false else {
            return nil
        }
        let used = JSON.number(object["used"]) ?? JSON.number(object["usedCents"])
        let limit = JSON.number(object["limit"]) ?? JSON.number(object["limitCents"])
        let explicitPercent =
            JSON.number(object["percentUsed"])
            ?? JSON.number(object["usedPercent"])
            ?? JSON.number(object["percentage"])
            ?? JSON.number(object["percent"])

        if let explicitPercent, used == nil || limit == nil || !((limit ?? 0) > 0) {
            return IncludedQuota(name: name, used: used ?? 0, limit: limit ?? 100, percent: roundPercent(explicitPercent))
        }
        guard let used, let limit, limit > 0 else { return nil }
        let percent = explicitPercent.map(roundPercent) ?? roundPercent((used / limit) * 100)
        return IncludedQuota(name: name, used: used, limit: limit, percent: percent)
    }

    static func readIncludedQuotas(_ summary: Any) -> [IncludedQuota] {
        guard let object = JSON.object(summary) else { return [] }
        let individual = JSON.object(object["individualUsage"])
        let plan = JSON.object(individual?["plan"])
        let autoPercent = JSON.number(plan?["autoPercentUsed"]) ?? parsePercentFromMessage(object["autoModelSelectedDisplayMessage"])
        let apiPercent = JSON.number(plan?["apiPercentUsed"]) ?? parsePercentFromMessage(object["namedModelSelectedDisplayMessage"])
        if autoPercent != nil || apiPercent != nil {
            return [
                quotaFromPercent(name: "Cursor Models", percent: autoPercent),
                quotaFromPercent(name: "Other Models", percent: apiPercent),
            ].compactMap { $0 }
        }

        var quotas: [IncludedQuota] = []
        if let planQuota = readIncludedQuota(plan ?? object["planUsage"], name: "Cursor Models") {
            quotas.append(planQuota)
        }
        if let individual {
            for key in otherModelKeys {
                if let quota = readIncludedQuota(individual[key], name: "Other Models") {
                    quotas.append(quota)
                    break
                }
            }
        }
        if quotas.allSatisfy({ $0.name != "Other Models" }) {
            if let other = readIncludedQuota(object["namedModelUsage"], name: "Other Models")
                ?? readIncludedQuota(object["otherModels"], name: "Other Models")
            {
                quotas.append(other)
            }
        }
        return quotas
    }

    static func spendDisplayFor(_ summary: Any, plan: String?) -> SpendDisplay {
        if isTeamSpendPlan(summary, plan: plan) {
            return .usd
        }
        if !readIncludedQuotas(summary).isEmpty {
            return .percent
        }
        return .usd
    }

    static func isUnlimited(_ pool: UsagePool?, summary: Any) -> Bool {
        if let object = JSON.object(summary), let flag = object["isUnlimited"] as? Bool {
            return flag
        }
        guard let pool else { return false }
        return pool.limitCents == nil
    }

    static func readCappedMoneyPool(_ raw: Any?, source: UsagePoolSource) -> UsagePool? {
        guard let pool = readMoneyPool(raw, source: source), let limit = pool.limitCents, limit > 0 else {
            return nil
        }
        return pool
    }

    static func isRequestCountPool(_ raw: Any?) -> Bool {
        guard let object = JSON.object(raw) else { return true }
        return object["usedCents"] == nil && object["limitCents"] == nil
    }

    static func membershipPlan(_ summary: Any) -> String? {
        guard let object = JSON.object(summary) else { return nil }
        return JSON.string(object["membershipType"]) ?? JSON.string(object["plan"])
    }

    static func isoField(_ summary: Any, _ key: String) -> String? {
        JSON.string(JSON.object(summary)?[key])
    }

    static func tokenField(_ usage: [String: Any], _ keys: String...) -> Double {
        for key in keys {
            if let value = JSON.number(usage[key]) {
                return value
            }
        }
        return 0
    }

    static func readTimestamp(_ raw: [String: Any]) -> Double? {
        let value = raw["timestamp"] ?? raw["time"] ?? raw["createdAt"]
        if let numeric = JSON.number(value) {
            return numeric
        }
        if let string = JSON.string(value), let parsed = Date.parseMillis(string) {
            return parsed
        }
        return nil
    }

    static func eventCostUsd(_ raw: [String: Any], usage: [String: Any]?) -> Double {
        if let charged = JSON.number(raw["chargedCents"]) {
            return centsToUsd(charged)
        }
        if let totalCents = usage.flatMap({ JSON.number($0["totalCents"]) }) {
            return centsToUsd(totalCents)
        }
        if let fromString = parseDollarString(raw["usageBasedCosts"]) {
            return fromString
        }
        return 0
    }

    static func parseDollarString(_ value: Any?) -> Double? {
        guard var string = JSON.string(value) else { return nil }
        string = string.replacingOccurrences(of: "[^0-9.+-]", with: "", options: .regularExpression)
        guard let numeric = Double(string), numeric.isFinite else { return nil }
        return numeric
    }

    static func readBillingPoolLines(_ summary: Any, plan: String?) -> (included: String?, onDemand: String?) {
        guard JSON.object(summary) != nil else {
            return (nil, nil)
        }
        let quotas = readIncludedQuotas(summary)
        if spendDisplayFor(summary, plan: plan) == .percent, !quotas.isEmpty {
            return (includedLineFromQuotas(quotas), readOnDemandLine(summary))
        }
        let individual = JSON.object(JSON.object(summary)?["individualUsage"])
        var includedLine: String?
        if let planPool = JSON.object(individual?["plan"]), planPool["enabled"] as? Bool != false {
            let used = JSON.number(planPool["used"]) ?? JSON.number(planPool["usedCents"])
            let limit = JSON.number(planPool["limit"]) ?? JSON.number(planPool["limitCents"])
            if let used, JSON.number(planPool["usedCents"]) == nil {
                includedLine = formatRequestPool(used: used, limit: limit)
            }
        }
        return (includedLine, readOnDemandLine(summary))
    }

    static func readOnDemandLine(_ summary: Any) -> String? {
        guard let pool = pickUsagePool(summary) else { return nil }
        let used = Formatting.dollars(centsToUsd(pool.usedCents))
        guard let limitCents = pool.limitCents else { return used }
        return "\(used) / \(Formatting.dollars(centsToUsd(limitCents)))"
    }

    static func includedLineFromQuotas(_ quotas: [IncludedQuota]) -> String? {
        guard !quotas.isEmpty else { return nil }
        return quotas.map { "\($0.name) \(Formatting.percentUsed($0.percent))" }.joined(separator: " · ")
    }

    static func formatRequestPool(used: Double, limit: Double?) -> String {
        let usedText = String(Int(used.rounded()))
        guard let limit else { return usedText }
        return "\(usedText) / \(Int(limit.rounded()))"
    }

    static func lastDateOfMonth(_ from: Date, calendar: Calendar) -> Int {
        let range = calendar.range(of: .day, in: .month, for: from)
        return range?.count ?? 30
    }

    static func isWeekend(year: Int, month: Int, day: Int, calendar: Calendar) -> Bool {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    static func localDayKey(_ date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))"
    }

    static func localMonthKey(_ date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func spendTone(used: Double, cap: Double?) -> SpendTone {
        guard used.isFinite else { return .default }
        guard let cap else { return .green }
        if !(cap > 0) {
            return used > 0 ? .red : .green
        }
        return used >= cap ? .red : .green
    }

    static func currentProgress(_ data: UsageReady) -> Double? {
        if data.isUnlimited {
            return nil
        }
        if data.spendDisplay == .percent, let avg = averageCyclePercent(data.includedQuotas) {
            return max(0, avg / 100)
        }
        return ratio(used: data.usedUsd, cap: data.limitUsd)
    }

    static func todayProgress(_ data: UsageReady, now: Date, basis: BudgetDayBasis) -> Double? {
        if data.spendDisplay == .percent, !data.includedQuotas.isEmpty {
            let todayUsd = data.todayUsedUsd ?? 0
            let monthUsd = max(sumMonthUsedUsd(data.recentQueries, now: now), todayUsd)
            let avg = averageTodayPercent(data.includedQuotas, todayUsd: todayUsd, monthUsd: monthUsd)
            let pace = dailyPacePercent(now, basis: basis)
            guard let avg, let pace, pace > 0 else { return nil }
            return max(0, avg / pace)
        }
        return ratio(used: data.todayUsedUsd ?? 0, cap: data.dailyBudgetUsd)
    }

    static func ratio(used: Double, cap: Double?) -> Double? {
        guard used.isFinite, let cap, cap > 0 else { return nil }
        return max(0, used / cap)
    }

    static func currentText(_ data: UsageReady) -> String {
        if data.isUnlimited {
            return "Unlimited"
        }
        if data.spendDisplay == .percent, !data.includedQuotas.isEmpty, let text = proCurrentStatusText(data.includedQuotas) {
            return text
        }
        let used = Formatting.dollars(data.usedUsd)
        guard let limit = data.limitUsd else {
            return "\(used) / —"
        }
        return "\(used) / \(Formatting.dollars(limit))"
    }

    static func currentCompact(_ data: UsageReady) -> String {
        if data.isUnlimited {
            return "∞"
        }
        if data.spendDisplay == .percent, let avg = averageCyclePercent(data.includedQuotas) {
            return Formatting.percentPoint(avg)
        }
        return Formatting.dollarSign(data.usedUsd)
    }

    static func todayCompact(_ data: UsageReady, now: Date, basis: BudgetDayBasis) -> String? {
        if data.spendDisplay == .percent, !data.includedQuotas.isEmpty {
            let todayUsd = data.todayUsedUsd ?? 0
            let monthUsd = max(sumMonthUsedUsd(data.recentQueries, now: now), todayUsd)
            if let avg = averageTodayPercent(data.includedQuotas, todayUsd: todayUsd, monthUsd: monthUsd) {
                return Formatting.percentPoint(avg)
            }
        }
        guard let today = data.todayUsedUsd else { return nil }
        return Formatting.dollarSign(today)
    }

    static func todayText(_ data: UsageReady, now: Date, basis: BudgetDayBasis) -> String {
        if data.spendDisplay == .percent, !data.includedQuotas.isEmpty {
            let todayUsd = data.todayUsedUsd ?? 0
            let monthUsd = max(sumMonthUsedUsd(data.recentQueries, now: now), todayUsd)
            if let text = proTodayStatusText(
                quotas: data.includedQuotas,
                todayUsd: todayUsd,
                monthUsd: monthUsd,
                dailyPct: dailyPacePercent(now, basis: basis)
            ) {
                return text
            }
        }
        let used = Formatting.dollars(data.todayUsedUsd ?? 0)
        guard let budget = data.dailyBudgetUsd, budget > 0 else {
            return "\(used) / —"
        }
        return "\(used) / \(Formatting.dollars(budget))"
    }

    static func currentTone(_ data: UsageReady) -> SpendTone {
        if data.isUnlimited {
            return .green
        }
        if data.spendDisplay == .percent {
            guard let avg = averageCyclePercent(data.includedQuotas) else {
                return .green
            }
            return spendTone(used: avg, cap: 100)
        }
        return spendTone(used: data.usedUsd, cap: data.limitUsd)
    }

    static func todayTone(_ data: UsageReady, now: Date, basis: BudgetDayBasis) -> SpendTone {
        if data.spendDisplay == .percent, !data.includedQuotas.isEmpty {
            let todayUsd = data.todayUsedUsd ?? 0
            let monthUsd = max(sumMonthUsedUsd(data.recentQueries, now: now), todayUsd)
            let avg = averageTodayPercent(data.includedQuotas, todayUsd: todayUsd, monthUsd: monthUsd)
            let pace = dailyPacePercent(now, basis: basis)
            guard let avg, let pace else { return .green }
            return spendTone(used: avg, cap: pace)
        }
        if data.spendDisplay == .percent {
            return .green
        }
        guard let budget = data.dailyBudgetUsd, budget > 0 else { return .green }
        return spendTone(used: data.todayUsedUsd ?? 0, cap: budget)
    }

    static func recentViews(
        _ queries: [UsageQuery],
        count: Int,
        spikeThreshold: Double,
        showSpikeWarning: Bool
    ) -> [RecentQueryView] {
        let newest = queries.sorted { $0.timestamp > $1.timestamp }.prefix(max(0, count))
        return newest.enumerated().map { index, query in
            let spike = showSpikeWarning && query.tokens >= spikeThreshold
            let model = Formatting.stripModelPrefix(query.model)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (model?.isEmpty == false ? model! : "query")
            let body = "\(Formatting.dollars(query.costUsd)) - \(Formatting.compactTokens(query.tokens))"
            return RecentQueryView(
                id: "\(index)-\(query.timestamp)",
                text: spike ? "! \(body)" : body,
                model: label,
                detail: [
                    Formatting.dateTime(query.timestamp),
                    "\(Formatting.tokens(query.tokens)) tokens",
                    Formatting.kind(query.kind),
                ].joined(separator: " · "),
                tone: showSpikeWarning ? (spike ? .red : .green) : .default
            )
        }
    }

    static func statusMessage(_ data: UsageReady) -> String {
        var parts: [String] = []
        if let email = data.email, !email.isEmpty { parts.append(email) }
        if let plan = data.plan, !plan.isEmpty { parts.append(plan) }
        if let included = data.includedLine { parts.append(included) }
        if let onDemand = data.onDemandLine { parts.append(onDemand) }
        return parts.isEmpty ? "Cursor spend" : parts.joined(separator: " · ")
    }
}

private extension Date {
    static func parseMillis(_ value: String) -> Double? {
        if let numeric = Double(value), numeric.isFinite {
            return numeric
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date.timeIntervalSince1970 * 1000
        }
        return nil
    }
}
