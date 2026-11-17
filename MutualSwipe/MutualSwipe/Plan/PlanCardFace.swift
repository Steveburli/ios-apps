import SwiftUI
import MutualKit

/// The front of an itinerary card in the swipe stack: photos to swipe through
/// on top, a small map of the stops, then the stops with their times. Only
/// the photo area pages sideways; dragging anywhere else votes as usual.
struct PlanCardContent: View {
    let card: Card
    let plan: Itinerary
    let kind: DeckKind

    private var hasPlaces: Bool {
        plan.stops.contains { !$0.place.isEmpty || $0.hasLocation }
    }

    var body: some View {
        GeometryReader { box in
            let height = box.size.height
            let photos = !plan.photos.isEmpty
            let showsMap = hasPlaces
            let topHeight = height * (photos ? (showsMap ? 0.44 : 0.56) : (showsMap ? 0.4 : 0.3))
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if photos {
                        PlanPhotoPager(photos: plan.photos, barsInset: 16)
                    } else if showsMap {
                        PlanMap(plan: plan)
                    } else {
                        RadialGradient(colors: [Color.white.opacity(0.17), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
                    }
                    LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.25),
                                           .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.8), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    header
                        .allowsHitTesting(false)
                }
                .frame(width: box.size.width, height: topHeight)
                .clipped()

                if photos && showsMap {
                    PlanMap(plan: plan)
                        .frame(height: height * 0.19)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }
                }

                stopList
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Theme.cardColor(card.id))
        .foregroundStyle(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("PLAN · \(plan.stops.count) \(plan.stops.count == 1 ? "STOP" : "STOPS")", systemImage: "map.fill")
                Spacer()
                if plan.photos.count > 1 {
                    Label("Swipe photos", systemImage: "hand.draw")
                }
            }
            .font(.caption2.weight(.bold))
            .tracking(1)
            .opacity(0.9)
            .padding(.top, 20)
            Spacer(minLength: 0)
            Text(card.title)
                .font(.system(size: 28, weight: .heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .shadow(color: .black.opacity(0.3), radius: 3)
            if !card.subtitle.isEmpty {
                Text(card.subtitle).font(.subheadline.weight(.semibold)).opacity(0.95).lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var stopList: some View {
        VStack(alignment: .leading, spacing: 8) {
            let shown = plan.stops.count > 4 ? 3 : plan.stops.count
            ForEach(Array(plan.stops.prefix(shown).enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: 10) {
                    StopNumber(number: index + 1, size: 22)
                    if !stop.time.isEmpty {
                        Text(stop.time)
                            .font(.subheadline.weight(.heavy).monospacedDigit())
                            .frame(minWidth: 72, alignment: .leading)
                    }
                    Text(stop.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .opacity(0.95)
                }
            }
            if plan.stops.count > shown {
                Text("+ \(plan.stops.count - shown) more")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.8)
                    .padding(.leading, 32)
            }
            if plan.stops.isEmpty, !card.details.isEmpty {
                Text(card.details).font(.subheadline).lineLimit(4).opacity(0.94)
            }
            Spacer(minLength: 0)
            Text("Tap for the whole plan").font(.caption.weight(.semibold)).opacity(0.72)
        }
    }
}
