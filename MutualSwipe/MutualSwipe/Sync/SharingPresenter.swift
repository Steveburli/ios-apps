import UIKit
import CloudKit

/// Shows Apple's iCloud sharing screen, where the owner invites people
/// through Messages, Mail or a link, and manages who's in.
@MainActor
enum SharingPresenter {
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
            CloudStore.shared.notice = "Sharing didn’t save: \(error.localizedDescription)"
        }
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        Task { @MainActor in await CloudStore.shared.refresh() }
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        Task { @MainActor in await CloudStore.shared.refresh() }
    }
}
