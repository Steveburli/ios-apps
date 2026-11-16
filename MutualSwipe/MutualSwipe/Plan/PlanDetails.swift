import SwiftUI
import MutualKit

/// The top of a plan's details: photos to swipe through, a map you can move,
/// and every stop with its time, note and directions.
struct PlanDetails: View {
    let card: Card
    let plan: Itinerary
    let kind: DeckKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if plan.photos.isEmpty {
                    Theme.cardColor(card.id)
                } else {
                    PhotoPager(photos: plan.photos, barsInset: 14)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(kind.label.uppercased()) · PLAN")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .opacity(0.85)
                    Text(card.title)
                        .font(Theme.display(28))
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle).font(.subheadline.weight(.semibold)).opacity(0.95)
                    }
                }
                .foregroundStyle(Color.white)
                .padding(18)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .frame(height: plan.photos.isEmpty ? 170 : 300)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if plan.stops.contains(where: { !$0.place.isEmpty || $0.hasLocation }) {
                PlanMap(plan: plan, interactive: true)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(stop, number: index + 1, last: index == plan.stops.count - 1)
                }
            }
        }
    }

    private func stopRow(_ stop: Itinerary.Stop, number: Int, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                StopNumber(number: number, size: 28)
                if !last {
                    Rectangle().fill(Theme.line).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if !stop.time.isEmpty {
                    Text(stop.time).font(.footnote.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.accent)
                }
                Text(stop.headline).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if !stop.address.isEmpty {
                    Text(stop.address).font(.footnote).foregroundStyle(Theme.muted)
                }
                if !stop.note.isEmpty {
                    Text(stop.note).font(.subheadline).foregroundStyle(Theme.ink)
                }
                HStack(spacing: 14) {
                    if let maps = directions(to: stop) {
                        Link(destination: maps) {
                            Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                        }
                    }
                    if let site = URL(string: stop.website), !stop.website.isEmpty {
                        Link(destination: site) {
                            Label(CardText.host(stop.website), systemImage: "safari")
                        }
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 2)
            }
            .padding(.bottom, last ? 0 : 16)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    /// Opens Apple Maps on the stop.
    private func directions(to stop: Itinerary.Stop) -> URL? {
        guard !stop.place.isEmpty || stop.hasLocation else { return nil }
        var parts = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "q", value: stop.searchText(area: plan.area))]
        if let lat = stop.latitude, let lon = stop.longitude {
            items.append(URLQueryItem(name: "ll", value: "\(lat),\(lon)"))
        }
        parts?.queryItems = items
        return parts?.url
    }
}
