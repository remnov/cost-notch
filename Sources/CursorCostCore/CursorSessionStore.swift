import Foundation
import SQLite3

public enum CursorSessionStore {
    public static let accessTokenKey = "cursorAuth/accessToken"
    public static let refreshTokenKey = "cursorAuth/refreshToken"
    public static let emailKeys = ["cursorAuth/cachedEmail", "cursorAuth/email"]
    public static let refreshLeeway: TimeInterval = 60

    public static func defaultDatabasePath(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    public static func read(databasePath: URL? = nil) throws -> CursorSession {
        let auth = try readAuth(databasePath: databasePath)
        return try session(accessToken: auth.accessToken, email: auth.email)
    }

    public static func readAuth(databasePath: URL? = nil) throws -> CursorAuthTokens {
        let path = databasePath ?? defaultDatabasePath()
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw CursorCostError.signIn
        }

        let values = try readItemValues(path: path.path)
        guard let stored = values.stored, let jwt = jwtFromStoredValue(stored) else {
            throw CursorCostError.signIn
        }
        return CursorAuthTokens(
            accessToken: jwt,
            refreshToken: values.refreshToken,
            email: values.email
        )
    }

    public static func session(accessToken: String, email: String?) throws -> CursorSession {
        guard let jwt = jwtFromStoredValue(accessToken), let sub = decodeJwtSub(jwt) else {
            throw CursorCostError.signIn
        }
        return CursorSession(cookie: buildWorkosCookie(sub: sub, accessToken: jwt), email: email)
    }

    public static func jwtFromStoredValue(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return nil
        }
        value = value.removingPercentEncoding ?? value
        if let range = value.range(of: "::", options: .backwards) {
            value = String(value[range.upperBound...])
        }
        return value.isEmpty ? nil : value
    }

    public static func decodeJwtSub(_ token: String) -> String? {
        guard let sub = JSON.string(jwtPayload(token)?["sub"]) else {
            return nil
        }
        return sub
    }

    public static func jwtExpiration(_ token: String) -> Date? {
        guard let exp = JSON.number(jwtPayload(token)?["exp"]) else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    public static func needsRefresh(
        _ token: String,
        now: Date = Date(),
        leeway: TimeInterval = refreshLeeway
    ) -> Bool {
        guard let expiration = jwtExpiration(token) else {
            return false
        }
        return expiration.timeIntervalSince(now) <= leeway
    }

    public static func buildWorkosCookie(sub: String, accessToken: String) -> String {
        "WorkosCursorSessionToken=\(sub)::\(accessToken)"
    }
}

private extension CursorSessionStore {
    struct ItemValues {
        var stored: String?
        var refreshToken: String?
        var email: String?
    }

    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let payload = String(parts[1])
        guard !payload.isEmpty, let data = Data(base64URLEncoded: payload) else {
            return nil
        }
        return JSON.object(try? JSONSerialization.jsonObject(with: data))
    }

    static func readItemValues(path: String) throws -> ItemValues {
        let db = try openDatabase(path: path)
        defer { sqlite3_close(db) }

        var email: String?
        for key in emailKeys {
            email = readValue(db: db, key: key)
            if email != nil {
                break
            }
        }
        return ItemValues(
            stored: readValue(db: db, key: accessTokenKey),
            refreshToken: readValue(db: db, key: refreshTokenKey),
            email: email
        )
    }

    static func openDatabase(path: String) throws -> OpaquePointer {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
        for immutable in [false, true] {
            var db: OpaquePointer?
            let uri = sqliteURI(path: path, immutable: immutable)
            if sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db {
                sqlite3_busy_timeout(db, 5000)
                return db
            }
            sqlite3_close(db)
        }
        throw CursorCostError.sessionRead
    }

    static func sqliteURI(path: String, immutable: Bool) -> String {
        let encoded = path.replacingOccurrences(of: " ", with: "%20")
        var uri = "file:\(encoded)?mode=ro"
        if immutable {
            uri += "&immutable=1"
        }
        return uri
    }

    static func readValue(db: OpaquePointer, key: String) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        _ = key.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return columnString(statement, index: 0)
    }

    static func columnString(_ statement: OpaquePointer, index: Int32) -> String? {
        let type = sqlite3_column_type(statement, index)
        if type == SQLITE_NULL {
            return nil
        }
        if type == SQLITE_BLOB {
            guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
            let length = Int(sqlite3_column_bytes(statement, index))
            let data = Data(bytes: bytes, count: length)
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        let text = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = base64.count % 4
        if pad != 0 {
            base64 += String(repeating: "=", count: 4 - pad)
        }
        self.init(base64Encoded: base64)
    }
}
