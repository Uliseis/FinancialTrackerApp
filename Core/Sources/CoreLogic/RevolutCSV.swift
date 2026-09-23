import Foundation

extension CoreLogic {
    // Port of Spec/lib/csv-import.ts parsing. The externalId must match the web scheme
    // byte-for-byte or every historical row re-imports as a duplicate:
    //   revolutcsv:v1:{startedUTCDay}:{amountAsWritten}:{slug}:{dupIdx}
    public enum RevolutCSV {
        public struct Row: Equatable, Sendable {
            public let externalId: String
            public let startedAt: Date
            public let completedAt: Date?
            public let amount: Decimal
            public let description: String?
        }

        public struct Parsed: Equatable, Sendable {
            public let rows: [Row]
            public let skippedTransfers: Int
            public var skippedNotCompleted = 0
            public let errors: [String]
        }

        public enum ParseError: Error, Equatable {
            case missingColumns([String])
        }

        static let requiredColumns = ["Type", "Started Date", "Completed Date", "Description", "Amount"]

        public static func parse(_ text: String) throws -> Parsed {
            var records = splitRecords(text)
            guard !records.isEmpty else { throw ParseError.missingColumns(requiredColumns) }
            let header = records.removeFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            let missing = requiredColumns.filter { !header.contains($0) }
            guard missing.isEmpty else { throw ParseError.missingColumns(missing) }
            func field(_ record: [String], _ name: String) -> String? {
                guard let i = header.firstIndex(of: name), i < record.count else { return nil }
                return record[i]
            }

            var dupCounts: [String: Int] = [:]
            var rows: [Row] = []
            var skipped = 0
            var notCompleted = 0
            var errors: [String] = []
            for (i, record) in records.enumerated() {
                if record.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
                let type = (field(record, "Type") ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                // Top-ups already exist as transfer mirror legs; re-adding them breaks the invariants.
                if type == "TRANSFER" || type == "TOPUP" { skipped += 1; continue }
                // A REVERTED hold or DECLINED attempt never moved money.
                if let state = field(record, "State"),
                   state.trimmingCharacters(in: .whitespaces).uppercased() != "COMPLETED" {
                    notCompleted += 1; continue
                }
                guard let started = parseMadrid(field(record, "Started Date")),
                      let amountText = normalizeAmount(field(record, "Amount")),
                      var amount = Decimal(string: amountText) else {
                    errors.append("row \(i + 1): missing date or amount")
                    continue
                }
                if let feeText = normalizeAmount(field(record, "Fee")), let fee = Decimal(string: feeText), fee >= 0 {
                    amount -= fee
                }
                let completed = parseMadrid(field(record, "Completed Date")) ?? started
                let rawDescription = field(record, "Description") ?? ""
                let description = rawDescription.trimmingCharacters(in: .whitespaces)
                let day = dayKey(started)
                let slugged = slug(rawDescription)
                let signature = "\(day)|\(amountText)|\(slugged)"
                let dupIdx = dupCounts[signature, default: 0]
                dupCounts[signature] = dupIdx + 1
                rows.append(Row(
                    externalId: "revolutcsv:v1:\(day):\(amountText):\(slugged):\(dupIdx)",
                    startedAt: started,
                    completedAt: completed,
                    amount: amount,
                    description: description.isEmpty ? nil : description))
            }
            return Parsed(rows: rows, skippedTransfers: skipped, skippedNotCompleted: notCompleted, errors: errors)
        }

        // lower → NFKD → [^a-z0-9]+ → "-" → trim → first 40. Combining marks are separators,
        // not dropped: "El Corte Inglés" → "el-corte-ingle-s".
        static func slug(_ input: String) -> String {
            let normalized = input.lowercased().decomposedStringWithCompatibilityMapping
            var out = ""
            var pendingSeparator = false
            for scalar in normalized.unicodeScalars {
                let keep = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
                if keep {
                    if pendingSeparator, !out.isEmpty { out.append("-") }
                    pendingSeparator = false
                    out.unicodeScalars.append(scalar)
                } else {
                    pendingSeparator = true
                }
            }
            return String(out.prefix(40))
        }

        // Revolut writes wall-clock Europe/Madrid; the day key is the UTC date of that instant,
        // so an 00:18 charge keys to the previous day. Correct, not a bug.
        static func parseMadrid(_ raw: String?) -> Date? {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            let text = raw.replacingOccurrences(of: "T", with: " ")
            return madridWithSeconds.date(from: text) ?? madridNoSeconds.date(from: text)
        }

        static func dayKey(_ date: Date) -> String { utcDay.string(from: date) }

        // Revolut English exports use US formatting ("1,234.56"); EU "1.234,56" is rejected
        // like the web spec does, so an ambiguous file can't import with the wrong magnitude.
        static func normalizeAmount(_ raw: String?) -> String? {
            guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            let hasComma = s.contains(","), hasDot = s.contains(".")
            if hasComma && hasDot {
                guard let lastDot = s.lastIndex(of: "."), let lastComma = s.lastIndex(of: ","),
                      lastDot > lastComma,
                      s.wholeMatch(of: /-?\d{1,3}(,\d{3})+\.\d+/) != nil else { return nil }
                s.removeAll { $0 == "," }
            } else if hasComma {
                if s.wholeMatch(of: /-?\d{1,3}(,\d{3})+/) != nil {
                    s.removeAll { $0 == "," }
                } else if s.wholeMatch(of: /-?\d+,\d{1,2}/) != nil {
                    s = s.replacingOccurrences(of: ",", with: ".")
                } else {
                    return nil
                }
            }
            guard s.wholeMatch(of: /-?\d+(\.\d+)?/) != nil else { return nil }
            return s
        }

        // Minimal RFC 4180: quoted fields, doubled quotes, CRLF or LF. Enough for Revolut.
        static func splitRecords(_ text: String) -> [[String]] {
            var records: [[String]] = []
            var fields: [String] = []
            var current = ""
            var inQuotes = false
            let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if inQuotes {
                    if c == "\"" {
                        if i + 1 < chars.count, chars[i + 1] == "\"" { current.append("\""); i += 1 }
                        else { inQuotes = false }
                    } else {
                        current.append(c)
                    }
                } else if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current); current = ""
                } else if c == "\n" || c == "\r" || c == "\r\n" {
                    fields.append(current); current = ""
                    records.append(fields); fields = []
                } else {
                    current.append(c)
                }
                i += 1
            }
            if !current.isEmpty || !fields.isEmpty {
                fields.append(current)
                records.append(fields)
            }
            return records
        }

        private static let madridWithSeconds = makeFormatter("yyyy-MM-dd HH:mm:ss", tz: "Europe/Madrid")
        private static let madridNoSeconds = makeFormatter("yyyy-MM-dd HH:mm", tz: "Europe/Madrid")
        private static let utcDay = makeFormatter("yyyy-MM-dd", tz: "UTC")

        private static func makeFormatter(_ format: String, tz: String) -> DateFormatter {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: tz)
            f.dateFormat = format
            return f
        }
    }
}
