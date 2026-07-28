import SwiftUI
import SwiftData
import AuthenticationServices
import CoreModel
import CoreLogic
import CoreIntegrations

// The registered Enable Banking redirect URL for iOS. A private-use scheme keeps the whole
// round trip on the device — no domain, no hosting, nothing to squat. An https callback
// would need an Associated Domains entitlement (webcredentials) plus an AASA file served at
// that host; ASWebAuthenticationSession refuses the redirect without it.
enum EBConfig {
    static let callbackScheme = "odysseyfinance"
    static let redirectURL = URL(string: "\(callbackScheme)://enablebanking/callback")!
}

// Full bank-link round trip: startAuth → in-app browser → callback code → createSession →
// Connection row updated. Used for both first-time links and re-auth (existing != nil).
@MainActor
enum BankLink {
    struct Outcome {
        let authorized: Bool
        let accountCount: Int
    }

    static func link(
        aspspName: String, country: String,
        existing: Connection? = nil, in ctx: ModelContext
    ) async throws -> Outcome {
        let signer = try EBKeychain().loadSigner()
        let client = EBClient(tokenProvider: signer)
        let state = UUID().uuidString
        let (request, validUntil) = CoreLogic.EBConnect.makeAuthRequest(
            aspspName: aspspName, country: country,
            redirectUrl: EBConfig.redirectURL.absoluteString, state: state)
        let auth = try await client.startAuth(request)
        let connection = try CoreLogic.EBConnect.prepareConnection(
            existing: existing, aspspName: aspspName, country: country,
            state: state, authorizationId: auth.authorizationId,
            validUntil: validUntil, in: ctx)
        guard let authURL = URL(string: auth.url) else { throw URLError(.badURL) }

        let callback = try await BankAuthSession.authenticate(url: authURL)
        let (code, returnedState) = try CoreLogic.EBConnect.parseCallback(callback)
        let session = try await client.createSession(code: code)
        try CoreLogic.EBConnect.applySession(
            session, to: connection, expectedState: returnedState, in: ctx)
        return Outcome(
            authorized: session.status == "AUTHORIZED",
            accountCount: EBHelpers.sessionAccounts(session).count)
    }
}

// ASWebAuthenticationSession wrapper. The session and its context provider must stay
// alive until the completion fires.
@MainActor
private enum BankAuthSession {
    private static var active: (ASWebAuthenticationSession, WebAuthContext)?

    static func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let context = WebAuthContext()
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(EBConfig.callbackScheme)
            ) { callbackURL, error in
                Task { @MainActor in active = nil }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            session.presentationContextProvider = context
            active = (session, context)
            if !session.start() {
                active = nil
                continuation.resume(throwing: CancellationError())
            }
        }
    }
}

private final class WebAuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.compactMap(\.keyWindow).first ?? scenes.flatMap(\.windows).first {
            return window
        }
        guard let scene = scenes.first else {
            preconditionFailure("Auth session started with no connected window scene")
        }
        return UIWindow(windowScene: scene)
    }
}

extension Error {
    // User-closed auth sheet — not an error worth surfacing.
    var isAuthCancellation: Bool {
        self is CancellationError ||
        (self as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}
