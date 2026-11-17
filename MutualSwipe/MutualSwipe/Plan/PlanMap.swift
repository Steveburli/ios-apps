import SwiftUI
import MapKit
import MutualKit

/// A map with a numbered pin for each stop, framed to fit them all. Stops
/// saved without a location (like the ready-made nights) are looked up on
/// this phone the first time the map shows.
struct PlanMap: View {
    let plan: Itinerary
    /// The card's map is a picture; the details map can be moved around.
    var interactive = false
    /// Look up stops saved without a location. The editor turns this off and
    /// shows only stops already found, so typing doesn't start searches.
    var autoLocate = true

    @State private var located: Itinerary?
    @State private var position: MapCameraPosition = .automatic

    private struct Pin: Identifiable {
        let id: String
        let number: Int
        let title: String
        let coordinate: CLLocationCoordinate2D
    }

    private var pins: [Pin] {
        let source = located ?? plan
        return source.stops.enumerated().compactMap { index, stop in
            guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
            return Pin(id: stop.id, number: index + 1, title: stop.place.isEmpty ? stop.what : stop.place,
                       coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some View {
        let pins = self.pins
        ZStack {
            if pins.isEmpty {
                Rectangle().fill(Color.black.opacity(0.12))
                    .overlay(Image(systemName: "map").font(.title2).foregroundStyle(Color.white.opacity(0.55)))
            } else {
                Map(position: $position, interactionModes: interactive ? .all : []) {
                    ForEach(pins) { pin in
                        Annotation(pin.title, coordinate: pin.coordinate, anchor: .center) {
                            StopNumber(number: pin.number)
                        }
                        .annotationTitles(interactive ? .automatic : .hidden)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .allowsHitTesting(interactive)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Map of \(plan.stops.count) stops")
        .task(id: plan) {
            located = nil
            position = Self.frame(pins)
            guard autoLocate, plan.stops.contains(where: { !$0.hasLocation && !$0.place.isEmpty }) else { return }
            let found = await PlaceFinder.locate(plan)
            located = found
            position = Self.frame(self.pins)
        }
    }

    /// A region that shows every pin with some room around them.
    private static func frame(_ pins: [Pin]) -> MapCameraPosition {
        guard let first = pins.first else { return .automatic }
        var minLat = first.coordinate.latitude, maxLat = minLat
        var minLon = first.coordinate.longitude, maxLon = minLon
        for pin in pins {
            minLat = min(minLat, pin.coordinate.latitude)
            maxLat = max(maxLat, pin.coordinate.latitude)
            minLon = min(minLon, pin.coordinate.longitude)
            maxLon = max(maxLon, pin.coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.008, (maxLat - minLat) * 1.8),
                                    longitudeDelta: max(0.008, (maxLon - minLon) * 1.8))
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// The numbered circle used on the map and in the list of stops.
struct StopNumber: View {
    let number: Int
    var size: CGFloat = 24

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.55, weight: .heavy).monospacedDigit())
            .foregroundStyle(Theme.accentInk)
            .frame(width: size, height: size)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
