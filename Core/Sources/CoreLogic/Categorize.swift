import Foundation
import SwiftData
import CoreModel

extension CoreLogic {
    public enum Categorize {
        public struct Result: Equatable, Sendable {
            public var updated: Int
            public var scanned: Int

            public init(updated: Int, scanned: Int) {
                self.updated = updated
                self.scanned = scanned
            }
        }

        public static func matches(rule: CategoryRule, tx: Transaction) -> Bool {
            let needle = rule.pattern
            if needle.isEmpty { return false }
            let haystack: String
            switch rule.field {
            case .counterparty: haystack = tx.counterparty ?? ""
            case .description:  haystack = tx.transactionDescription ?? ""
            }
            let h = haystack.lowercased()
            let n = needle.lowercased()
            switch rule.matchType {
            case .equals:     return h == n
            case .startsWith: return h.hasPrefix(n)
            case .endsWith:   return h.hasSuffix(n)
            case .contains:   return h.contains(n)
            case .regex:
                guard let re = try? NSRegularExpression(pattern: needle, options: [.caseInsensitive]) else {
                    return false
                }
                let range = NSRange(haystack.startIndex..., in: haystack)
                return re.firstMatch(in: haystack, options: [], range: range) != nil
            }
        }

        public struct Preview: Equatable, Sendable {
            public var count: Int
            public var sampleIds: [UUID]
        }

        // Ports the category-rules/preview route: how many transactions a (pattern, field,
        // matchType) would match, plus the most recent sample ids. Uses an unsaved rule.
        @MainActor
        public static func preview(
            pattern: String, field: RuleField = .description, matchType: RuleMatch = .contains,
            in ctx: ModelContext, sampleLimit: Int = 5
        ) throws -> Preview {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return Preview(count: 0, sampleIds: []) }
            let probe = CategoryRule(pattern: trimmed, field: field, matchType: matchType)
            let matched = try ctx.fetch(FetchDescriptor<Transaction>(
                sortBy: [SortDescriptor(\.bookedAt, order: .reverse)]
            )).filter { matches(rule: probe, tx: $0) }
            return Preview(count: matched.count, sampleIds: matched.prefix(sampleLimit).map(\.id))
        }

        // Tie-break on equal priorities: createdAt ASC (older rule wins).
        // The TS source orders only by priority DESC; with ties undefined.
        @MainActor
        @discardableResult
        public static func applyRulesToTransactions(
            in ctx: ModelContext,
            txIds: [UUID]? = nil
        ) throws -> Result {
            let rules = try ctx.fetch(FetchDescriptor<CategoryRule>(
                sortBy: [
                    SortDescriptor(\.priority, order: .reverse),
                    SortDescriptor(\.createdAt, order: .forward),
                ]
            ))
            if rules.isEmpty { return Result(updated: 0, scanned: 0) }

            let fetched: [Transaction]
            if let ids = txIds, !ids.isEmpty {
                let idSet = Set(ids)
                fetched = try ctx.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { idSet.contains($0.id) }
                ))
            } else {
                fetched = try ctx.fetch(FetchDescriptor<Transaction>())
            }
            let rows = fetched.filter { $0.categorySource != .manual }

            var updated = 0
            for tx in rows {
                var matched: CategoryRule?
                for rule in rules where matches(rule: rule, tx: tx) {
                    matched = rule
                    break
                }
                guard let rule = matched, let cat = rule.category else { continue }
                if tx.category?.id == cat.id, tx.categorySource == .rule { continue }
                tx.category = cat
                tx.categorySource = .rule
                updated += 1
            }
            if updated > 0 { try ctx.saveTouchingChanges() }
            return Result(updated: updated, scanned: rows.count)
        }
    }
}
