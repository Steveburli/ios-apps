import SwiftUI
import LittlesKit

enum FoodRoute: Hashable {
    case plan, recipes, recipe(String), dinner
}

/// Three big buttons under the progress ring.
struct FoodLinks: View {
    var body: some View {
        HStack(spacing: 10) {
            link("🗓️", "Meal plan", .plan)
            link("📖", "Recipes", .recipes)
            link("🍽️", "Tonight", .dinner)
        }
    }

    private func link(_ emoji: String, _ title: String, _ route: FoodRoute) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 4) {
                Text(emoji).font(.title2)
                Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A week of meals for the chosen kid, with the grocery list.
struct MealPlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var added = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KidPicker(selection: Binding(get: { model.kidID }, set: { model.select($0) }))
                    .padding(.horizontal, -16)
                if let kid = model.kid {
                    content(kid)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Meal plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ kid: Kid) -> some View {
        let start = Dates.key(Date())
        let plan = MealPlanner.week(for: kid, logs: model.state.logs, start: start, seed: model.mealSeed(kid.id), now: Date())
        if plan.isEmpty {
            EmptyNote(emoji: "🍼", text: "\(kid.name) isn't on solids yet. Meal plans start at 6 months.").card()
        } else {
            let counts = MealPlanner.allergenCounts(plan)
            HStack {
                Text("Allergens this week: " + (counts.isEmpty ? "none yet" : counts.sorted { $0.key.title < $1.key.title }.map { "\($0.key.emoji)×\($0.value)" }.joined(separator: " ")))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Shuffle", systemImage: "shuffle") { model.shuffleMeals(kid.id) }
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(plan) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Dates.date(day.day)?.formatted(.dateTime.weekday(.wide).month().day()) ?? day.day)
                        .font(.headline)
                    ForEach(day.meals) { meal in
                        HStack(alignment: .top, spacing: 10) {
                            Text(meal.slot.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 70, alignment: .leading)
                            Text(meal.foodIDs.compactMap { FoodGuide.food($0) }.map { "\($0.emoji) \($0.name)" }.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .card()
            }
            let groceries = MealPlanner.groceries(plan)
            VStack(alignment: .leading, spacing: 8) {
                Text("🛒 Grocery list").font(.headline)
                ForEach(groceries, id: \.category) { group in
                    Text(group.category.title).font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                    Text(group.foods.map { $0.name }.joined(separator: ", ")).font(.subheadline)
                }
                Button {
                    for group in groceries { for food in group.foods { model.addShopping(food.name, list: "Groceries") } }
                    added = true
                } label: {
                    Label(added ? "Added to the shopping list" : "Add to the shopping list", systemImage: added ? "checkmark" : "cart.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(added)
            }
            .card()
            Text("Each started allergen shows up at least twice, a new one starts over three mornings, and new foods land at dinner. Swap anything you like: it's a starting point.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct RecipesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let kid = model.kid
        let age = kid?.ageMonths(on: Date()) ?? 12
        let tried = Set(FoodProgress.stats(model.state.logs, kidID: kid?.id ?? "").keys)
        List(RecipeBook.forKid(ageMonths: age, tried: tried)) { recipe in
            NavigationLink(value: FoodRoute.recipe(recipe.id)) {
                HStack(spacing: 12) {
                    Text(recipe.emoji).font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.title).font(.headline)
                        let fresh = recipe.foodIDs.filter { !tried.contains($0) }.count
                        Text("\(recipe.minutes < 60 ? "\(recipe.minutes) min" : Dates.duration(Double(recipe.minutes) * 60)) · \(recipe.foodIDs.count) foods"
                             + (fresh > 0 ? " · \(fresh) new for \(kid?.name ?? "them")" : ""))
                            .font(.caption)
                            .foregroundStyle(fresh > 0 ? Theme.accent : Theme.muted)
                    }
                }
            }
        }
        .navigationTitle("Recipes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject var model: AppModel
    let recipe: Recipe
    @State private var log: LogTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text(recipe.emoji).font(.system(size: 50))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title).font(Theme.display(24))
                        Text("From \(recipe.minMonths) months · \(recipe.minutes < 60 ? "\(recipe.minutes) min" : Dates.duration(Double(recipe.minutes) * 60))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(recipe.foodIDs, id: \.self) { id in
                        if let food = FoodGuide.food(id) {
                            Pill(text: "\(food.emoji) \(food.name)", color: food.allergen == nil ? Theme.accent : Theme.warn)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ingredients").font(.headline)
                    ForEach(recipe.ingredients, id: \.self) { Text("• " + $0).font(.subheadline) }
                }
                .card()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steps").font(.headline)
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").font(.subheadline)
                    }
                }
                .card()
                Text("💡 " + recipe.tip).font(.subheadline).card()
                Button {
                    if let kid = model.kid {
                        log = LogTarget(entry: LogEntry(kidID: kid.id, kind: .solids, start: Date(),
                                                        bites: recipe.foodIDs.map { FoodBite(foodID: $0) }, note: recipe.title), isNew: true)
                    }
                } label: {
                    Label("Log it as a meal", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $log) { target in
            LogSheet(entry: target.entry, isNew: true).environmentObject(model)
        }
    }
}

/// Pick tonight's grown-up dinner; see how to serve each part to each kid.
struct DinnerView: View {
    @EnvironmentObject var model: AppModel
    @State private var dinnerID = FamilyDinners.all[0].id

    var body: some View {
        let dinner = FamilyDinners.all.first { $0.id == dinnerID } ?? FamilyDinners.all[0]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FamilyDinners.all) { item in
                            Button { dinnerID = item.id } label: {
                                Text("\(item.emoji) \(item.title)")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(item.id == dinnerID ? Color.white : Theme.ink)
                                    .background(item.id == dinnerID ? Theme.accent : Theme.surface, in: Capsule())
                                    .overlay(Capsule().stroke(item.id == dinnerID ? Theme.accent : Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(model.state.kids) { kid in
                    let age = kid.ageMonths(on: Date())
                    let tried = Set(FoodProgress.stats(model.state.logs, kidID: kid.id).keys)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            KidBadge(kid: kid, size: 28)
                            Text("For \(kid.name)").font(.headline)
                            Text(kid.ageLabel(on: Date())).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        if age < 6 {
                            Text("Not on solids yet: a bottle or nursing at the table.").font(.subheadline).foregroundStyle(Theme.muted)
                        } else {
                            ForEach(FamilyDinners.adapt(dinner, ageMonths: age, tried: tried)) { part in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("\(part.food.emoji) \(part.food.name)").font(.subheadline.weight(.bold))
                                        if !part.flag.isEmpty {
                                            Pill(text: part.flag, color: part.flag == "New" ? Theme.accent : Theme.warn)
                                        }
                                    }
                                    Text(part.howToServe).font(.subheadline).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tips").font(.headline)
                    ForEach(dinner.tips + ["Serve everyone the same meal; let the kids choose how much to eat."], id: \.self) {
                        Text("• " + $0).font(.subheadline)
                    }
                }
                .card()
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Tonight's dinner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Safe foods and "learning" foods, for a picky toddler or preschooler.
struct PickyCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid

    var body: some View {
        let learning = PickyEater.learningFoods(model.state.logs, kidID: kid.id)
        let safe = PickyEater.safeFoods(model.state.logs, kidID: kid.id)
        if kid.ageMonths(on: Date()) >= 12 || !learning.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("🥦 Learning foods").font(.headline)
                if learning.isEmpty {
                    Text("Nothing refused lately. Keep offering variety!").font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(learning.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.food.emoji) \(item.food.name)").font(.subheadline.weight(.semibold))
                        HStack(spacing: 3) {
                            ForEach(0..<PickyEater.goal, id: \.self) { index in
                                Circle()
                                    .fill(index < item.tries ? Theme.color(kid) : Theme.sunk)
                                    .frame(width: 14, height: 14)
                            }
                            Text("\(min(item.tries, PickyEater.goal))/\(PickyEater.goal) tries").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if !safe.isEmpty {
                    Text("Safe foods to serve alongside: " + safe.prefix(8).map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Text("It can take 10 or more no-pressure tries. Serve a little with a safe food; touching and smelling count.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
    }
}
