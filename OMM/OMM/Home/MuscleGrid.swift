import SwiftUI
import OMMKit

/// The 7 × 5 grid: a body-area label, then four muscle groups to pick from.
struct MuscleGrid: View {
    @Environment(AppModel.self) private var model

    private let cellShape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Catalog.rows) { row in
                HStack(spacing: 3) {
                    Text(row.area)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(2)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.labelBackground, in: cellShape)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(row.groups) { group in
                        cell(group)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.selection)
    }

    private func cell(_ group: MuscleGroup) -> some View {
        let done = model.program.isDone(group)
        let selected = !done && model.selection.contains(group)
        let fill = done ? Theme.doneBackground : (selected ? Theme.primary : Color.white)
        let stroke = done ? Theme.doneBackground : (selected ? Theme.primary : Theme.border)
        let ink = done ? Theme.doneText : (selected ? Color.white : Theme.text)

        return Button {
            model.toggle(group)
        } label: {
            Text(group.name)
                .font(.system(size: 13, weight: selected ? .bold : .medium))
                .strikethrough(done)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(2)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(fill, in: cellShape)
                .overlay(cellShape.strokeBorder(stroke, lineWidth: 1))
                .shadow(color: Theme.primary.opacity(selected ? 0.45 : 0), radius: 5, y: 3)
                .contentShape(cellShape)
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityLabel("\(group.name), \(group.area)")
        .accessibilityValue(done ? "Done" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
