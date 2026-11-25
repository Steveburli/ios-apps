import SwiftUI

@main
struct FishersGuideApp: App {
    @State private var model = Screenshots.makeModel() ?? GuideModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
