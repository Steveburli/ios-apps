import CoreLocation
import GuideKit
import SwiftUI

extension StopCategory {
    var color: Color {
        switch self {
        case .history: Color(red: 0.70, green: 0.36, blue: 0.16)
        case .nature: Color(red: 0.18, green: 0.55, blue: 0.30)
        case .arts: Color(red: 0.55, green: 0.27, blue: 0.68)
        case .entertainment: Color(red: 0.85, green: 0.25, blue: 0.40)
        case .landmark: Color(red: 0.12, green: 0.45, blue: 0.75)
        case .area: Color(red: 0.40, green: 0.45, blue: 0.50)
        }
    }

    var symbol: String {
        switch self {
        case .history: "building.columns.fill"
        case .nature: "leaf.fill"
        case .arts: "theatermasks.fill"
        case .entertainment: "music.note"
        case .landmark: "mappin.and.ellipse"
        case .area: "signpost.right.fill"
        }
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

extension Stop {
    var coordinate: CLLocationCoordinate2D { location.coordinate }
}

enum Format {
    /// "0.4 mi" or "850 ft".
    static func distance(_ meters: Double) -> String {
        let miles = meters / 1609.344
        if miles < 0.1 { return "\(Int((meters * 3.28084 / 50).rounded()) * 50) ft" }
        return miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
    }
}

/// The round category badge used on pins and in lists.
struct CategoryBadge: View {
    var category: StopCategory
    var size: CGFloat = 34
    var dimmed = false

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(dimmed ? Color.gray : category.color))
            .overlay(Circle().stroke(.white, lineWidth: size > 30 ? 2 : 1.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}
