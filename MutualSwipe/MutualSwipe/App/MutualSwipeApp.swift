import SwiftUI
import UIKit
import CloudKit
import MutualKit

@main
struct MutualSwipeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CloudStore.shared
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(session)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent pushes tell the sync engines when someone else changes a shared deck.
        // CKSyncEngine handles them itself; the app only has to register.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Receives iCloud invitations: tapping a share link opens the app here.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            await CloudStore.shared.accept(metadata)
        }
    }
}

struct RootView: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    private let poll = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $session.path) {
            HomeView()
                .navigationDestination(for: String.self) { deckID in
                    DeckView(deckID: deckID)
                }
        }
        .tint(Theme.accent)
        .sheet(item: $session.sheet) { sheet in
            Group {
                switch sheet {
                case .player(let groupID): PlayerSheet(groupID: groupID)
                case .groups: GroupsSheet()
                case .newDeck: NewDeckSheet()
                case .card(let id): CardSheet(cardID: id)
                }
            }
            .environment(store)
            .environment(session)
        }
        .overlay(alignment: .bottom) {
            if let toast = session.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.toast)
        .onChange(of: store.notice) { _, notice in
            if let notice {
                session.show(notice)
                store.notice = nil
            }
        }
        .onChange(of: store.joinedGroupID) { _, id in
            guard let id else { return }
            session.currentGroupID = id
            session.path = []
            session.sheet = nil
            session.show("You joined “\(store.groups[id]?.name ?? "the group")”")
            store.joinedGroupID = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.refresh() }
            } else if phase == .background {
                store.writeNow()
            }
        }
        .onReceive(poll) { _ in
            if scenePhase == .active { Task { await store.refresh() } }
        }
    }
}

private struct ToastView: View {
    @Environment(Session.self) private var session
    let toast: Session.Toast

    var body: some View {
        Text(toast.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.bg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .task(id: toast.id) {
                UIAccessibility.post(notification: .announcement, argument: toast.message)
                try? await Task.sleep(for: .seconds(2.8))
                if session.toast?.id == toast.id { session.toast = nil }
            }
    }
}
