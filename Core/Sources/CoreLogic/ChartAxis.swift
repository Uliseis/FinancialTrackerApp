import Foundation

extension CoreLogic {
    public enum ChartAxis {
        // Up to `count` axis ticks drawn from real data dates, spread evenly in TIME. Picking
        // every nth point instead bunches ticks wherever readings cluster, and their labels
        // collide. For each evenly spaced target the nearest real date is taken, and one
        // closer than half a slot to the previous pick is dropped.
        public static func ticks(_ dates: [Date], count: Int) -> [Date] {
            let sorted = dates.sorted()
            guard let first = sorted.first, let last = sorted.last else { return [] }
            let span = last.timeIntervalSince(first)
            guard count > 1, span > 0 else { return [first] }

            let slot = span / Double(count - 1)
            var picked: [Date] = []
            for i in 0..<count {
                let target = first.addingTimeInterval(slot * Double(i))
                let nearest = sorted.min {
                    abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target))
                }!
                if let previous = picked.last, nearest.timeIntervalSince(previous) < slot / 2 {
                    continue
                }
                picked.append(nearest)
            }
            return picked
        }
    }
}
