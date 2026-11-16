import Foundation
import CoreLocation
import UIKit
import DoThisNowKit

/// Watches the places that Track timers start and stop by, with the iPhone's
/// own region monitoring, so it works with the app closed. iOS relaunches the
/// app in the background when a place's edge is crossed; `AppDelegate` creates
/// this at launch so the event has somewhere to go.
@Observable
@MainActor
final class PlaceWatcher: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceWatcher()

    /// What iOS lets the app do with location.
    private(set) var status: CLAuthorizationStatus
    /// Precise location is off, which makes small places unreliable.
    private(set) var reducedAccuracy = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private weak var model: AppModel?
    /// Crossings that arrived before the model was attached.
    @ObservationIgnored private var waiting: [(String, PlaceCrossing, Date)] = []
    private static let prefix = "place-"

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
    }

    var isAlways: Bool { status == .authorizedAlways }
    var isOff: Bool { status == .denied || status == .restricted }

    func attach(_ model: AppModel) {
        self.model = model
        let pending = waiting
        waiting = []
        for (id, crossing, at) in pending {
            model.placeCrossed(id, crossing, at: at)
        }
        sync(model.state.placeTimers.watchedPlaces)
    }

    /// Asks for "Always", which watching places with the app closed needs.
    /// The first time, iOS offers "While Using" and later asks about Always on
    /// its own; after that, only the Settings app can change it.
    func requestAlways() {
        let key = "askedForAlwaysLocation"
        switch status {
        case .notDetermined:
            UserDefaults.standard.set(false, forKey: key)
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse where !UserDefaults.standard.bool(forKey: key):
            // iOS shows the "Change to Always Allow" question once.
            UserDefaults.standard.set(true, forKey: key)
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        default:
            openSettings()
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Watches exactly these places. iOS allows 20 per app.
    func sync(_ places: [WatchedPlace]) {
        guard !Screenshots.isActive, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let wanted = Dictionary(uniqueKeysWithValues: places.prefix(20).map { (Self.prefix + $0.id, $0) })
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.prefix) {
            guard let circle = region as? CLCircularRegion, let place = wanted[region.identifier],
                  circle.center.latitude == place.coordinate.latitude, circle.center.longitude == place.coordinate.longitude,
                  circle.radius == min(place.radius, manager.maximumRegionMonitoringDistance) else {
                manager.stopMonitoring(for: region)
                continue
            }
        }
        let watching = Set(manager.monitoredRegions.map(\.identifier))
        for (identifier, place) in wanted where !watching.contains(identifier) {
            let region = CLCircularRegion(center: place.coordinate.location,
                                          radius: min(place.radius, manager.maximumRegionMonitoringDistance),
                                          identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func crossed(_ region: CLRegion, _ crossing: PlaceCrossing) {
        guard region.identifier.hasPrefix(Self.prefix) else { return }
        let id = String(region.identifier.dropFirst(Self.prefix.count))
        let now = Date()
        if let model {
            model.placeCrossed(id, crossing, at: now)
        } else {
            waiting.append((id, crossing, now))
        }
    }

    // MARK: CLLocationManagerDelegate (delivered on the main thread, where the manager was made)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        MainActor.assumeIsolated {
            self.status = status
            self.reducedAccuracy = reduced
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        MainActor.assumeIsolated { crossed(region, .arrive) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        MainActor.assumeIsolated { crossed(region, .leave) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {}
}
