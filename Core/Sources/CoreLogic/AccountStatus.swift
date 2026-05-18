import Foundation
import CoreModel

extension CoreLogic {
    public enum AccountStatus {
        // `archived` = dead account, no reads/writes/pairing.
        // `excluded` = alive but off cash net worth (e.g. roommate's account).
        // Conflating these caused the 2026-05-16 mirror-nuke incident — keep separate.
        public static func isUsableForTransfers(_ account: Account?) -> Bool {
            guard let a = account else { return false }
            return !a.archived
        }

        public static func isCountedInCashNetWorth(_ account: Account?) -> Bool {
            guard let a = account else { return false }
            return !a.archived && !a.excluded
        }
    }
}
