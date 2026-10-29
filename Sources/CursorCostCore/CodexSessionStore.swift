import Foundation

public enum CodexSessionStore {
    public static func defaultAuthPath(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty
        {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
        }
        return URL(fileURLWithPath: home).appendingPathComponent(".codex/auth.json")
    }

    public static func readAuth(
        authPath: URL? = nil,
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CodexAuthTokens {
        let path = authPath ?? defaultAuthPath(home: home, environment: environment)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw CursorCostError.signInCodex
        }
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw CursorCostError.sessionReadCodex
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data), let object = JSON.object(raw) else {
            throw CursorCostError.sessionReadCodex
        }
        let tokens = JSON.object(object["tokens"]) ?? [:]
        guard let accessToken = JSON.string(tokens["access_token"]) ?? JSON.string(tokens["accessToken"]) else {
            throw CursorCostError.signInCodex
        }
        let idToken = JSON.string(tokens["id_token"]) ?? JSON.string(tokens["idToken"])
        let accountId =
            JSON.string(tokens["account_id"])
            ?? JSON.string(tokens["accountId"])
            ?? claimAccountId(accessToken)
            ?? claimAccountId(idToken)
        let email = claimEmail(accessToken) ?? claimEmail(idToken)
        return CodexAuthTokens(
            accessToken: accessToken,
            refreshToken: JSON.string(tokens["refresh_token"]) ?? JSON.string(tokens["refreshToken"]),
            idToken: idToken,
            accountId: accountId,
            email: email
        )
    }

    static func claimEmail(_ token: String?) -> String? {
        guard let token, let profile = JSON.object(jwtPayload(token)?["https://api.openai.com/profile"]) else {
            return nil
        }
        return JSON.string(profile["email"])
    }

    static func claimAccountId(_ token: String?) -> String? {
        guard let token, let auth = JSON.object(jwtPayload(token)?["https://api.openai.com/auth"]) else {
            return nil
        }
        return JSON.string(auth["chatgpt_account_id"])
    }

    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let payload = String(parts[1])
        guard !payload.isEmpty, let data = Data(codexBase64URLEncoded: payload) else {
            return nil
        }
        return JSON.object(try? JSONSerialization.jsonObject(with: data))
    }
}

private extension Data {
    init?(codexBase64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = base64.count % 4
        if pad != 0 {
            base64 += String(repeating: "=", count: 4 - pad)
        }
        self.init(base64Encoded: base64)
    }
}
