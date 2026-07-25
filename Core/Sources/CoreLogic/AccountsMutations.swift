import Foundation
import SwiftData
import CoreModel

extension CoreLogic.Accounts {
    public enum MutationError: Swift.Error, Equatable {
        case nameRequired
        case institutionRequired
        case invalidCurrency
        case amountMustBePositive
    }

    // Manual account: externalId is "manual:<uuid>", no connection. Opening balance seeds
    // both `balance` and `manualOpeningBalance` (web parity); the manual balance shape then
    // computes manualOpeningBalance + Σtx. Defaults to the default space when none given.
    @MainActor @discardableResult
    public static func createManual(
        name: String,
        type: AccountType = .bank,
        institution: String,
        currency: String = "EUR",
        group: AccountGroup? = nil,
        space: AccountSpace? = nil,
        openingBalance: Decimal? = nil,
        in ctx: ModelContext,
        now: Date = .now
    ) throws -> Account {
        let cleanName = try requireText(name, or: .nameRequired)
        let cleanInstitution = try requireText(institution, or: .institutionRequired)
        let cleanCurrency = try normalizedCurrency(currency)
        let resolvedSpace = try (space ?? CoreLogic.Spaces.ensureDefault(in: ctx, now: now))
        let account = Account(
            group: group,
            space: resolvedSpace,
            externalId: "manual:\(UUID().uuidString)",
            type: type,
            institution: cleanInstitution,
            name: cleanName,
            currency: cleanCurrency,
            balance: openingBalance,
            balanceUpdatedAt: openingBalance != nil ? now : nil,
            manualOpeningBalance: openingBalance,
            createdAt: now
        )
        ctx.insert(account)
        try ctx.saveTouchingChanges()
        return account
    }

    // Edits the user-controlled fields. Changing currency records the manual-override
    // marker so a future bank sync won't clobber it. Changing the space re-runs transfer
    // repair (cross-space groups break) — returns the repair result, or nil if unchanged.
    @MainActor @discardableResult
    public static func update(
        _ account: Account,
        name: String,
        alias: String? = nil,
        type: AccountType,
        institution: String,
        currency: String,
        group: AccountGroup?,
        space: AccountSpace?,
        excluded: Bool,
        openingBalance: Decimal?,
        in ctx: ModelContext,
        now: Date = .now
    ) throws -> CoreLogic.Transfers.RepairResult? {
        let cleanName = try requireText(name, or: .nameRequired)
        let cleanInstitution = try requireText(institution, or: .institutionRequired)
        let cleanCurrency = try normalizedCurrency(currency)

        let spaceChanged = account.space?.id != space?.id
        let currencyChanged = account.currency != cleanCurrency

        account.name = cleanName
        // Blank alias clears it rather than storing "" — displayName falls back to `name`.
        let cleanAlias = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        account.alias = (cleanAlias?.isEmpty ?? true) ? nil : cleanAlias
        account.type = type
        account.institution = cleanInstitution
        account.currency = cleanCurrency
        account.group = group
        account.space = space
        account.excluded = excluded
        // Opening balance is a manual-account concept; never clobber a connected account's
        // bank-reported `balance`.
        if account.connection == nil {
            account.balance = openingBalance
            account.manualOpeningBalance = openingBalance
            account.balanceUpdatedAt = openingBalance != nil ? now : nil
        }
        if currencyChanged { markCurrencyOverride(account, now: now) }

        if spaceChanged {
            return try CoreLogic.Transfers.repairGroups(in: ctx, accountId: account.id)
        }
        try ctx.saveTouchingChanges()
        return nil
    }

    @MainActor @discardableResult
    public static func setArchived(
        _ account: Account, _ archived: Bool, in ctx: ModelContext, now: Date = .now
    ) throws -> CoreLogic.Transfers.RepairResult? {
        guard account.archived != archived else { return nil }
        account.archived = archived
        // Archiving removes the account from transfer pairing — repair breaks its groups.
        return try CoreLogic.Transfers.repairGroups(in: ctx, accountId: account.id)
    }

    @MainActor
    public static func delete(_ account: Account, in ctx: ModelContext) throws {
        ctx.delete(account)
        try ctx.saveTouchingChanges()
    }

    // Balance anchor: "as of `date`, the real balance was `balance`". The displayed balance
    // then becomes anchor + Σ(tx after date) — see computeEurBalances/computeNativeBalances.
    // anchor and anchorAt are always set/cleared together (the web's PATCH refinement).
    @MainActor
    public static func setAnchor(
        _ account: Account, balance: Decimal, at date: Date, in ctx: ModelContext
    ) throws {
        account.balanceAnchor = balance
        account.balanceAnchorAt = date
        try ctx.saveTouchingChanges()
    }

    @MainActor
    public static func clearAnchor(_ account: Account, in ctx: ModelContext) throws {
        account.balanceAnchor = nil
        account.balanceAnchorAt = nil
        try ctx.saveTouchingChanges()
    }

    // Ports app/api/accounts/[id]/interest: a manual positive credit ("Interest") on the
    // account. externalId "manual-interest:<uuid>", counterparty = institution. EUR amounts
    // are their own EUR value; other currencies get amountEur backfilled by the FX pass.
    @MainActor @discardableResult
    public static func addInterest(
        _ account: Account, amount: Decimal, at date: Date, note: String? = nil,
        in ctx: ModelContext, now: Date = .now
    ) throws -> Transaction {
        guard amount > 0 else { throw MutationError.amountMustBePositive }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEur = account.currency.uppercased() == "EUR"
        let tx = Transaction(
            account: account,
            externalId: "manual-interest:\(UUID().uuidString)",
            bookedAt: date,
            amount: amount,
            currency: account.currency,
            amountEur: isEur ? amount : nil,
            fxRateUsed: isEur ? 1 : nil,
            direction: .credit,
            description: (trimmed?.isEmpty == false ? trimmed : "Interest"),
            counterparty: account.institution,
            categorySource: .bank,
            createdAt: now)
        ctx.insert(tx)
        try ctx.saveTouchingChanges()
        return tx
    }

    // MARK: - Helpers

    private static func requireText(_ value: String, or error: MutationError) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw error }
        return trimmed
    }

    private static func normalizedCurrency(_ raw: String) throws -> String {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            throw MutationError.invalidCurrency
        }
        return code
    }

    private static func markCurrencyOverride(_ account: Account, now: Date) {
        var meta = account.metadataJSON
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        meta["currencyOverride"] = true
        meta["currencyOverrideAt"] = ISO8601DateFormatter().string(from: now)
        account.metadataJSON = try? JSONSerialization.data(withJSONObject: meta)
    }
}
