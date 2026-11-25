import GuideKit
import SwiftUI

/// Every stop, nearest first when we know where you are, with what you've heard.
struct StopsListView: View {
    @Environment(GuideModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var detail: Stop?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedStops) { stop in
                        Button {
                            detail = stop
                        } label: {
                            StopRow(stop: stop, heard: model.hasHeard(stop.id), distance: model.distance(to: stop))
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Stories play on their own when you drive near a stop. Tap one to hear it now.")
                }
            }
            .navigationTitle("Stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $detail) { stop in
                StopDetailView(stop: stop, embedded: true)
            }
        }
    }

    private var sortedStops: [Stop] {
        let stops = model.tour.stops
        guard model.lastFix != nil else {
            return stops.sorted { ($0.kind == .area ? 1 : 0, $0.title) < ($1.kind == .area ? 1 : 0, $1.title) }
        }
        return stops.sorted { (model.distance(to: $0) ?? 0) < (model.distance(to: $1) ?? 0) }
    }
}

struct StopRow: View {
    var stop: Stop
    var heard: Bool
    var distance: Double?

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: stop.category, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.title)
                    .font(.body.weight(.semibold))
                Text(stop.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let distance {
                    Text(Format.distance(distance))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if heard {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Heard")
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
