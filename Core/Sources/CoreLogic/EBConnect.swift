import Foundation
import SwiftData
import CoreModel
import CoreIntegrations

extension CoreLogic {
    // Ports api/enablebanking/connect + callback: everything except the network calls and
    // the ASWebAuthenticationSession, which live in the App. The web's 90-day default
    // consent validity carries over.
    public enum EBConnect {
        public static let defaultValidityDays = 90

        public enum CallbackError: Swift.Error, Equatable {
            case bankReported(String)
            case missingCode
            case missingState
            case stateMismatch
        }

        nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

        public static func makeAuthRequest(
            aspspName: String, country: String, redirectUrl: String, state: String,
            validForDays: Int = defaultValidityDays, psuType: String = "personal",
            now: Date = .now
        ) -> (request: AuthRequest, validUntil: Date) {
            let validUntil = now.addingTimeInterval(Double(validForDays) * 86_400)
            let request = AuthRequest(
                access: .init(validUntil: iso.string(from: validUntil)),
                aspsp: .init(name: aspspName, country: country),
                state: state,
                redirectUrl: redirectUrl,
                psuType: psuType
            )
            return (request, validUntil)
        }

        // Creates (or repoints, for re-auth) the pending Connection row before the browser
        // round-trip, mirroring the web's insert/update in the connect route.
        @MainActor @discardableResult
        public static func prepareConnection(
            existing: Connection? = nil,
            aspspName: String, country: String, state: String, authorizationId: String,
            validUntil: Date, psuType: String = "personal",
            in ctx: ModelContext, now: Date = .now
        ) throws -> Connection {
            let connection = existing ?? Connection(connector: .enablebanking)
            connection.institutionId = aspspName
            connection.institutionName = aspspName
            connection.status = .pending
            connection.expiresAt = validUntil
            mergeMetadata([
                "state": state,
                "authorizationId": authorizationId,
                "country": country,
                "psuType": psuType,
            ], into: connection)
            connection.updatedAt = now
            if existing == nil { ctx.insert(connection) }
            try ctx.save()
            return connection
        }

        public static func parseCallback(_ url: URL) throws -> (code: String, state: String) {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                items.first { $0.name == name }?.value
            }
            if let error = value("error") { throw CallbackError.bankReported(error) }
            guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
            guard let state = value("state"), !state.isEmpty else { throw CallbackError.missingState }
            return (code, state)
        }

        // Mirrors the callback route's connection update from the created session. When
        // access.valid_until is absent the expiry simply isn't updated — the web's
        // optional-chained behavior, not a guess.
        @MainActor
        public static func applySession(
            _ session: CreateSessionResponse, to connection: Connection,
            expectedState: String, in ctx: ModelContext, now: Date = .now
        ) throws {
            guard storedState(of: connection) == expectedState else {
                throw CallbackError.stateMismatch
            }
            connection.sessionId = session.sessionId
            connection.status = session.status == "AUTHORIZED" ? .active : .pending
            if let valid = session.access?.validUntil, let date = parseISO(valid) {
                connection.expiresAt = date
            }
            var meta: [String: Any] = ["sessionStatus": session.status]
            if let aspsp = session.aspsp {
                meta["aspsp"] = ["name": aspsp.name, "country": aspsp.country]
            }
            meta["accountUids"] = EBHelpers.sessionAccounts(session).compactMap(\.uid)
            if let authorized = session.authorized { meta["authorized"] = authorized }
            mergeMetadata(meta, into: connection)
            connection.updatedAt = now
            try ctx.save()
        }

        public static func storedState(of connection: Connection) -> String? {
            metadata(of: connection)["state"] as? String
        }

        public static func storedCountry(of connection: Connection) -> String? {
            metadata(of: connection)["country"] as? String
        }

        // metadataJSON is an opaque jsonb blob (same treatment as Account.metadataJSON):
        // read-merge-write via JSONSerialization, never a Codable struct.
        private static func metadata(of connection: Connection) -> [String: Any] {
            guard let data = connection.metadataJSON,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return object
        }

        private static func mergeMetadata(_ updates: [String: Any], into connection: Connection) {
            var meta = metadata(of: connection)
            for (key, value) in updates { meta[key] = value }
            connection.metadataJSON = try? JSONSerialization.data(withJSONObject: meta)
        }

        private static func parseISO(_ string: String) -> Date? {
            if let date = iso.date(from: string) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string)
        }
    }
}
