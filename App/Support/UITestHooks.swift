#if DEBUG
import Foundation

// DEBUG-only screenshot affordance: launch with UITEST_PRESENT=<name> to auto-open a
// management sheet for capture, since CLI automation can't tap. Parallel to UITEST_TAB.
enum UITestHooks {
    static var presentSheet: String? {
        ProcessInfo.processInfo.environment["UITEST_PRESENT"]
    }
}
#endif
