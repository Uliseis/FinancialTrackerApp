import Foundation
import Security

public enum EBKeyError: Error, Equatable {
    case badPEM
    case keyCreationFailed(String)
    case notFound
    case keychain(OSStatus)
}

// Parses the Enable Banking RSA private key (PEM or bare base64; PKCS#1 or PKCS#8) into
// a SecKey usable by EBJWTSigner. SecKeyCreateWithData wants PKCS#1 for RSA, so a PKCS#8
// ("BEGIN PRIVATE KEY") body is unwrapped to its inner PKCS#1 first.
public enum EBRSAKey {
    public static func from(pem: String) throws -> SecKey {
        let der = try derBytes(fromPEM: pem)
        if let key = makeKey(der) { return key }
        if let inner = strippedPKCS8(der), let key = makeKey(inner) { return key }
        throw EBKeyError.keyCreationFailed("could not import RSA private key")
    }

    static func derBytes(fromPEM pem: String) throws -> Data {
        let body: String
        if pem.contains("-----BEGIN") {
            body = pem
                .split(separator: "\n")
                .filter { !$0.hasPrefix("-----") }
                .joined()
        } else {
            body = pem
        }
        let cleaned = body.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: cleaned) else { throw EBKeyError.badPEM }
        return data
    }

    private static func makeKey(_ der: Data) -> SecKey? {
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil)
    }

    // Standard 26-byte PKCS#8 RSA wrapper prefix → inner PKCS#1 OCTET STRING contents.
    private static func strippedPKCS8(_ der: Data) -> Data? {
        let prefix: [UInt8] = [0x30, 0x82]
        guard der.count > 26, Array(der.prefix(2)) == prefix else { return nil }
        // Skip the SEQUENCE + version + AlgorithmIdentifier + OCTET STRING header (26 bytes).
        return der.subdata(in: 26..<der.count)
    }
}

// iCloud-synced (choice C): kSecAttrSynchronizable so the key follows the user's Apple
// account across devices. A per-item biometric SecAccessControl is incompatible with
// synchronizable items, so biometric protection is provided by the app's Face ID gate
// at launch; the item itself is gated by device unlock (kSecAttrAccessibleWhenUnlocked).
public struct EBKeychain: Sendable {
    public let service: String
    public init(service: String = "com.uliseis.financialtracker.enablebanking") {
        self.service = service
    }

    private static let pemAccount = "rsa-private-key-pem"
    private static let appIdAccount = "application-id"

    public func storeKeyPEM(_ pem: String) throws { try store(Self.pemAccount, pem) }
    public func storeApplicationId(_ id: String) throws { try store(Self.appIdAccount, id) }
    public func loadKeyPEM() throws -> String { try load(Self.pemAccount) }
    public func loadApplicationId() throws -> String { try load(Self.appIdAccount) }

    public func loadSigner(ttl: TimeInterval = 3600) throws -> EBJWTSigner {
        let key = try EBRSAKey.from(pem: try loadKeyPEM())
        return EBJWTSigner(applicationId: try loadApplicationId(), privateKey: key, ttl: ttl)
    }

    public var isConfigured: Bool {
        (try? loadKeyPEM()) != nil && (try? loadApplicationId()) != nil
    }

    public func removeAll() {
        for account in [Self.pemAccount, Self.appIdAccount] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecAttrSynchronizable: kSecAttrSynchronizableAny as Any,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private func store(_ account: String, _ value: String) throws {
        let data = Data(value.utf8)
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanTrue as Any,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw EBKeyError.keychain(status) }
    }

    private func load(_ account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny as Any,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? EBKeyError.notFound : EBKeyError.keychain(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw EBKeyError.notFound
        }
        return value
    }
}
