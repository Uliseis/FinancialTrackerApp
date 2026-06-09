import XCTest
import Security
@testable import CoreIntegrations

final class EBJWTSignerTests: XCTestCase {
    private func makeRSAKey() throws -> SecKey {
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw XCTSkip("RSA key generation unavailable: \(String(describing: error))")
        }
        return key
    }

    private func b64urlDecode(_ s: String) -> Data {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t) ?? Data()
    }

    func test_jwt_structureAndClaims() throws {
        let key = try makeRSAKey()
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let signer = EBJWTSigner(applicationId: "app-123", privateKey: key, ttl: 3600,
                                 now: { fixed })
        let jwt = try signer.jwt()
        let parts = jwt.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)

        let header = try JSONSerialization.jsonObject(with: b64urlDecode(parts[0])) as! [String: Any]
        XCTAssertEqual(header["alg"] as? String, "RS256")
        XCTAssertEqual(header["typ"] as? String, "JWT")
        XCTAssertEqual(header["kid"] as? String, "app-123")

        let payload = try JSONSerialization.jsonObject(with: b64urlDecode(parts[1])) as! [String: Any]
        XCTAssertEqual(payload["iss"] as? String, "enablebanking.com")
        XCTAssertEqual(payload["aud"] as? String, "api.enablebanking.com")
        XCTAssertEqual(payload["iat"] as? Int, 1_700_000_000)
        XCTAssertEqual(payload["exp"] as? Int, 1_700_000_000 + 3600)
    }

    func test_signatureVerifiesAgainstPublicKey() throws {
        let key = try makeRSAKey()
        let pub = SecKeyCopyPublicKey(key)!
        let signer = EBJWTSigner(applicationId: "app", privateKey: key)
        let jwt = try signer.jwt()
        let parts = jwt.split(separator: ".").map(String.init)
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let signature = b64urlDecode(parts[2])

        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(
            pub, .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData, signature as CFData, &error
        )
        XCTAssertTrue(ok, "JWT signature must verify against the public key")
    }

    func test_bearerToken_prefix() throws {
        let signer = EBJWTSigner(applicationId: "app", privateKey: try makeRSAKey())
        XCTAssertTrue(try signer.bearerToken().hasPrefix("Bearer "))
    }

    // PEM (PKCS#1) round-trips through EBRSAKey.from and produces a usable signing key.
    func test_pemRoundTrip_pkcs1() throws {
        let key = try makeRSAKey()
        let der = SecKeyCopyExternalRepresentation(key, nil)! as Data  // PKCS#1 for RSA
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n"
            + der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            + "\n-----END RSA PRIVATE KEY-----"
        let parsed = try EBRSAKey.from(pem: pem)
        let signer = EBJWTSigner(applicationId: "app", privateKey: parsed)
        XCTAssertNoThrow(try signer.jwt())
    }

    func test_badPEM_throws() {
        XCTAssertThrowsError(try EBRSAKey.from(pem: "not base64 @@@"))
    }
}
