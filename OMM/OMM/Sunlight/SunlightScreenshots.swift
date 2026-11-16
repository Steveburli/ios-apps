import Foundation
import OMMKit

extension Screenshots {
    /// A week of sunlight: most days met, today partway with the timer running
    /// on the "sunlight" screen (it opens the Back inside sheet).
    static func sampleSunlight(now: Date = Date()) -> SunlightLog {
        var log = SunlightLog(goalMinutes: SunlightLog.defaultGoal, remindersOn: true)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let past: [(Int, Int, SunlightKind)] = [(6, 35, .openSky), (5, 20, .openSky), (4, 40, .openSky),
                                                (3, 30, .openSky), (2, 60, .shade), (1, 45, .openSky)]
        for (back, minutes, kind) in past {
            if let day = calendar.date(byAdding: .day, value: -back, to: today),
               let noon = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: day) {
                log.add(minutes: minutes, kind: kind, endingAt: noon)
            }
        }
        log.add(minutes: 12, kind: .openSky, endingAt: now.addingTimeInterval(-3 * 3600))
        if screen == "sunlight" {
            log.startOutside(at: now.addingTimeInterval(-9 * 60))
        }
        return log
    }
}
