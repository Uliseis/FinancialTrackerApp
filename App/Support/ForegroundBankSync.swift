import Foundation
import SwiftData
import CoreLogic
import CoreIntegrations
import CoreSync

// Bank data used to refresh only from the Connections screen (a manual tap) or from the
// BGProcessingTask — and iOS runs processing tasks opportunistically, typically only while
// charging and idle, so in practice the app never refreshed itself. This pulls Enable
// Banking whenever the app comes to the foreground, throttled so opening the app twice in
// a row doesn't hammer the API.
enum ForegroundBankSync {
    static let minimumInterval: TimeInterval = 15 * 60
    private static let lastRunKey = "ForegroundBankSync.lastRunAt"

    private static var lastRun: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: lastRunKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastRunKey)
        }
    }

    static func isDue(now: Date = .now) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= minimumInterval
    }

    // Marks the attempt before awaiting so two rapid foregrounds can't both start a run.
    // ponytail: try? skips silently when the signing key can't be read (no connection set
    // up yet, or Keychain locked) — the next foreground retries.
    @MainActor
    static func runIfDue(_ ctx: ModelContext, engine: CloudKitSyncEngine?) async {
        guard isDue() else { return }
        lastRun = .now
        if let signer = try? EBKeychain().loadSigner() {
            _ = await CoreLogic.EBSync.syncAll(api: EBClient(tokenProvider: signer), in: ctx)
        }
        // Independent of Enable Banking: brokers and crypto have their own sources, and an
        // unconfigured bank connection shouldn't stop them refreshing.
        _ = await CoreLogic.InvestmentRefresh.run(in: ctx)
        // Rows inserted on the main context push via SaveObserver, but nudge the engine so
        // they leave the device on this run rather than the next save.
        await engine?.sendPendingChanges()
    }
}
