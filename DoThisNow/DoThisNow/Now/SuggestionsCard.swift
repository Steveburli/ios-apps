import SwiftUI
import DoThisNowKit

/// Changes made in a shared Reminders list, such as "From my wife": a new
/// priority to keep, put back, or adjust, and notes to read.
struct SuggestionsCard: View {
    @Environment(AppModel.self) private var model
    let suggestions: [Suggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SUGGESTIONS")
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.accent)
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 { Divider().overlay(Theme.line) }
                SuggestionRow(suggestion: suggestion)
            }
        }
        .card()
    }
}

private struct SuggestionRow: View {
    @Environment(AppModel.self) private var model
    let suggestion: Suggestion

    var body: some View {
        let title = model.state.task(suggestion.taskID)?.title ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            switch suggestion.kind {
            case .priority:
                Text("Moved from \(Tier.name(suggestion.oldTier)) to \(Tier.name(suggestion.newTier ?? suggestion.oldTier)).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
            case .note:
                Text("“\(suggestion.text)”")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            (Text(suggestion.from) + Text(" · ") + Text(suggestion.at, format: .dateTime.month(.abbreviated).day().hour().minute()))
                .font(.caption)
                .foregroundStyle(Theme.ink3)
            FlowLayout {
                buttons
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        let id = suggestion.id
        switch suggestion.kind {
        case .priority:
            Button("Keep it") { model.approveSuggestion(id) }
                .buttonStyle(.dtn(.primary, size: .small))
            Button("Put it back") { model.denySuggestion(id) }
                .buttonStyle(.dtn(size: .small))
                .accessibilityHint("Back to \(Tier.name(suggestion.oldTier))")
            tierMenu("Pick another")
        case .note:
            Button("Got it") { model.approveSuggestion(id) }
                .buttonStyle(.dtn(.primary, size: .small))
            tierMenu("Change priority")
        }
    }

    private func tierMenu(_ label: String) -> some View {
        Menu {
            ForEach(Tier.all, id: \.self) { tier in
                Button(Tier.name(tier)) { model.adjustSuggestion(suggestion.id, tier: tier) }
            }
        } label: {
            Text(label)
        }
        .buttonStyle(.dtn(size: .small))
    }
}
