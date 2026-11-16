import SwiftUI
import WidgetKit

/// The widgets extension: Home Screen and Lock Screen widgets for Track
/// timers, and the Live Activity for the Lock Screen and Dynamic Island.
@main
struct DoThisNowWidgets: WidgetBundle {
    var body: some Widget {
        TimerWidget()
        StartButtonsWidget()
        TimerLiveActivity()
    }
}
