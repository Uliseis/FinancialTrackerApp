import Foundation

enum DumpParse {
    static let supportedSchemaVersion = 1

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.calendar = Calendar(identifier: .iso8601)
        return f
    }()

    static func uuid(_ s: String, table: String, id: String, field: String) throws -> UUID {
        guard let u = UUID(uuidString: s) else {
            throw ImportError.invalidUUID(table: table, id: id, field: field, value: s)
        }
        return u
    }

    static func uuid(_ s: String?, table: String, id: String, field: String) throws -> UUID? {
        guard let s else { return nil }
        guard let u = UUID(uuidString: s) else {
            throw ImportError.invalidUUID(table: table, id: id, field: field, value: s)
        }
        return u
    }

    static func decimal(_ s: String, table: String, id: String, field: String) throws -> Decimal {
        guard let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ImportError.invalidDecimal(table: table, id: id, field: field, value: s)
        }
        return d
    }

    static func decimal(_ s: String?, table: String, id: String, field: String) throws -> Decimal? {
        guard let s else { return nil }
        guard let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ImportError.invalidDecimal(table: table, id: id, field: field, value: s)
        }
        return d
    }

    static func timestamp(_ s: String, table: String, id: String, field: String) throws -> Date {
        if let d = isoFractional.date(from: s) { return d }
        if let d = iso.date(from: s) { return d }
        throw ImportError.invalidDate(table: table, id: id, field: field, value: s)
    }

    static func timestamp(_ s: String?, table: String, id: String, field: String) throws -> Date? {
        guard let s else { return nil }
        if let d = isoFractional.date(from: s) { return d }
        if let d = iso.date(from: s) { return d }
        throw ImportError.invalidDate(table: table, id: id, field: field, value: s)
    }

    static func date(_ s: String, table: String, id: String, field: String) throws -> Date {
        if let d = dateOnly.date(from: s) { return d }
        throw ImportError.invalidDate(table: table, id: id, field: field, value: s)
    }

    static func enumValue<E: RawRepresentable>(
        _ s: String,
        as: E.Type,
        table: String,
        id: String,
        field: String,
        valid: [String]
    ) throws -> E where E.RawValue == String {
        guard let e = E(rawValue: s) else {
            throw ImportError.invalidEnum(
                table: table, id: id, field: field, value: s, valid: valid
            )
        }
        return e
    }
}
