import SwiftUI
import DoThisNowKit

/// One-of-several chips, for choices whose labels are too long for a
/// segmented control.
struct ChoiceChips<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        FlowLayout {
            ForEach(options, id: \.value) { option in
                Chip(title: option.label, isOn: selection == option.value) {
                    selection = option.value
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A minutes value with − and + in steps of five.
struct MinuteStepper: View {
    let title: String
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 5...1440
    var step = 5

    var body: some View {
        Stepper(value: $minutes, in: range, step: step) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(minutes) min")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityValue("\(minutes) minutes")
    }
}

/// A time-of-day picker bound to minutes after midnight.
struct MinuteOfDayPicker: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: binding, displayedComponents: .hourAndMinute)
    }

    private var binding: Binding<Date> {
        Binding(
            get: { model.today.date(atMinute: Double(minutes), calendar: model.calendar) },
            set: { minutes = Int(model.calendar.minuteOfDay($0)) }
        )
    }
}
