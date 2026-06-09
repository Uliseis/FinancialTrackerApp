import Foundation
import CloudKit
import CoreModel

public enum RecordCoding {

    // MARK: - Connection

    public static func encode(_ s: ConnectionSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.connection, id: s.id)
        r["connector"] = s.connector.rawValue as CKRecordValue
        r["institutionId"] = s.institutionId as CKRecordValue?
        r["institutionName"] = s.institutionName as CKRecordValue?
        r["sessionId"] = s.sessionId as CKRecordValue?
        r["accessTokenEnc"] = s.accessTokenEnc as CKRecordValue?
        r["refreshTokenEnc"] = s.refreshTokenEnc as CKRecordValue?
        r["metadataJSON"] = s.metadataJSON as CKRecordValue?
        r["status"] = s.status.rawValue as CKRecordValue
        r["expiresAt"] = s.expiresAt as CKRecordValue?
        r["lastSyncAt"] = s.lastSyncAt as CKRecordValue?
        r["lastError"] = s.lastError as CKRecordValue?
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodeConnection(_ r: CKRecord) throws -> ConnectionSnapshot {
        try validate(r, RecordType.connection)
        return ConnectionSnapshot(
            id: try uuid(r),
            connector: try requireEnum(r, "connector", Connector.self),
            institutionId: optionalString(r, "institutionId"),
            institutionName: optionalString(r, "institutionName"),
            sessionId: optionalString(r, "sessionId"),
            accessTokenEnc: optionalString(r, "accessTokenEnc"),
            refreshTokenEnc: optionalString(r, "refreshTokenEnc"),
            metadataJSON: optionalData(r, "metadataJSON"),
            status: try requireEnum(r, "status", ConnectionStatus.self),
            expiresAt: optionalDate(r, "expiresAt"),
            lastSyncAt: optionalDate(r, "lastSyncAt"),
            lastError: optionalString(r, "lastError"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - AccountGroup

    public static func encode(_ s: AccountGroupSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.accountGroup, id: s.id)
        r["name"] = s.name as CKRecordValue
        r["color"] = s.color as CKRecordValue?
        r["kind"] = s.kind.rawValue as CKRecordValue
        r["sortOrder"] = s.sortOrder as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodeAccountGroup(_ r: CKRecord) throws -> AccountGroupSnapshot {
        try validate(r, RecordType.accountGroup)
        return AccountGroupSnapshot(
            id: try uuid(r),
            name: try requireString(r, "name"),
            color: optionalString(r, "color"),
            kind: try requireEnum(r, "kind", AccountGroupKind.self),
            sortOrder: try requireInt(r, "sortOrder"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - AccountSpace

    public static func encode(_ s: AccountSpaceSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.accountSpace, id: s.id)
        r["name"] = s.name as CKRecordValue
        r["color"] = s.color as CKRecordValue?
        r["isDefault"] = s.isDefault as CKRecordValue
        r["sortOrder"] = s.sortOrder as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodeAccountSpace(_ r: CKRecord) throws -> AccountSpaceSnapshot {
        try validate(r, RecordType.accountSpace)
        return AccountSpaceSnapshot(
            id: try uuid(r),
            name: try requireString(r, "name"),
            color: optionalString(r, "color"),
            isDefault: try requireBool(r, "isDefault"),
            sortOrder: try requireInt(r, "sortOrder"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - Account

    public static func encode(_ s: AccountSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.account, id: s.id)
        r["connectionId"] = s.connectionId?.uuidString as CKRecordValue?
        r["groupId"] = s.groupId?.uuidString as CKRecordValue?
        r["spaceId"] = s.spaceId?.uuidString as CKRecordValue?
        r["externalId"] = s.externalId as CKRecordValue
        r["type"] = s.type.rawValue as CKRecordValue
        r["institution"] = s.institution as CKRecordValue
        r["name"] = s.name as CKRecordValue
        r["currency"] = s.currency as CKRecordValue
        r["iban"] = s.iban as CKRecordValue?
        r["balance"] = s.balance.map(decimalString) as CKRecordValue?
        r["balanceUpdatedAt"] = s.balanceUpdatedAt as CKRecordValue?
        r["metadataJSON"] = s.metadataJSON as CKRecordValue?
        r["archived"] = s.archived as CKRecordValue
        r["excluded"] = s.excluded as CKRecordValue
        r["manualOpeningBalance"] = s.manualOpeningBalance.map(decimalString) as CKRecordValue?
        r["balanceAnchor"] = s.balanceAnchor.map(decimalString) as CKRecordValue?
        r["balanceAnchorAt"] = s.balanceAnchorAt as CKRecordValue?
        r["createdAt"] = s.createdAt as CKRecordValue
        r["clock"] = s.clock as CKRecordValue
        return r
    }

    public static func decodeAccount(_ r: CKRecord) throws -> AccountSnapshot {
        try validate(r, RecordType.account)
        return AccountSnapshot(
            id: try uuid(r),
            connectionId: try optionalUUID(r, "connectionId"),
            groupId: try optionalUUID(r, "groupId"),
            spaceId: try optionalUUID(r, "spaceId"),
            externalId: try requireString(r, "externalId"),
            type: try requireEnum(r, "type", AccountType.self),
            institution: try requireString(r, "institution"),
            name: try requireString(r, "name"),
            currency: try requireString(r, "currency"),
            iban: optionalString(r, "iban"),
            balance: try optionalDecimal(r, "balance"),
            balanceUpdatedAt: optionalDate(r, "balanceUpdatedAt"),
            metadataJSON: optionalData(r, "metadataJSON"),
            archived: try requireBool(r, "archived"),
            excluded: try requireBool(r, "excluded"),
            manualOpeningBalance: try optionalDecimal(r, "manualOpeningBalance"),
            balanceAnchor: try optionalDecimal(r, "balanceAnchor"),
            balanceAnchorAt: optionalDate(r, "balanceAnchorAt"),
            createdAt: try requireDate(r, "createdAt"),
            clock: try requireDate(r, "clock")
        )
    }

    // MARK: - Category

    public static func encode(_ s: CategorySnapshot) -> CKRecord {
        let r = makeRecord(RecordType.category, id: s.id)
        r["name"] = s.name as CKRecordValue
        r["parentId"] = s.parentId?.uuidString as CKRecordValue?
        r["kind"] = s.kind as CKRecordValue
        r["color"] = s.color as CKRecordValue?
        r["createdAt"] = s.createdAt as CKRecordValue
        r["clock"] = s.clock as CKRecordValue
        return r
    }

    public static func decodeCategory(_ r: CKRecord) throws -> CategorySnapshot {
        try validate(r, RecordType.category)
        return CategorySnapshot(
            id: try uuid(r),
            name: try requireString(r, "name"),
            parentId: try optionalUUID(r, "parentId"),
            kind: try requireString(r, "kind"),
            color: optionalString(r, "color"),
            createdAt: try requireDate(r, "createdAt"),
            clock: try requireDate(r, "clock")
        )
    }

    // MARK: - CategoryRule

    public static func encode(_ s: CategoryRuleSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.categoryRule, id: s.id)
        r["pattern"] = s.pattern as CKRecordValue
        r["field"] = s.field.rawValue as CKRecordValue
        r["matchType"] = s.matchType.rawValue as CKRecordValue
        r["categoryId"] = s.categoryId?.uuidString as CKRecordValue?
        r["priority"] = s.priority as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["clock"] = s.clock as CKRecordValue
        return r
    }

    public static func decodeCategoryRule(_ r: CKRecord) throws -> CategoryRuleSnapshot {
        try validate(r, RecordType.categoryRule)
        return CategoryRuleSnapshot(
            id: try uuid(r),
            pattern: try requireString(r, "pattern"),
            field: try requireEnum(r, "field", RuleField.self),
            matchType: try requireEnum(r, "matchType", RuleMatch.self),
            categoryId: try optionalUUID(r, "categoryId"),
            priority: try requireInt(r, "priority"),
            createdAt: try requireDate(r, "createdAt"),
            clock: try requireDate(r, "clock")
        )
    }

    // MARK: - TransferRoute

    public static func encode(_ s: TransferRouteSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.transferRoute, id: s.id)
        r["pattern"] = s.pattern as CKRecordValue
        r["field"] = s.field.rawValue as CKRecordValue
        r["matchType"] = s.matchType.rawValue as CKRecordValue
        r["sourceAccountId"] = s.sourceAccountId?.uuidString as CKRecordValue?
        r["targetAccountId"] = s.targetAccountId?.uuidString as CKRecordValue?
        r["direction"] = s.direction?.rawValue as CKRecordValue?
        r["priority"] = s.priority as CKRecordValue
        r["enabled"] = s.enabled as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodeTransferRoute(_ r: CKRecord) throws -> TransferRouteSnapshot {
        try validate(r, RecordType.transferRoute)
        return TransferRouteSnapshot(
            id: try uuid(r),
            pattern: try requireString(r, "pattern"),
            field: try requireEnum(r, "field", RuleField.self),
            matchType: try requireEnum(r, "matchType", RuleMatch.self),
            sourceAccountId: try optionalUUID(r, "sourceAccountId"),
            targetAccountId: try optionalUUID(r, "targetAccountId"),
            direction: try optionalEnum(r, "direction", TxDirection.self),
            priority: try requireInt(r, "priority"),
            enabled: try requireBool(r, "enabled"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - TransferGroup

    public static func encode(_ s: TransferGroupSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.transferGroup, id: s.id)
        r["pairedAt"] = s.pairedAt as CKRecordValue?
        r["routeId"] = s.routeId?.uuidString as CKRecordValue?
        r["createdAt"] = s.createdAt as CKRecordValue
        r["clock"] = s.clock as CKRecordValue
        return r
    }

    public static func decodeTransferGroup(_ r: CKRecord) throws -> TransferGroupSnapshot {
        try validate(r, RecordType.transferGroup)
        return TransferGroupSnapshot(
            id: try uuid(r),
            pairedAt: optionalDate(r, "pairedAt"),
            routeId: try optionalUUID(r, "routeId"),
            createdAt: try requireDate(r, "createdAt"),
            clock: try requireDate(r, "clock")
        )
    }

    // MARK: - Budget

    public static func encode(_ s: BudgetSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.budget, id: s.id)
        r["categoryId"] = s.categoryId?.uuidString as CKRecordValue?
        r["amountEur"] = decimalString(s.amountEur) as CKRecordValue
        r["period"] = s.period.rawValue as CKRecordValue
        r["startsOn"] = s.startsOn as CKRecordValue
        r["active"] = s.active as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodeBudget(_ r: CKRecord) throws -> BudgetSnapshot {
        try validate(r, RecordType.budget)
        return BudgetSnapshot(
            id: try uuid(r),
            categoryId: try optionalUUID(r, "categoryId"),
            amountEur: try requireDecimal(r, "amountEur"),
            period: try requireEnum(r, "period", BudgetPeriod.self),
            startsOn: try requireDate(r, "startsOn"),
            active: try requireBool(r, "active"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - FxRate

    public static func encode(_ s: FxRateSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.fxRate, id: s.id)
        r["date"] = s.date as CKRecordValue
        r["currency"] = s.currency as CKRecordValue
        r["rate"] = decimalString(s.rate) as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["clock"] = s.clock as CKRecordValue
        return r
    }

    public static func decodeFxRate(_ r: CKRecord) throws -> FxRateSnapshot {
        try validate(r, RecordType.fxRate)
        return FxRateSnapshot(
            id: try uuid(r),
            date: try requireDate(r, "date"),
            currency: try requireString(r, "currency"),
            rate: try requireDecimal(r, "rate"),
            createdAt: try requireDate(r, "createdAt"),
            clock: try requireDate(r, "clock")
        )
    }

    // MARK: - Transaction

    public static func encode(_ s: TransactionSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.transaction, id: s.id)
        r["accountId"] = s.accountId?.uuidString as CKRecordValue?
        r["externalId"] = s.externalId as CKRecordValue
        r["bookedAt"] = s.bookedAt as CKRecordValue
        r["valueAt"] = s.valueAt as CKRecordValue?
        r["amount"] = decimalString(s.amount) as CKRecordValue
        r["currency"] = s.currency as CKRecordValue
        r["amountEur"] = s.amountEur.map(decimalString) as CKRecordValue?
        r["fxRateUsed"] = s.fxRateUsed.map(decimalString) as CKRecordValue?
        r["direction"] = s.direction.rawValue as CKRecordValue
        r["transactionDescription"] = s.transactionDescription as CKRecordValue?
        r["counterparty"] = s.counterparty as CKRecordValue?
        r["categoryId"] = s.categoryId?.uuidString as CKRecordValue?
        r["categorySource"] = s.categorySource.rawValue as CKRecordValue
        r["isTransfer"] = s.isTransfer as CKRecordValue
        r["transferGroupId"] = s.transferGroupId?.uuidString as CKRecordValue?
        r["routedFromTxId"] = s.routedFromTxId?.uuidString as CKRecordValue?
        r["routeId"] = s.routeId?.uuidString as CKRecordValue?
        r["sharedExpenseGroupId"] = s.sharedExpenseGroupId?.uuidString as CKRecordValue?
        r["rawJSON"] = s.rawJSON as CKRecordValue?
        r["createdAt"] = s.createdAt as CKRecordValue
        r["clock"] = s.clock as CKRecordValue
        return r
    }

    public static func decodeTransaction(_ r: CKRecord) throws -> TransactionSnapshot {
        try validate(r, RecordType.transaction)
        return TransactionSnapshot(
            id: try uuid(r),
            accountId: try optionalUUID(r, "accountId"),
            externalId: try requireString(r, "externalId"),
            bookedAt: try requireDate(r, "bookedAt"),
            valueAt: optionalDate(r, "valueAt"),
            amount: try requireDecimal(r, "amount"),
            currency: try requireString(r, "currency"),
            amountEur: try optionalDecimal(r, "amountEur"),
            fxRateUsed: try optionalDecimal(r, "fxRateUsed"),
            direction: try requireEnum(r, "direction", TxDirection.self),
            transactionDescription: optionalString(r, "transactionDescription"),
            counterparty: optionalString(r, "counterparty"),
            categoryId: try optionalUUID(r, "categoryId"),
            categorySource: try requireEnum(r, "categorySource", CategorySource.self),
            isTransfer: try requireBool(r, "isTransfer"),
            transferGroupId: try optionalUUID(r, "transferGroupId"),
            routedFromTxId: try optionalUUID(r, "routedFromTxId"),
            routeId: try optionalUUID(r, "routeId"),
            sharedExpenseGroupId: try optionalUUID(r, "sharedExpenseGroupId"),
            rawJSON: optionalData(r, "rawJSON"),
            createdAt: try requireDate(r, "createdAt"),
            clock: try requireDate(r, "clock")
        )
    }

    // MARK: - SharedExpenseGroup

    public static func encode(_ s: SharedExpenseGroupSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.sharedExpenseGroup, id: s.id)
        r["label"] = s.label as CKRecordValue
        r["primaryTxId"] = s.primaryTxId?.uuidString as CKRecordValue?
        r["attributionMonth"] = s.attributionMonth as CKRecordValue
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodeSharedExpenseGroup(_ r: CKRecord) throws -> SharedExpenseGroupSnapshot {
        try validate(r, RecordType.sharedExpenseGroup)
        return SharedExpenseGroupSnapshot(
            id: try uuid(r),
            label: try requireString(r, "label"),
            primaryTxId: try optionalUUID(r, "primaryTxId"),
            attributionMonth: try requireDate(r, "attributionMonth"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - PortfolioValuation

    public static func encode(_ s: PortfolioValuationSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.portfolioValuation, id: s.id)
        r["accountId"] = s.accountId?.uuidString as CKRecordValue?
        r["asOf"] = s.asOf as CKRecordValue
        r["marketValueEur"] = decimalString(s.marketValueEur) as CKRecordValue
        r["cashValueEur"] = s.cashValueEur.map(decimalString) as CKRecordValue?
        r["notes"] = s.notes as CKRecordValue?
        r["createdAt"] = s.createdAt as CKRecordValue
        r["updatedAt"] = s.updatedAt as CKRecordValue
        return r
    }

    public static func decodePortfolioValuation(_ r: CKRecord) throws -> PortfolioValuationSnapshot {
        try validate(r, RecordType.portfolioValuation)
        return PortfolioValuationSnapshot(
            id: try uuid(r),
            accountId: try optionalUUID(r, "accountId"),
            asOf: try requireDate(r, "asOf"),
            marketValueEur: try requireDecimal(r, "marketValueEur"),
            cashValueEur: try optionalDecimal(r, "cashValueEur"),
            notes: optionalString(r, "notes"),
            createdAt: try requireDate(r, "createdAt"),
            updatedAt: try requireDate(r, "updatedAt")
        )
    }

    // MARK: - SyncRun

    public static func encode(_ s: SyncRunSnapshot) -> CKRecord {
        let r = makeRecord(RecordType.syncRun, id: s.id)
        r["connector"] = s.connector.rawValue as CKRecordValue
        r["connectionId"] = s.connectionId?.uuidString as CKRecordValue?
        r["startedAt"] = s.startedAt as CKRecordValue
        r["finishedAt"] = s.finishedAt as CKRecordValue?
        r["status"] = s.status.rawValue as CKRecordValue
        r["insertedTransactions"] = s.insertedTransactions as CKRecordValue
        r["error"] = s.error as CKRecordValue?
        r["rawJSON"] = s.rawJSON as CKRecordValue?
        return r
    }

    public static func decodeSyncRun(_ r: CKRecord) throws -> SyncRunSnapshot {
        try validate(r, RecordType.syncRun)
        return SyncRunSnapshot(
            id: try uuid(r),
            connector: try requireEnum(r, "connector", Connector.self),
            connectionId: try optionalUUID(r, "connectionId"),
            startedAt: try requireDate(r, "startedAt"),
            finishedAt: optionalDate(r, "finishedAt"),
            status: try requireEnum(r, "status", SyncRunStatus.self),
            insertedTransactions: try requireInt(r, "insertedTransactions"),
            error: optionalString(r, "error"),
            rawJSON: optionalData(r, "rawJSON")
        )
    }

    // MARK: - helpers

    private static func makeRecord(_ type: String, id: UUID) -> CKRecord {
        let rid = CKRecord.ID(recordName: id.uuidString)
        return CKRecord(recordType: type, recordID: rid)
    }

    private static func validate(_ r: CKRecord, _ expected: String) throws {
        if r.recordType != expected {
            throw RecordCodingError.wrongRecordType(found: r.recordType, expected: expected)
        }
    }

    private static func uuid(_ r: CKRecord) throws -> UUID {
        let name = r.recordID.recordName
        guard let u = UUID(uuidString: name) else {
            throw RecordCodingError.recordNameNotUUID(name)
        }
        return u
    }

    private static func requireString(_ r: CKRecord, _ field: String) throws -> String {
        guard let v = r[field] as? String else {
            throw RecordCodingError.missingField(recordType: r.recordType, field: field)
        }
        return v
    }

    private static func optionalString(_ r: CKRecord, _ field: String) -> String? {
        r[field] as? String
    }

    private static func requireDate(_ r: CKRecord, _ field: String) throws -> Date {
        guard let v = r[field] as? Date else {
            throw RecordCodingError.missingField(recordType: r.recordType, field: field)
        }
        return v
    }

    private static func optionalDate(_ r: CKRecord, _ field: String) -> Date? {
        r[field] as? Date
    }

    private static func requireInt(_ r: CKRecord, _ field: String) throws -> Int {
        if let v = r[field] as? Int { return v }
        if let n = r[field] as? NSNumber { return n.intValue }
        throw RecordCodingError.missingField(recordType: r.recordType, field: field)
    }

    private static func requireBool(_ r: CKRecord, _ field: String) throws -> Bool {
        if let v = r[field] as? Bool { return v }
        if let n = r[field] as? NSNumber { return n.boolValue }
        throw RecordCodingError.missingField(recordType: r.recordType, field: field)
    }

    private static func requireDecimal(_ r: CKRecord, _ field: String) throws -> Decimal {
        let s = try requireString(r, field)
        guard let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw RecordCodingError.invalidValue(recordType: r.recordType, field: field, value: s)
        }
        return d
    }

    private static func optionalDecimal(_ r: CKRecord, _ field: String) throws -> Decimal? {
        guard let s = r[field] as? String else { return nil }
        guard let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw RecordCodingError.invalidValue(recordType: r.recordType, field: field, value: s)
        }
        return d
    }

    private static func optionalUUID(_ r: CKRecord, _ field: String) throws -> UUID? {
        guard let s = r[field] as? String else { return nil }
        guard let u = UUID(uuidString: s) else {
            throw RecordCodingError.invalidValue(recordType: r.recordType, field: field, value: s)
        }
        return u
    }

    private static func requireEnum<E: RawRepresentable>(
        _ r: CKRecord, _ field: String, _ type: E.Type
    ) throws -> E where E.RawValue == String {
        let s = try requireString(r, field)
        guard let e = E(rawValue: s) else {
            throw RecordCodingError.invalidValue(recordType: r.recordType, field: field, value: s)
        }
        return e
    }

    private static func optionalEnum<E: RawRepresentable>(
        _ r: CKRecord, _ field: String, _ type: E.Type
    ) throws -> E? where E.RawValue == String {
        guard let s = r[field] as? String else { return nil }
        guard let e = E(rawValue: s) else {
            throw RecordCodingError.invalidValue(recordType: r.recordType, field: field, value: s)
        }
        return e
    }

    private static func optionalData(_ r: CKRecord, _ field: String) -> Data? {
        r[field] as? Data
    }

    private static func decimalString(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }
}
