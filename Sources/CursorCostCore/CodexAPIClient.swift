import Foundation

public actor CodexAPIClient {
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    public static let oauthClientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let timeout: TimeInterval = 25

    private let session: URLSession
    private let redirectBlocker: CodexRedirectBlocker

    public init(session: URLSession? = nil) {
        let blocker = CodexRedirectBlocker()
        self.redirectBlocker = blocker
        self.session = session ?? CodexAPIClient.makeSession(delegate: blocker)
    }

    public func loadUsage(auth: CodexAuthTokens, now: Date = Date()) async throws -> UsageReady {
        var tokens = auth
        var didRefresh = false
        if CursorSessionStore.needsRefresh(tokens.accessToken, now: now) {
            tokens = try await refreshTokens(tokens)
            didRefresh = true
        }
        do {
            return try await fetchUsageReady(tokens)
        } catch CursorCostError.sessionExpiredCodex {
            if didRefresh {
                throw CursorCostError.sessionExpiredCodex
            }
            tokens = try await refreshTokens(tokens)
            return try await fetchUsageReady(tokens)
        }
    }

    nonisolated public static func parseRefreshResponse(_ data: Data, current: CodexAuthTokens) throws -> CodexAuthTokens {
        let raw = try UsageMapper.parseJSON(data)
        guard let object = JSON.object(raw) else {
            throw CursorCostError.sessionExpiredCodex
        }
        guard let accessToken = JSON.string(object["access_token"]), !accessToken.isEmpty else {
            throw CursorCostError.sessionExpiredCodex
        }
        let idToken = JSON.string(object["id_token"]) ?? current.idToken
        return CodexAuthTokens(
            accessToken: accessToken,
            refreshToken: JSON.string(object["refresh_token"]) ?? current.refreshToken,
            idToken: idToken,
            accountId: current.accountId ?? CodexSessionStore.claimAccountId(accessToken) ?? CodexSessionStore.claimAccountId(idToken),
            email: CodexSessionStore.claimEmail(accessToken) ?? CodexSessionStore.claimEmail(idToken) ?? current.email
        )
    }

    public static func makeSession(delegate: URLSessionTaskDelegate? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

final class CodexRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension CodexAPIClient {
    func refreshTokens(_ auth: CodexAuthTokens) async throws -> CodexAuthTokens {
        guard let refreshToken = auth.refreshToken, !refreshToken.isEmpty else {
            throw CursorCostError.sessionExpiredCodex
        }
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.oauthClientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ])
        let data = try await send(request, expiredMeans: .sessionExpiredCodex)
        return try Self.parseRefreshResponse(data, current: auth)
    }

    func fetchUsageReady(_ auth: CodexAuthTokens) async throws -> UsageReady {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CostNotch", forHTTPHeaderField: "User-Agent")
        if let accountId = auth.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let data = try await send(request, expiredMeans: .sessionExpiredCodex)
        let raw = try UsageMapper.parseJSON(data)
        return UsageMapper.buildCodexUsageReady(usage: raw, email: auth.email)
    }

    func send(_ request: URLRequest, expiredMeans: CursorCostError) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorCostError.loadUsage
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw expiredMeans
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CursorCostError.httpStatus(http.statusCode)
        }
        return data
    }
}
