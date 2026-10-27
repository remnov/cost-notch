@testable import CursorCostCore
import Foundation
import Security
import SQLite3
import Testing

struct EncryptedSessionTests {
    private static let password = Data("synthetic-cursor-safe-storage-password".utf8)
    private static let access = "aaa.eyJzdWIiOiJ1c2VyX3Rlc3QiLCJleHAiOjQxMDI0NDQ4MDB9.sig"
    private static let encryptedAccess = "cursor-safe-storage:v1:djEwStVDCjLq3FZ5n8MaQecVrlT6O8RUcJdH5WeFS9cMmnQbA2U8ZTZeaddcwC1oU5pqh4H0LV9sWo9VvpAneSE2bw=="
    private static let encryptedRefresh = "cursor-safe-storage:v1:djEwDY8BNpk7bzkKsurOjKN884AXL5C6+NoZpccpK6WR8Z8="

    @Test
    func readAuth_givenEncryptedTokens_thenDecryptsBothWithOneKeychainRead() throws {
        try withDatabase(access: Self.encryptedAccess, refresh: Self.encryptedRefresh) { given in
            var reads = 0

            let then = try CursorSessionStore.readAuth(databasePath: given) {
                reads += 1
                return Self.password
            }

            #expect(then.accessToken == Self.access)
            #expect(then.refreshToken == "synthetic-refresh-token")
            #expect(reads == 1)
            #expect(try CursorSessionStore.session(accessToken: then.accessToken, email: nil).cookie
                == "WorkosCursorSessionToken=user_test::\(Self.access)")
            #expect(try storedValue(at: given, key: CursorSessionStore.accessTokenKey) == Self.encryptedAccess)
            #expect(try storedValue(at: given, key: CursorSessionStore.refreshTokenKey) == Self.encryptedRefresh)
        }
    }

    @Test
    func readAuth_givenLegacyPlainTokens_thenDoesNotReadKeychain() throws {
        try withDatabase(access: "user_test::\(Self.access)", refresh: "plain-refresh") { given in
            let then = try CursorSessionStore.readAuth(databasePath: given) {
                Issue.record("Plain tokens must not access Keychain")
                throw CursorCostError.keychainAccessDenied
            }

            #expect(then.accessToken == Self.access)
            #expect(then.refreshToken == "plain-refresh")
        }
    }

    @Test
    func readAuth_givenUpdatedDatabaseTokens_thenReadsFreshValues() throws {
        try withDatabase(access: Self.encryptedAccess, refresh: Self.encryptedRefresh) { given in
            _ = try CursorSessionStore.readAuth(databasePath: given, readPassword: { Self.password })
            try writeValues(at: given, access: Self.access, refresh: "rotated-refresh")

            let then = try CursorSessionStore.readAuth(databasePath: given) {
                Issue.record("Updated plain tokens must not access Keychain")
                throw CursorCostError.keychainAccessDenied
            }

            #expect(then.refreshToken == "rotated-refresh")
        }
    }

    @Test
    func readAuth_givenKeychainDenied_thenPreservesPermissionError() throws {
        try withDatabase(access: Self.encryptedAccess, refresh: nil) { given in
            #expect(throws: CursorCostError.keychainAccessDenied) {
                try CursorSessionStore.readAuth(databasePath: given) {
                    throw CursorCostError.keychainAccessDenied
                }
            }
        }
    }

    @Test(arguments: ["cursor-safe-storage:v2:opaque", "cursor-safe-storage:v1:djExb3BhcXVl"])
    func decode_givenUnknownEncryptionVersion_thenRejectsBeforeKeychain(_ given: String) {
        var decoder = CursorTokenDecoder {
            Issue.record("Unknown formats must not access Keychain")
            return Self.password
        }

        #expect(throws: CursorCostError.unsupportedSessionFormat) {
            try decoder.decode(given)
        }
    }

    @Test(arguments: ["cursor-safe-storage:v1:!invalid!", "cursor-safe-storage:v1:djEw", "cursor-safe-storage:v1:djEwYQ=="])
    func decode_givenMalformedCiphertext_thenRejectsBeforeKeychain(_ given: String) {
        var decoder = CursorTokenDecoder {
            Issue.record("Malformed ciphertext must not access Keychain")
            return Self.password
        }

        #expect(throws: CursorCostError.sessionDecryption) {
            try decoder.decode(given)
        }
    }

    @Test
    func decode_givenWrongKey_thenReportsDecryptionFailure() {
        var decoder = CursorTokenDecoder { Data("wrong-password".utf8) }

        #expect(throws: CursorCostError.sessionDecryption) {
            try decoder.decode(Self.encryptedAccess)
        }
    }

    @Test
    func readAuth_givenUnreadableSchema_thenReportsDatabaseFailure() throws {
        try withDatabase(access: Self.access, refresh: nil) { given in
            try withConnection(at: given) { db in
                #expect(sqlite3_exec(db, "DROP TABLE ItemTable", nil, nil, nil) == SQLITE_OK)
            }

            #expect(throws: CursorCostError.sessionRead) {
                try CursorSessionStore.readAuth(databasePath: given, readPassword: { Self.password })
            }
        }
    }

    @Test
    func keychainError_givenDistinctStatuses_thenPreservesRecoveryActions() {
        #expect(CursorKeychain.error(for: errSecSuccess) == nil)
        #expect(CursorKeychain.error(for: errSecUserCanceled) == .keychainAccessDenied)
        #expect(CursorKeychain.error(for: errSecAuthFailed) == .keychainAccessDenied)
        #expect(CursorKeychain.error(for: errSecInteractionNotAllowed) == .keychainInteractionRequired)
        #expect(CursorKeychain.error(for: errSecItemNotFound) == .keychainItemMissing)
        #expect(CursorKeychain.error(for: errSecNotAvailable) == .keychainUnavailable)
    }
}

private func withDatabase(access: String, refresh: String?, body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cursor session # \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("state.vscdb")
    try withConnection(at: path) { db in
        #expect(sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)", nil, nil, nil) == SQLITE_OK)
    }
    try writeValues(at: path, access: access, refresh: refresh)
    try body(path)
}

private func writeValues(at path: URL, access: String, refresh: String?) throws {
    try withConnection(at: path) { db in
        for (key, value) in [(CursorSessionStore.accessTokenKey, access), (CursorSessionStore.refreshTokenKey, refresh)] {
            guard let value else { continue }
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO ItemTable VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
            let data = Data(value.utf8)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), transient) }
            #expect(sqlite3_step(statement) == SQLITE_DONE)
        }
    }
}

private func storedValue(at path: URL, key: String) throws -> String? {
    try withConnection(at: path) { db in
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        _ = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return String(data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))), encoding: .utf8)
    }
}

private func withConnection<T>(at path: URL, body: (OpaquePointer) throws -> T) throws -> T {
    var connection: OpaquePointer?
    let status = sqlite3_open(path.path, &connection)
    defer { sqlite3_close(connection) }
    guard status == SQLITE_OK, let connection else { throw CursorCostError.sessionRead }
    return try body(connection)
}
