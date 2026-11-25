import SwiftUI
import ArgumentKit

@main
struct MapMyArgumentApp: App {
    @State private var store = Screenshots.isActive ? Screenshots.store() : Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .map(let id): MapScreen(mapID: id)
                    case .build: BuildFlow()
                    case .rate: RateFlow()
                    case .compare: CompareView()
                    case .how: HowView()
                    }
                }
        }
        .onOpenURL { url in open(url) }
    }

    /// Links like https://mapmyargument.com/#m=MMA1.… (from the website) carry a share code.
    func open(_ url: URL) {
        guard let received = try? store.receive(url.absoluteString.replacingOccurrences(of: "#m=", with: " MMA1.")
            .replacingOccurrences(of: "MMA1.MMA1.", with: "MMA1.")) else { return }
        switch received {
        case .rate: store.path = [.rate]
        case .compare: store.path = [.compare]
        case .alreadyHave(let id): store.path = [.map(id)]
        }
    }
}
