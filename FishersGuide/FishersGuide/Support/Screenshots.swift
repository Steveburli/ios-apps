import Foundation
import GuideKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph each screen
/// with sample data: welcome, map, playing, stops, stop or settings. Nothing here runs in
/// normal use, and it never plays sound or asks for location.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    /// A model with throwaway storage and a pretend drive north past Conner Prairie.
    @MainActor
    static func makeModel() -> GuideModel? {
        guard let screen else { return nil }
        let suite = "screenshots"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = GuideModel(defaults: defaults)
        model.hasOnboarded = screen != "welcome"

        guard screen != "welcome" else { return model }
        // Northbound on Allisonville Road, about 600 m south of Conner Prairie.
        let fix = Fix(point: GeoPoint(lat: 39.9792, lon: -86.0262), course: 5, speed: 20, time: Date())
        switch screen {
        case "map":
            model.stageForScreenshots(at: fix, heard: ["fishers-welcome", "fishers-municipal"], nowPlaying: nil)
        case "stop":
            model.stageForScreenshots(at: fix, heard: ["fishers-welcome", "fishers-municipal"], nowPlaying: nil)
            model.selectedStopID = "conner-prairie"
        default:
            model.stageForScreenshots(at: fix, heard: ["fishers-welcome", "fishers-municipal"], nowPlaying: "conner-prairie")
        }
        return model
    }
}
