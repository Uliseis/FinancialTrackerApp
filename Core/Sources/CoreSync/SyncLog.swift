import Foundation
import os

// Sync diagnostics. Prefixed so it greps cleanly out of the device console
// (`devicectl … process launch --console`), and mirrored to the unified log.
// DEBUG-only: production sync should surface state through the UI, not stdout.
enum SyncLog {
    private static let logger = Logger(subsystem: "com.uliseis.odysseyfinance", category: "sync")

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let line = message()
        print("OFSYNC: \(line)")
        logger.debug("\(line, privacy: .public)")
        #endif
    }
}
