import SwiftUI
import MapKit
import DoThisNowKit

/// Apple Maps suggestions as you type a place or address.
@Observable
@MainActor
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Searches near the trip's other stops, so "pizza" finds pizza there.
    func focus(on coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return }
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.2, (lats.max()! - lats.min()!) * 2),
                                    longitudeDelta: max(0.2, (lons.max()! - lons.min()!) * 2))
        completer.region = MKCoordinateRegion(center: coordinates.count == 1 ? first.location : center, span: span)
    }

    /// The place's name, address and position.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (name: String, address: String, coordinate: Coordinate)? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { return nil }
        let placemark = item.placemark
        // "111 S Michigan Ave, Chicago"
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, placemark.locality ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return (item.name ?? completion.title, address.isEmpty ? completion.subtitle : address, Coordinate(placemark.coordinate))
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
