import SwiftUI
import OMMKit

/// Asks what kind of light it was, after "Back inside" or to add time by hand.
/// The minutes start at the timer's count and can be changed, in case the
/// timer ran on after coming in.
struct SunlightLogSheet: View {
    let mode: SunlightModel.Sheet
    @Environment(SunlightModel.self) private var sunlight
    @State private var minutes = 15
    @State private var kind: SunlightKind = .openSky

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $minutes, in: 1...SunlightLog.maxEntryMinutes, step: minutes < 10 ? 1 : 5) {
                        Text("\(minutes) min")
                            .font(.headline.monospacedDigit())
                    }
                } header: {
                    Text(mode == .finish ? "Time outside" : "How long were you outside?")
                }
                Section {
                    ForEach(SunlightKind.allCases, id: \.self) { option in
                        Button {
                            kind = option
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: kind == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(kind == option ? SunlightCard.sun : Theme.muted)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.text)
                                    Text(option.detail)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(kind == option ? .isSelected : [])
                    }
                } header: {
                    Text("What kind of light was it?")
                } footer: {
                    Text("Counts as \(credited) min toward today's goal.")
                }
                if mode == .finish {
                    Section {
                        Button("Don't log this", role: .destructive) { sunlight.discardTimer() }
                    }
                }
            }
            .navigationTitle(mode == .finish ? "Back inside" : "Add time outside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .finish ? "Still outside" : "Cancel") { sunlight.sheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        if mode == .finish {
                            sunlight.finish(kind: kind, minutes: minutes)
                        } else {
                            sunlight.add(minutes: minutes, kind: kind)
                        }
                    }
                    .bold()
                }
            }
        }
        .onAppear {
            if mode == .finish {
                minutes = max(1, sunlight.log.elapsedMinutes(now: Date()))
            }
        }
    }

    private var credited: Int {
        SunlightEntry(start: Date(), minutes: minutes, kind: kind).creditedMinutes
    }
}
