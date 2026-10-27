import CommonCrypto
import Foundation
import LocalAuthentication
import Security

struct CursorTokenDecoder {
    private let readPassword: () throws -> Data
    private var password: Data?

    init(readPassword: @escaping () throws -> Data) {
        self.readPassword = readPassword
    }

    mutating func decode(_ stored: String) throws -> String {
        guard stored.hasPrefix("cursor-safe-storage:") else { return stored }
        let prefix = "cursor-safe-storage:v1:"
        guard stored.hasPrefix(prefix) else {
            throw CursorCostError.unsupportedSessionFormat
        }
        guard let encrypted = Data(base64Encoded: String(stored.dropFirst(prefix.count))) else {
            throw CursorCostError.sessionDecryption
        }
        guard encrypted.starts(with: Data("v10".utf8)) else {
            throw CursorCostError.unsupportedSessionFormat
        }
        let ciphertext = Data(encrypted.dropFirst(3))
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else {
            throw CursorCostError.sessionDecryption
        }
        if password == nil {
            password = try readPassword()
        }
        guard let password, !password.isEmpty else {
            throw CursorCostError.keychainUnavailable
        }
        var key = Data(count: kCCKeySizeAES128)
        defer { key.resetBytes(in: 0..<key.count) }
        let salt = Data("saltysalt".utf8)
        let keyLength = key.count
        let derived = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), keyLength
                    )
                }
            }
        }
        guard derived == kCCSuccess else { throw CursorCostError.sessionDecryption }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let capacity = plaintext.count
        var length = 0
        let status = plaintext.withUnsafeMutableBytes { output in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyLength, ivBytes.baseAddress,
                            input.baseAddress, ciphertext.count, output.baseAddress, capacity, &length
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess,
              let token = String(data: plaintext.prefix(length), encoding: .utf8), !token.isEmpty
        else {
            throw CursorCostError.sessionDecryption
        }
        return token
    }
}

enum CursorKeychain {
    private static let lock = NSLock()
    private static var cachedPassword: Data?

    static func clearCachedPassword() {
        lock.lock()
        defer { lock.unlock() }
        cachedPassword = nil
    }

    static func password(allowInteraction: Bool) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPassword { return cachedPassword }
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: "Cursor Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if let error = error(for: status) { throw error }
        guard let data = result as? Data, !data.isEmpty else {
            throw CursorCostError.keychainUnavailable
        }
        cachedPassword = data
        return data
    }

    static func error(for status: OSStatus) -> CursorCostError? {
        switch status {
        case errSecSuccess:
            return nil
        case errSecUserCanceled, errSecAuthFailed:
            return .keychainAccessDenied
        case errSecInteractionNotAllowed:
            return .keychainInteractionRequired
        case errSecItemNotFound:
            return .keychainItemMissing
        default:
            return .keychainUnavailable
        }
    }
}
