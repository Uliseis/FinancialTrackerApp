import Foundation
import SwiftData

// Models carrying a last-modified clock for LWW sync.
public protocol Touchable: AnyObject {
    var updatedAt: Date { get set }
}

extension Account: Touchable {}
extension CoreModel.Category: Touchable {}
extension Transaction: Touchable {}
extension CategoryRule: Touchable {}
extension TransferGroup: Touchable {}
extension Connection: Touchable {}
extension AccountGroup: Touchable {}
extension AccountSpace: Touchable {}
extension Budget: Touchable {}
extension TransferRoute: Touchable {}
extension SharedExpenseGroup: Touchable {}
extension PortfolioValuation: Touchable {}
// FxRate (write-once, clock == createdAt), SyncRun, SyncRecordMeta intentionally excluded.

public extension ModelContext {
    // Stamp every changed Touchable's updatedAt, then save. Plain pre-save code (NOT the
    // willSave notification), so it's predictable and can't under-bump within a save. Use
    // for UI mutations; the sync pull path uses plain save() so remote clocks are kept.
    func saveTouchingChanges(now: Date = .now) throws {
        for case let touchable as any Touchable in insertedModelsArray + changedModelsArray {
            touchable.updatedAt = now
        }
        try save()
    }
}
