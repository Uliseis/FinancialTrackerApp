import Foundation
import CloudKit

public enum SyncZone {
    public static let zoneName = "FinancialTracker"

    public static var id: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public static func recordID(for uuid: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: uuid.uuidString, zoneID: id)
    }
}
