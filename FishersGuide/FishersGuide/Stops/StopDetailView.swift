import GuideKit
import MapKit
import SwiftUI

/// Everything about one stop: the full story text, play it now, and directions.
struct StopDetailView: View {
    @Environment(GuideModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var stop: Stop
    /// Pushed inside the stops list rather than shown as its own sheet.
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: stop.coordinate,
                    latitudinalMeters: max(1200, stop.radius * 4),
                    longitudinalMeters: max(1200, stop.radius * 4)))) {
                    Annotation(stop.title, coordinate: stop.coordinate) {
                        CategoryBadge(category: stop.category, size: 36)
                    }
                    .annotationTitles(.hidden)
                    if stop.kind == .poi {
                        MapCircle(center: stop.coordinate, radius: stop.radius)
                            .foregroundStyle(stop.category.color.opacity(0.12))
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)

                HStack(spacing: 8) {
                    Label(stop.category.title, systemImage: stop.category.symbol)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(stop.category.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(stop.category.color)
                    if model.hasHeard(stop.id) {
                        Label("Heard", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    if let d = model.distance(to: stop) {
                        Text("\(Format.distance(d)) away")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.title)
                        .font(.title.weight(.bold))
                    if !stop.subtitle.isEmpty {
                        Text(stop.subtitle)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.playStory(stop)
                    dismiss()
                } label: {
                    Label(isPlayingThis ? "Playing now" : "Play the Story", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPlayingThis)

                Text(stop.narration)
                    .font(.body)
                    .lineSpacing(3)

                if let address = stop.address {
                    Label(address, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if stop.kind == .poi {
                        Button {
                            openDirections()
                        } label: {
                            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let site = stop.website, let url = URL(string: site) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Website", systemImage: "safari")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(stop.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isPlayingThis: Bool {
        model.narrator.current?.stopID == stop.id && !(model.narrator.current?.isTeaser ?? true)
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
