import SwiftUI

/// A small "i" button that shows what the timeline's colors mean in a pop-up
/// over the timeline. The legend is always hidden until you tap it, so the
/// Day tab gives its room to the timeline.
struct LegendButton: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false
    var size: CGFloat = 40

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle").frame(width: size, height: size)
        }
        .accessibilityLabel("Color key")
        .accessibilityHint("Shows what each color on the timeline means")
        .popover(isPresented: $showing, arrowEdge: .top) {
            DayLegend(autoFill: model.state.settings.autoFill)
                .padding(16)
                .frame(width: 290)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// What each kind of block on the timeline looks like.
struct DayLegend: View {
    let autoFill: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the colors mean")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            LegendItem(text: "Work: a rock, can’t move") { RoundedRectangle(cornerRadius: 4).fill(Theme.rock) }
            LegendItem(text: "Your blocks: hold and drag, they bump each other") { RoundedRectangle(cornerRadius: 5).fill(Theme.block) }
            LegendItem(text: autoFill ? "Suggestions: soft, they flow around" : "Suggestions: off") {
                RoundedRectangle(cornerRadius: 7).fill(Theme.soft)
            }
            LegendItem(text: "Events: drag the solid part to pick when you arrive") { RoundedRectangle(cornerRadius: 4).fill(Theme.core) }
            LegendItem(text: "Jelly: extra time at the event, squeezable") {
                RoundedRectangle(cornerRadius: 4).fill(Theme.jelly).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.jellyLine, lineWidth: 1.5))
            }
            LegendItem(text: "Sleep: moves, but complains") { RoundedRectangle(cornerRadius: 4).fill(Theme.sleep) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LegendItem<Swatch: View>: View {
    let text: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            swatch.frame(width: 14, height: 14).padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
