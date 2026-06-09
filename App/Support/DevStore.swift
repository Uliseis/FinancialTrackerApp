#if DEBUG
import Foundation

// Dev-only: route the app's store at the imported real-data store in DevData/ (gitignored).
// Path is derived from this source file so it survives the repo moving. Simulator can read
// host filesystem paths; a physical device can't (no device in play this slice).
enum DevStore {
    static var url: URL? {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()   // App/Support
            .deletingLastPathComponent()   // App
            .deletingLastPathComponent()   // <repo>
        let store = repoRoot.appending(path: "DevData/financial.store")
        return FileManager.default.fileExists(atPath: store.path) ? store : nil
    }
}
#endif
