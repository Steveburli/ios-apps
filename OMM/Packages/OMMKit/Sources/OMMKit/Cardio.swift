/// The optional cardio block at the end of a workout. It never crosses
/// anything off the grid or changes the estimate.
public enum Cardio {
    public static let noEquipment = [
        "Brisk Walk (outside or marching in place)",
        "High Knees",
        "Step-Ups (on a stair, switching legs)",
        "Shadow Boxing",
        "Jump Rope (or the motion without a rope)",
    ]
    public static let gym = [
        "Treadmill Walk or Jog",
        "Stationary Bike",
        "Rowing Machine",
        "Elliptical",
        "Stair Climber",
    ]

    public static let minutesRange: ClosedRange<Int> = 3...30
    public static let minutesStep = 3
    public static let defaultMinutes = 9
    /// Sets always keep at least this much of the workout.
    public static let minimumSetMinutes = 6

    /// The longest cardio block that still leaves time for the sets.
    public static func maxMinutes(forDuration duration: Int) -> Int {
        max(minutesRange.lowerBound, min(minutesRange.upperBound, duration - minimumSetMinutes))
    }

    /// `minutes` pulled into range for a workout of `duration` minutes.
    public static func clamp(_ minutes: Int, forDuration duration: Int) -> Int {
        min(max(minutes, minutesRange.lowerBound), maxMinutes(forDuration: duration))
    }
}
