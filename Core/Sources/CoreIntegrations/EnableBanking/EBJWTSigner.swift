import Foundation
import Security

public protocol EBTokenProvider: Sendable {
    func bearerToken() throws -> String
}

public enum EBSigningError: Error, Equatable {
    case signatureFailed(String)
    case serializationFailed
}

// Mirrors Spec/lib/enablebanking.ts signJwt(): an RS256 JWT whose only claims are app
// identity (kid = applicationId) + iss/aud/iat/exp. The payload carries nothing
// user-specific — it is purely the application credential. Signed on-device with the
// Security framework (CryptoKit has no RSA).
public final class EBJWTSigner: EBTokenProvider, @unchecked Sendable {
    // @unchecked: applicationId is immutable; SecKey signing is thread-safe.
    private let applicationId: String
    private let privateKey: SecKey
    private let now: @Sendable () -> Date
    private let ttl: TimeInterval

    public init(
        applicationId: String,
        privateKey: SecKey,
        ttl: TimeInterval = 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.applicationId = applicationId
        self.privateKey = privateKey
        self.ttl = ttl
        self.now = now
    }

    private struct Header: Encodable { let typ = "JWT"; let alg = "RS256"; let kid: String }
    private struct Payload: Encodable { let iss: String; let aud: String; let iat: Int; let exp: Int }

    public func jwt() throws -> String {
        let iat = Int(now().timeIntervalSince1970)
        let header = Header(kid: applicationId)
        let payload = Payload(iss: "enablebanking.com", aud: "api.enablebanking.com",
                              iat: iat, exp: iat + Int(ttl))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let headerData = try? encoder.encode(header),
              let payloadData = try? encoder.encode(payload) else {
            throw EBSigningError.serializationFailed
        }
        let signingInput = "\(Self.base64url(headerData)).\(Self.base64url(payloadData))"
        guard let inputData = signingInput.data(using: .utf8) else {
            throw EBSigningError.serializationFailed
        }
        let signature = try Self.sign(inputData, with: privateKey)
        return "\(signingInput).\(Self.base64url(signature))"
    }

    public func bearerToken() throws -> String { "Bearer \(try jwt())" }

    static func sign(_ data: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error
        ) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw EBSigningError.signatureFailed(message)
        }
        return sig as Data
    }

    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}
