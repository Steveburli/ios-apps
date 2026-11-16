import Foundation
import CoreLocation
import MapKit
import MutualKit

/// Finds real places near the phone with Apple Maps, to fill in where the
/// ready-made Indianapolis list runs short. Nothing leaves Apple's services,
/// and the location is used only for the search.
@MainActor
enum NearbyPlaces {
    /// Downtown Indianapolis. Within `indyReach` of it, the Indy list applies.
    static let indy = CLLocation(latitude: 39.7684, longitude: -86.1581)
    static let indyReach: CLLocationDistance = 90_000

    /// Searches Maps for each category, skipping places already in the deck.
    /// Returns the new places, in category order.
    static func places(for categories: [Journey.Category], indyCounts: [String: Int], answers: Journey.Answers,
                       near location: CLLocation, skipping titles: Set<String>) async -> [Journey.Place] {
        var seen = Set(titles.map { $0.lowercased() })
        var found: [Journey.Place] = []
        for category in categories {
            let wanted = Journey.mapsWanted(for: category, indyCount: indyCounts[category.id] ?? 0)
            guard wanted > 0 else { continue }
            var added = 0
            for query in category.mapsQueries where added < wanted {
                for item in await search(query, near: location, radius: answers.distance.searchRadius) where added < wanted {
                    guard let name = item.name, seen.insert(name.lowercased()).inserted,
                          let draft = draft(for: item, category: category, from: location) else { continue }
                    let id = "maps-\(category.id)-\(found.count)"
                    found.append(Journey.Place(id: id, categoryID: category.id, source: .maps, draft: draft))
                    added += 1
                }
            }
        }
        return found
    }

    private static func search(_ query: String, near location: CLLocation, radius: CLLocationDistance) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.filter { item in
            location.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                               longitude: item.placemark.coordinate.longitude)) <= radius
        }
    }

    private static func draft(for item: MKMapItem, category: Journey.Category, from location: CLLocation) -> CardDraft? {
        guard let name = item.name else { return nil }
        let coordinate = item.placemark.coordinate
        let meters = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let miles = meters / 1609.34
        var facts: [String] = []
        if let area = item.placemark.subLocality ?? item.placemark.locality { facts.append(area) }
        facts.append(miles < 10 ? String(format: "%.1f mi away", miles) : "\(Int(miles.rounded())) mi away")
        facts.append(category.title)
        var details = "Found on Apple Maps near you."
        if let street = item.placemark.thoroughfare {
            let number = item.placemark.subThoroughfare.map { $0 + " " } ?? ""
            details += "\nAddress: " + number + street
        }
        let link: String
        if let url = item.url, !CardText.safeURL(url.absoluteString).isEmpty {
            link = CardText.safeURL(url.absoluteString)
        } else {
            var parts = URLComponents(string: "https://maps.apple.com/")!
            parts.queryItems = [URLQueryItem(name: "q", value: name),
                                URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)")]
            link = parts.url?.absoluteString ?? ""
        }
        return CardText.clean(CardDraft(title: name, subtitle: facts.joined(separator: " · "), details: details,
                                        link: link, tags: [category.title]))
    }
}

/// Asks for the phone's location once, politely: nil when it's turned off,
/// refused, or slow.
@MainActor
final class OneLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?

    var isRefused: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func current() async -> CLLocation? {
        guard !isRefused, waiting == nil else { return nil }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { continuation in
            waiting = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        waiting?.resume(returning: location)
        waiting = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waiting != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
