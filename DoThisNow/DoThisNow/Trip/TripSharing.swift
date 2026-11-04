import UIKit
import CloudKit
import CoreLocation

/// Shows Apple's iCloud sharing screen, where the trip's owner invites people
/// through Messages, Mail or a link, and manages who's in.
@MainActor
enum TripSharing {
    private static var delegate: SharingDelegate?

    static func present(share: CKShare, container: CKContainer, title: String) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        let delegate = SharingDelegate(title: title)
        controller.delegate = delegate
        self.delegate = delegate
        controller.modalPresentationStyle = .formSheet
        top.present(controller, animated: true)
    }
}

private final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    let title: String

    init(title: String) {
        self.title = title
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        title
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        Task { @MainActor in
            TripStore.shared.notice = "Sharing didn’t save: \(error.localizedDescription)"
        }
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        Task { @MainActor in await TripStore.shared.refresh() }
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        Task { @MainActor in await TripStore.shared.refresh() }
    }
}

/// Finds where you are once, for "We're off schedule".
@MainActor
final class HereFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Nil when location is off or takes too long.
    func locate() async -> CLLocationCoordinate2D? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
            Task {
                try? await Task.sleep(for: .seconds(8))
                self.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let all = waiting
        waiting = []
        for continuation in all { continuation.resume(returning: coordinate) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if !self.waiting.isEmpty { manager.requestLocation() }
            case .denied, .restricted:
                self.finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
