import Foundation
import CoreLogic

// When the budgeting month starts. Per device, like the other app preferences; income and
// expense figures are derived from booking dates, so a change recalculates every month.
enum CycleSettings {
    static let startDayKey = "dashboard.cycleStartDay"
    static let startsEarlyOnWeekendsKey = "dashboard.cycleStartsEarlyOnWeekends"

    static var current: CoreLogic.Dashboard.Cycle {
        let d = UserDefaults.standard
        let day = d.integer(forKey: startDayKey)
        return .init(startDay: day == 0 ? 1 : day,
                     startsEarlyOnWeekends: d.object(forKey: startsEarlyOnWeekendsKey) as? Bool ?? true)
    }
}
