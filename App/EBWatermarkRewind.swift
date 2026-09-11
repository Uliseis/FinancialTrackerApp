#if DEBUG
import Foundation
import SwiftData
import CoreModel
import CoreLogic

// One-shot: OFEB_REWIND="Abanca=2026-07-20" moves that connection's sync watermark back so
// the next foreground sync re-fetches from there (minus the 7-day overlap). Needed once:
// before the watermark-hold fix, two partial runs (3 and 22 Aug 2026) advanced lastSyncAt
// while the savings account timed out, so its 28 Jul → 15 Aug window was never fetched.
// Re-fetching is safe — EBSync skips (account, externalId) pairs it already holds.
enum EBWatermarkRewind {
    @MainActor
    static func runIfRequested(_ container: ModelContainer) {
        guard let spec = ProcessInfo.processInfo.environment["OFEB_REWIND"],
              let eq = spec.firstIndex(of: "=") else { return }
        let institution = String(spec[..<eq])
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        guard let date = iso.date(from: String(spec[spec.index(after: eq)...])) else {
            print("[EBRewind] bad date in \(spec)"); return
        }
        let ctx = container.mainContext
        guard let connection = (try? ctx.fetch(FetchDescriptor<Connection>()))?
            .first(where: { $0.institutionName == institution }) else {
            print("[EBRewind] no connection named \(institution)"); return
        }
        guard let current = connection.lastSyncAt, current > date else {
            print("[EBRewind] \(institution) watermark already at or before \(date)"); return
        }
        connection.lastSyncAt = date
        connection.updatedAt = .now
        do { try ctx.save(); print("[EBRewind] \(institution) lastSyncAt \(current) → \(date)") }
        catch { print("[EBRewind] save failed: \(error)") }
    }
}
#endif
