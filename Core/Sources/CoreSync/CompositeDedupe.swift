import Foundation

public enum DedupeOutcome: Equatable, Sendable {
    case insert
    case sameRow(existingId: UUID)
    case duplicate(winnerId: UUID, loserId: UUID)
}

public struct TransactionCompositeKey: Hashable, Sendable {
    public let accountId: UUID
    public let externalId: String

    public init(accountId: UUID, externalId: String) {
        self.accountId = accountId
        self.externalId = externalId
    }
}

public struct FxRateCompositeKey: Hashable, Sendable {
    public let date: Date
    public let currency: String

    public init(date: Date, currency: String) {
        self.date = date
        self.currency = currency
    }
}

extension TransactionSnapshot {
    public var compositeKey: TransactionCompositeKey? {
        guard let accountId else { return nil }
        return TransactionCompositeKey(accountId: accountId, externalId: externalId)
    }
}

extension FxRateSnapshot {
    public var compositeKey: FxRateCompositeKey {
        FxRateCompositeKey(date: date, currency: currency)
    }
}

public enum CompositeDedupe {

    public static func dedupe(
        incoming: TransactionSnapshot,
        existing: TransactionSnapshot?
    ) -> DedupeOutcome {
        decide(
            incomingId: incoming.id, incomingCreatedAt: incoming.createdAt,
            existing: existing.map { ($0.id, $0.createdAt) }
        )
    }

    public static func dedupe(
        incoming: FxRateSnapshot,
        existing: FxRateSnapshot?
    ) -> DedupeOutcome {
        decide(
            incomingId: incoming.id, incomingCreatedAt: incoming.createdAt,
            existing: existing.map { ($0.id, $0.createdAt) }
        )
    }

    private static func decide(
        incomingId: UUID,
        incomingCreatedAt: Date,
        existing: (UUID, Date)?
    ) -> DedupeOutcome {
        guard let (existingId, existingCreatedAt) = existing else { return .insert }
        if existingId == incomingId { return .sameRow(existingId: existingId) }
        return .duplicate(
            winnerId: pickWinner(
                a: existingId, aCreatedAt: existingCreatedAt,
                b: incomingId, bCreatedAt: incomingCreatedAt
            ),
            loserId: pickLoser(
                a: existingId, aCreatedAt: existingCreatedAt,
                b: incomingId, bCreatedAt: incomingCreatedAt
            )
        )
    }

    private static func pickWinner(
        a: UUID, aCreatedAt: Date, b: UUID, bCreatedAt: Date
    ) -> UUID {
        if aCreatedAt < bCreatedAt { return a }
        if aCreatedAt > bCreatedAt { return b }
        return a.uuidString < b.uuidString ? a : b
    }

    private static func pickLoser(
        a: UUID, aCreatedAt: Date, b: UUID, bCreatedAt: Date
    ) -> UUID {
        if aCreatedAt < bCreatedAt { return b }
        if aCreatedAt > bCreatedAt { return a }
        return a.uuidString < b.uuidString ? b : a
    }
}
