import SwiftUI
import SwiftData
import Combine

extension View {
    // Views that aggregate via a manual reload() (not @Query) don't refresh when the
    // store changes. Re-run their reload on every persisted save — local edits and
    // sync-applied pulls alike.
    func reloadOnModelChange(_ action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            action()
        }
    }
}
