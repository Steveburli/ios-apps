import SwiftUI
import LittlesKit

/// One food: how to serve it at each stage, choking and allergen notes, and
/// how it's gone for each kid.
struct FoodDetailView: View {
    @EnvironmentObject var model: AppModel
    let food: FoodItem
    @State private var logMeal: LogTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(stages, id: \.title) { stage in
                    stageCard(stage)
                }
                if !food.tip.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Text("💡").font(.title3)
                        Text(food.tip).font(.subheadline).foregroundStyle(Theme.ink)
                    }
                    .card()
                }
                historyCard
                Text("General guidance for healthy babies, not medical advice. Always stay with your child while they eat.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let kid = model.kid {
                        logMeal = LogTarget(entry: LogEntry(kidID: kid.id, kind: .solids, start: Date(),
                                                            bites: [FoodBite(foodID: food.id)]), isNew: true)
                    }
                } label: {
                    Label("Log it", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $logMeal) { target in
            LogSheet(entry: target.entry, isNew: true).environmentObject(model)
        }
    }

    private struct Stage {
        var title: String
        var text: String
        var current: Bool
    }

    private var stages: [Stage] {
        let age = model.kid?.ageMonths(on: Date()) ?? 6
        return [
            Stage(title: "6–8 months", text: food.early, current: age < 9),
            Stage(title: "9–11 months", text: food.middle, current: age >= 9 && age < 12),
            Stage(title: "12 months +", text: food.toddler, current: age >= 12),
        ]
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(food.emoji)
                .font(.system(size: 54))
                .frame(width: 84, height: 84)
                .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(food.name).font(Theme.display(26)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Pill(text: food.category.title.lowercased().capitalized)
                    if let allergen = food.allergen {
                        Pill(text: "\(allergen.emoji) \(allergen.title) allergen", color: Theme.warn)
                    }
                }
                Pill(text: food.choke.title, color: food.choke == .high ? Color.red : (food.choke == .medium ? Theme.warn : Theme.good))
                if food.minMonths > 6 {
                    Text("From \(food.minMonths) months").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func stageCard(_ stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stage.title).font(.headline).foregroundStyle(Theme.ink)
                if stage.current, let kid = model.kid {
                    Pill(text: "\(kid.name) now", color: Theme.color(kid), filled: true)
                }
            }
            Text(stage.text).font(.subheadline).foregroundStyle(Theme.ink)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(stage.current ? Theme.color(model.kid) : .clear, lineWidth: 2)
        )
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it's gone").font(.headline)
            ForEach(model.state.kids) { kid in
                let stats = FoodProgress.stats(model.state.logs, kidID: kid.id)[food.id]
                HStack(spacing: 10) {
                    KidBadge(kid: kid, size: 28)
                    Text(kid.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let stats {
                        Text("\(stats.lastLiking.emoji) \(stats.tries)× · last \(stats.last.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        if stats.reactions > 0 {
                            Pill(text: "Reaction", color: Color.red)
                        }
                    } else {
                        Text("Not tried").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .card()
    }
}
