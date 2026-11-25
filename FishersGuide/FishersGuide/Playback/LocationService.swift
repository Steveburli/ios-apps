import CoreLocation
import Foundation
import GuideKit
import Observation

/// Wraps Core Location for driving: best accuracy, automotive activity, and updates that
/// keep coming with the screen off while a tour is running.
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isRunning = false
    private(set) var lastLocation: CLLocation?

    /// Every usable fix, on the main actor.
    var onFix: ((Fix) -> Void)?

    private let manager = CLLocationManager()
    /// Keeps When-In-Use updates alive in the background (iOS 17+), with the blue pill showing.
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard !isRunning else { return }
        if authorization == .notDetermined { requestPermission() }
        isRunning = true
        if Self.hasBackgroundLocationMode {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
        if Self.hasBackgroundLocationMode {
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    /// Setting allowsBackgroundLocationUpdates without the background mode crashes, so check.
    static let hasBackgroundLocationMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("location")
    }()

    fileprivate func handle(_ location: CLLocation) {
        // Skip stale or very rough fixes; a cell-tower fix can be a mile off.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        lastLocation = location
        let course: Double? = location.course >= 0 && location.courseAccuracy >= 0 && location.courseAccuracy <= 45
            ? location.course : nil
        let fix = Fix(point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
                      course: course, speed: max(0, location.speed), time: location.timestamp)
        onFix?(fix)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.handle(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient (no fix yet); Core Location keeps trying.
    }
}
