import SwiftUI
import OMMKit

/// The home grid in three labeled, colored sections (upper body, lower body,
/// core), each a body-area label then four muscle groups. One pick per section.
/// Groups trained in the last week are faded, so ready ones stand out.
struct MuscleGrid: View {
    @Environment(AppModel.self) private var model

    private let cellShape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        let now = Date()
        VStack(spacing: 12) {
            Text("Pick one from each: upper body, lower body, core")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            ForEach(Catalog.sections) { section in
                sectionView(section, now: now)
            }
            Text("Faded: trained in the last \(ProgramState.recoveryDays) days. Crossed out: finished.")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
        }
        .sensoryFeedback(.selection, trigger: model.selection)
    }

    private func sectionView(_ section: CategorySection, now: Date) -> some View {
        let color = section.category.color
        let picked = model.selection[section.category].flatMap(Catalog.group)
        return VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(section.category.title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color, in: Capsule())
                Spacer()
                Text(picked.map { "✓ \($0.area) · \($0.name)" } ?? "Pick 1")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(picked == nil ? Theme.muted : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(section.rows) { row in
                HStack(spacing: 3) {
                    Text(row.area)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(2)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(color.opacity(0.12), in: cellShape)
                        .accessibilityHidden(true)
                    ForEach(row.groups) { group in
                        cell(group, sectionPicked: picked != nil, now: now)
                    }
                }
            }
        }
    }

    private func cell(_ group: MuscleGroup, sectionPicked: Bool, now: Date) -> some View {
        let color = group.category.color
        let done = model.program.isDone(group)
        let selected = !done && model.selection.contains(group)
        // How recently trained, 1 today to 0 after a week. Picked and finished cells keep their own look.
        let fade = done || selected ? 0 : model.program.freshness(of: group, now: now)
        let fill = done ? Theme.doneBackground : (selected ? color : Color.white.mix(with: Theme.faded, by: fade))
        let stroke = done ? Theme.doneBackground : (selected ? color : Theme.border)
        let ink = done ? Theme.doneText : (selected ? Color.white : Theme.text.opacity(1 - 0.55 * fade))
        // Once a section has its pick, its other groups step back. They can still be tapped to switch.
        let dimmed = sectionPicked && !selected && !done

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
                .shadow(color: color.opacity(selected ? 0.45 : 0), radius: 5, y: 3)
                .opacity(dimmed ? 0.45 : 1)
                .contentShape(cellShape)
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityLabel("\(group.name), \(group.area), \(group.category.title)")
        .accessibilityValue(accessibilityValue(group, done: done, now: now))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessibilityValue(_ group: MuscleGroup, done: Bool, now: Date) -> String {
        if done { return "Done" }
        guard let days = model.program.daysSinceTrained(group, now: now),
              days < ProgramState.recoveryDays else { return "" }
        return days == 0 ? "Trained today" : "Trained \(days.counted("day")) ago"
    }
}
