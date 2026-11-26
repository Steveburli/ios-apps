import SwiftUI
import MapKit
import CoreLocation
import LittlesKit

/// Activities that practice what each kid is working on right now.
struct WorkingOnCard: View {
    @EnvironmentObject var model: AppModel
    let kidIDs: [String]

    var body: some View {
        let kids = kidIDs.compactMap { model.kid($0) }
        let rows: [WorkingOnRow] = kids.flatMap { kid in
            MilestoneActivities.picks(ageMonths: kid.ageMonths(on: Date()), statuses: model.state.milestones[kid.id] ?? [:])
                .prefix(2).map { WorkingOnRow(kid: kid, pick: $0) }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("🎯 Working on").font(.headline)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            KidBadge(kid: row.kid, size: 20)
                            Text(row.pick.milestone.text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        }
                        HStack(spacing: 6) {
                            ForEach(row.pick.activities) { activity in
                                NavigationLink(value: activity.id) {
                                    Pill(text: "\(activity.emoji) \(activity.title)")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }
}

struct WorkingOnRow: Identifiable {
    var kid: Kid
    var pick: MilestoneActivities.Pick
    var id: String { kid.id + pick.id }
}

struct TimeRow: Identifiable {
    var kid: Kid
    var screen: [(day: String, minutes: Int)]
    var outside: [(day: String, minutes: Int)]
    var id: String { kid.id }
}

/// This week's screen time and outside time for each kid.
struct TimeTotalsCard: View {
    @EnvironmentObject var model: AppModel
    let kidIDs: [String]

    var body: some View {
        let today = Dates.key(Date())
        let kids = kidIDs.compactMap { model.kid($0) }
        let data = kids.map { kid in
            TimeRow(kid: kid, screen: TimeTotals.week(model.state.logs, kidID: kid.id, kind: .screen, today: today),
                    outside: TimeTotals.week(model.state.logs, kidID: kid.id, kind: .outside, today: today))
        }
        if data.contains(where: { row in row.screen.contains { $0.minutes > 0 } || row.outside.contains { $0.minutes > 0 } }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("📺 Screens vs 🌳 outside, last 7 days").font(.headline)
                ForEach(data) { item in
                    let screen = item.screen.reduce(0) { $0 + $1.minutes }
                    let outside = item.outside.reduce(0) { $0 + $1.minutes }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.kid.name).font(.subheadline.weight(.semibold))
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(0..<7, id: \.self) { index in
                                VStack(spacing: 2) {
                                    bar(item.outside[index].minutes, color: Theme.good)
                                    bar(item.screen[index].minutes, color: Theme.warn)
                                    Text(Dates.letterWeekdays[Dates.weekday(item.screen[index].day) - 1]).font(.caption2).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        Text("Screens \(Dates.duration(Double(screen) * 60)) (\(Dates.duration(Double(screen) * 60 / 7))/day) · outside \(Dates.duration(Double(outside) * 60))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Text("The AAP suggests no screens under 18 months except video chat, and about an hour a day of quality programs for ages 2 to 5.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
    }

    private func bar(_ minutes: Int, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(minutes > 0 ? color : Theme.sunk)
            .frame(height: max(3, min(48, CGFloat(minutes) / 3)))
    }
}

/// Finds the phone's location once.
final class LocationFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var denied = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func find() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: DispatchQueue.main.async { self.denied = true }
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        DispatchQueue.main.async { self.location = last }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Today's weather from Open-Meteo (free, no key).
struct Weather: Equatable {
    var temperature: Double
    var code: Int
    var high: Double
    var rainChance: Int

    var summary: String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorms"
        default: return "Mixed"
        }
    }

    var emoji: String {
        switch code {
        case 0: return "☀️"
        case 1, 2: return "⛅️"
        case 3, 45, 48: return "☁️"
        case 51...67, 80...82: return "🌧️"
        case 71...77, 85, 86: return "❄️"
        case 95...99: return "⛈️"
        default: return "🌤️"
        }
    }

    /// Whether it's a good day to play outside.
    var outsideDay: Bool {
        rainChance < 50 && temperature >= 40 && temperature <= 95 && !(51...99).contains(code)
    }

    static func fetch(latitude: Double, longitude: Double) async -> Weather? {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code&daily=temperature_2m_max,precipitation_probability_max&temperature_unit=fahrenheit&timezone=auto&forecast_days=1")
        guard let url, let result = try? await URLSession.shared.data(from: url) else { return nil }
        let data = result.0
        struct Response: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double
                var weather_code: Int
            }
            struct Daily: Decodable {
                var temperature_2m_max: [Double]
                var precipitation_probability_max: [Int?]
            }
            var current: Current
            var daily: Daily
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return Weather(temperature: response.current.temperature_2m, code: response.current.weather_code,
                       high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
                       rainChance: (response.daily.precipitation_probability_max.first ?? 0) ?? 0)
    }
}

struct NearbyPlace: Identifiable {
    var id: String
    var name: String
    var detail: String
    var distance: Double
    var item: MKMapItem
}

/// Parks, libraries, splash pads and more near the phone, with today's weather.
struct NearbyView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var finder = LocationFinder()
    @State private var category = NearbyView.categories[0]
    @State private var places: [NearbyPlace] = []
    @State private var weather: Weather?
    @State private var searching = false

    static let categories: [(emoji: String, title: String, query: String)] = [
        ("🛝", "Playgrounds", "playground"),
        ("📚", "Libraries", "public library"),
        ("💦", "Splash pads", "splash pad"),
        ("🏛️", "Museums", "children's museum"),
        ("🌳", "Parks", "park"),
        ("🤸", "Indoor play", "indoor playground"),
        ("🦒", "Zoos & farms", "zoo"),
        ("🍦", "Treats", "ice cream"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let weather {
                    HStack(spacing: 12) {
                        Text(weather.emoji).font(.system(size: 36))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.units.temperature(weather.temperature)) · \(weather.summary)").font(.headline)
                            Text("High \(model.units.temperature(weather.high)) · \(weather.rainChance)% chance of rain")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            Text(weather.outsideDay ? "Good day to get outside." : "Maybe an inside day: try the library or indoor play.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(weather.outsideDay ? Theme.good : Theme.warn)
                        }
                    }
                    .card()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NearbyView.categories, id: \.query) { item in
                            Button {
                                category = item
                                Task { await search() }
                            } label: {
                                Text("\(item.emoji) \(item.title)")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(item.query == category.query ? Color.white : Theme.ink)
                                    .background(item.query == category.query ? Theme.accent : Theme.surface, in: Capsule())
                                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if finder.denied {
                    EmptyNote(emoji: "📍", text: "Turn on location for Littles in Settings to find places nearby.").card()
                } else if searching {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if places.isEmpty {
                    EmptyNote(emoji: "🗺️", text: finder.location == nil ? "Finding where you are…" : "Nothing found nearby.").card()
                }
                ForEach(places) { place in
                    Button {
                        place.item.openInMaps()
                    } label: {
                        HStack(spacing: 12) {
                            Text(category.emoji).font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                                Text(place.detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(distance(place.distance)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Nearby")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { finder.find() }
        .onChange(of: finder.location) { _, location in
            guard let location else { return }
            Task {
                await search()
                weather = await Weather.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
        }
    }

    private func distance(_ meters: Double) -> String {
        model.units.isMetric ? String(format: "%.1f km", meters / 1000) : String(format: "%.1f mi", meters / 1609.34)
    }

    @MainActor
    private func search() async {
        guard let location = finder.location else { return }
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.query
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000)
        let response = try? await MKLocalSearch(request: request).start()
        places = (response?.mapItems ?? []).map { item in
            let itemLocation = item.placemark.location ?? location
            return NearbyPlace(id: "\(item.name ?? "")-\(item.placemark.coordinate.latitude)", name: item.name ?? "Place",
                         detail: item.placemark.title ?? "", distance: itemLocation.distance(from: location), item: item)
        }
        .sorted { $0.distance < $1.distance }
        searching = false
    }
}
