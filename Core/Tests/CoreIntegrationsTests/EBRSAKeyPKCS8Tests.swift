import XCTest
import Security
@testable import CoreIntegrations

// EB hands out application keys as PKCS#8 ("BEGIN PRIVATE KEY") — confirmed against the
// production key 2026-06-10. These tests cover the PKCS#8 unwrap path that the PKCS#1
// round-trip in EBJWTSignerTests cannot reach. No key material lives in the repo: the
// fixture is generated fresh by openssl on every run, and the production key is only
// read from a local path via EB_KEY_PEM_PATH.
final class EBRSAKeyPKCS8Tests: XCTestCase {
    private func opensslPKCS8PEM(bits: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["genpkey", "-algorithm", "RSA",
                             "-pkeyopt", "rsa_keygen_bits:\(bits)"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw XCTSkip("openssl unavailable: \(error)")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let pem = String(data: data, encoding: .utf8),
              pem.contains("-----BEGIN PRIVATE KEY-----") else {
            throw XCTSkip("openssl did not produce a PKCS#8 key")
        }
        return pem
    }

    private func assertParsesAndSigns(_ pem: String) throws {
        let key = try EBRSAKey.from(pem: pem)
        let signer = EBJWTSigner(applicationId: "app", privateKey: key)
        let jwt = try signer.jwt()
        let parts = jwt.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)

        let pub = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        var sig = parts[2].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while sig.count % 4 != 0 { sig += "=" }
        let signature = try XCTUnwrap(Data(base64Encoded: sig))
        XCTAssertTrue(SecKeyVerifySignature(
            pub, .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData, signature as CFData, nil
        ))
    }

    func test_opensslPKCS8_parsesAndSigns() throws {
        try assertParsesAndSigns(try opensslPKCS8PEM(bits: 2048))
    }

    // Validates the real EB application key without it entering the repo:
    //   EB_KEY_PEM_PATH=~/Downloads/<appid>.pem swift test --package-path Core \
    //     --filter EBRSAKeyPKCS8Tests
    func test_localProductionKey_parsesAndSigns() throws {
        guard let path = ProcessInfo.processInfo.environment["EB_KEY_PEM_PATH"] else {
            throw XCTSkip("EB_KEY_PEM_PATH not set")
        }
        let expanded = NSString(string: path).expandingTildeInPath
        let pem = try String(contentsOfFile: expanded, encoding: .utf8)
        try assertParsesAndSigns(pem)
    }
}
