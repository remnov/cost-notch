import Foundation

public actor CursorAPIClient {
    public static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    public static let eventsURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!
    public static let tokenURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    public static let oauthClientId = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    public static let timeout: TimeInterval = 15
    public static let pageSize = 100
    public static let maxTodayPages = 10

    private let session: URLSession

    public init(session: URLSession = CursorAPIClient.makeSession()) {
        self.session = session
    }

    public func session(from auth: CursorAuthTokens, now: Date = Date()) async throws -> CursorSession {
        var jwt = CursorSessionStore.jwtFromStoredValue(auth.accessToken) ?? auth.accessToken
        if CursorSessionStore.needsRefresh(jwt, now: now) {
            guard let refreshToken = auth.refreshToken, !refreshToken.isEmpty else {
                throw CursorCostError.sessionExpired
            }
            jwt = try await refreshAccessToken(refreshToken)
            guard !CursorSessionStore.needsRefresh(jwt, now: now, leeway: 0) else {
                throw CursorCostError.sessionExpired
            }
        }
        return try CursorSessionStore.session(accessToken: jwt, email: auth.email)
    }

    nonisolated public static func parseRefreshResponse(_ data: Data) throws -> String {
        let raw = try UsageMapper.parseJSON(data)
        guard let object = JSON.object(raw) else {
            throw CursorCostError.signIn
        }
        if object["shouldLogout"] as? Bool == true {
            throw CursorCostError.sessionExpired
        }
        guard let token = JSON.string(object["access_token"]), !token.isEmpty else {
            throw CursorCostError.signIn
        }
        return token
    }

    public func loadUsage(
        cookie: String,
        email: String?,
        now: Date = Date(),
        budgetDayBasis: BudgetDayBasis = .workingDays
    ) async throws -> UsageReady {
        async let summaryData = fetchSummary(cookie: cookie)
        async let eventQueries = fetchTodayEvents(cookie: cookie, now: now)
        let summary = try UsageMapper.parseJSON(await summaryData)
        let queries = try await eventQueries
        return UsageMapper.buildUsageReady(
            summary: summary,
            queries: queries,
            now: now,
            email: email,
            eventsAvailable: true,
            budgetDayBasis: budgetDayBasis
        )
    }

    public func fetchSummary(cookie: String) async throws -> Data {
        var request = URLRequest(url: Self.summaryURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout
        applyHeaders(&request, cookie: cookie, jsonBody: false)
        return try await send(request)
    }

    public func fetchTodayEvents(cookie: String, now: Date) async throws -> [UsageQuery] {
        let bounds = Self.localDayBounds(now)
        var collected: [UsageQuery] = []
        for page in 1...Self.maxTodayPages {
            let queries = try await postEventsPage(
                cookie: cookie,
                page: page,
                startDate: bounds.start,
                endDate: bounds.end
            )
            if queries.isEmpty {
                break
            }
            collected.append(contentsOf: queries)
            if queries.count < Self.pageSize {
                break
            }
        }
        if !collected.isEmpty {
            collected.sort { $0.timestamp > $1.timestamp }
            return collected
        }
        let fallback = try await postEventsPage(cookie: cookie, page: 1, startDate: nil, endDate: nil)
        return fallback.filter { Self.isSameLocalDay($0.timestamp, now: now) }
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }

    public static func localDayBounds(_ now: Date) -> (start: String, end: String) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = start.addingTimeInterval(24 * 60 * 60 - 0.001)
        return (
            String(Int((start.timeIntervalSince1970 * 1000).rounded())),
            String(Int((end.timeIntervalSince1970 * 1000).rounded()))
        )
    }

    public static func isSameLocalDay(_ timestamp: Double, now: Date) -> Bool {
        let calendar = Calendar.current
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        return calendar.isDate(date, inSameDayAs: now)
    }
}

private extension CursorAPIClient {
    func refreshAccessToken(_ refreshToken: String) async throws -> String {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.oauthClientId,
            "refresh_token": refreshToken,
        ])
        let data = try await send(request)
        return try Self.parseRefreshResponse(data)
    }

    func postEventsPage(
        cookie: String,
        page: Int,
        startDate: String?,
        endDate: String?
    ) async throws -> [UsageQuery] {
        var body: [String: Any] = [
            "page": page,
            "pageSize": Self.pageSize,
        ]
        if let startDate { body["startDate"] = startDate }
        if let endDate { body["endDate"] = endDate }
        var request = URLRequest(url: Self.eventsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyHeaders(&request, cookie: cookie, jsonBody: true)
        let data = try await send(request)
        let raw = try UsageMapper.parseJSON(data)
        return UsageMapper.mapEventsPayload(raw, limit: .max)
    }

    func applyHeaders(_ request: inout URLRequest, cookie: String, jsonBody: Bool) {
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        }
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorCostError.loadUsage
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CursorCostError.httpStatus(http.statusCode)
        }
        return data
    }
}
