import Foundation

/// The cloud build launches the app with `-screenshots <screen>` to photograph
/// each screen with the example tasks: now, pick, doing, tasks, day, inbox,
/// track or wake.
/// Nothing here runs in normal use.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool {
        screen != nil
    }
}
