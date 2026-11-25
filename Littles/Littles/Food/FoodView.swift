import SwiftUI
import LittlesKit

/// The Food tab: progress toward 100 foods, allergens in rotation, what to
/// feed today, and the first-foods guide.
struct FoodView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var category: FoodCategory?
    @State private var showHoldOffs = false
    @State private var path: [String] = []
    @State private var logMeal: LogTarget?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    KidPicker(selection: Binding(get: { model.kidID }, set: { model.select($0) }))
                        .padding(.horizontal, -16)
                    if let kid = model.kid {
                        if search.isEmpty {
                            overview(kid)
                        }
                        guide(kid)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Food")
            .searchable(text: $search, prompt: "Search 60+ foods")
            .navigationDestination(for: String.self) { id in
                if let food = FoodGuide.food(id) {
                    FoodDetailView(food: food)
                }
            }
            .sheet(item: $logMeal) { target in
                LogSheet(entry: target.entry, isNew: true).environmentObject(model)
            }
            .sheet(isPresented: $showHoldOffs) {
                HoldOffSheet()
            }
            .onAppear {
                if Screenshots.shows("fooddetail") { path = ["egg"] }
            }
        }
    }

    @ViewBuilder
    private func overview(_ kid: Kid) -> some View {
        let age = kid.ageMonths(on: Date())
        if age < 6 {
            VStack(alignment: .leading, spacing: 8) {
                Text("🥄 Solids usually start around 6 months")
                    .font(.headline)
                Text("Signs \(kid.name) is ready: sits up with little help, holds their head steady, brings things to their mouth, and shows interest in your food. Ask your pediatrician, especially about allergens if \(kid.name) has severe eczema.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        } else {
            ProgressCard(kid: kid)
            AllergenCard(kid: kid)
            TodayIdeas(kid: kid) { ids in
                logMeal = LogTarget(entry: LogEntry(kidID: kid.id, kind: .solids, start: Date(),
                                                    bites: ids.map { FoodBite(foodID: $0) }), isNew: true)
            }
        }
        Button { showHoldOffs = true } label: {
            HStack {
                Text("⛔️ Foods to hold off on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func guide(_ kid: Kid) -> some View {
        let stats = FoodProgress.stats(model.state.logs, kidID: kid.id)
        SectionTitle(text: "First foods guide")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", selected: category == nil) { category = nil }
                ForEach(FoodCategory.allCases) { item in
                    filterChip(item.title, selected: category == item) { category = item }
                }
            }
        }
        let foods = FoodGuide.all.filter { food in
            (category == nil || food.category == category)
                && (search.isEmpty || food.name.localizedCaseInsensitiveContains(search))
        }
        if foods.isEmpty {
            EmptyNote(emoji: "🔍", text: "No food called \"\(search)\" in the guide yet.").card()
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(foods) { food in
                    NavigationLink(value: food.id) {
                        FoodTile(food: food, stats: stats[food.id])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Text("General guidance for healthy babies, not medical advice. Always supervise meals, keep baby seated upright, and ask your pediatrician about allergens.")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.accent : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// "34 of 100 foods" with a ring.
struct ProgressCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid

    var body: some View {
        let stats = FoodProgress.stats(model.state.logs, kidID: kid.id)
        let tried = stats.count
        let fraction = min(1, Double(tried) / Double(FoodProgress.goal))
        let loved = stats.values.filter { $0.loved > 0 }.count
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let newThisWeek = stats.values.filter { $0.first >= weekAgo }.count
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.sunk, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.color(kid), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(tried)").font(Theme.display(26))
                    Text("of \(FoodProgress.goal)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 86, height: 86)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(kid.name)'s first 100 foods")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("\(newThisWeek) new this week · \(loved) loved")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Text(encouragement(tried))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func encouragement(_ tried: Int) -> String {
        switch tried {
        case 0: return "Log a meal to start counting."
        case 1..<25: return "Great start. Variety now pays off later."
        case 25..<60: return "Lots of tastes and textures already."
        case 60..<100: return "Over halfway to 100!"
        default: return "100 foods! 🎉"
        }
    }
}

/// The nine allergens as chips, colored by where each stands.
struct AllergenCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid

    var body: some View {
        let statuses = FoodProgress.allergens(model.state.logs, kidID: kid.id, now: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Allergens")
                    .font(.headline)
                Spacer()
                Text("\(statuses.filter { $0.state == .inRotation }.count) of 9 in rotation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(statuses) { status in
                    VStack(spacing: 2) {
                        Text(status.allergen.emoji).font(.title3)
                        Text(status.allergen.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Text(label(status))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(status.state))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(color(status.state).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Text("Once started, offer each allergen about twice a week to keep it in the diet.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func label(_ status: AllergenStatus) -> String {
        switch status.state {
        case .introducing: return "\(status.exposures) of 3 tries"
        case .due:
            if let last = status.last {
                return "\(Int(Date().timeIntervalSince(last) / 86_400))d ago · due"
            }
            return "Due"
        default: return status.state.title
        }
    }

    private func color(_ state: AllergenState) -> Color {
        switch state {
        case .notStarted: return Theme.muted
        case .introducing: return Theme.accent
        case .inRotation: return Theme.good
        case .due: return Theme.warn
        case .reaction: return Color.red
        }
    }
}

/// "What to feed today": a few foods with a reason each, and one tap to log them.
struct TodayIdeas: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let onLog: ([String]) -> Void

    var body: some View {
        let ideas = FoodProgress.suggestions(for: kid, logs: model.state.logs, now: Date())
        VStack(alignment: .leading, spacing: 10) {
            Text("What to feed today")
                .font(.headline)
            ForEach(ideas) { idea in
                NavigationLink(value: idea.food.id) {
                    HStack(spacing: 12) {
                        Text(idea.food.emoji)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Theme.sunk, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.food.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                            Text(idea.reason.title).font(.caption).foregroundStyle(Theme.accent)
                            Text(idea.food.howToServe(ageMonths: kid.ageMonths(on: Date())))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
            if !ideas.isEmpty {
                Button {
                    onLog(ideas.map { $0.food.id })
                } label: {
                    Label("Log these as a meal", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .card()
    }
}

/// One food in the guide grid.
struct FoodTile: View {
    let food: FoodItem
    let stats: FoodStats?

    var body: some View {
        HStack(spacing: 10) {
            Text(food.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    if let stats {
                        Text(stats.lastLiking.emoji)
                        Text("\(stats.tries)×").foregroundStyle(Theme.muted)
                    } else {
                        Text(food.minMonths > 6 ? "\(food.minMonths) mo +" : "Not yet").foregroundStyle(Theme.muted)
                    }
                    if food.allergen != nil {
                        Text("· allergen").foregroundStyle(Theme.warn)
                    }
                }
                .font(.caption2.weight(.semibold))
            }
            Spacer(minLength: 0)
            if stats != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct HoldOffSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(FoodGuide.holdOffs) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title).font(.headline)
                        Spacer()
                        Pill(text: item.untilMonths >= 216 ? "Always" : "Until \(Age.short(months: item.untilMonths))", color: Theme.warn)
                    }
                    Text(item.why).font(.subheadline).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Hold off on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
