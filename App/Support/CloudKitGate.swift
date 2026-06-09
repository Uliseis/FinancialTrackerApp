import Foundation

// Sync runs only when the user has an iCloud account available — there is nothing to sync
// to otherwise, and CKContainer init traps in builds that aren't iCloud-entitled (unsigned
// dev builds, before a Developer team + CloudKit entitlement exist). ubiquityIdentityToken
// is non-nil exactly when both hold, so it is the single correct precondition for start().
enum CloudKitGate {
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
