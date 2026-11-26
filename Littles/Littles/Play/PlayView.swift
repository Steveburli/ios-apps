import SwiftUI
import LittlesKit

/// The Play tab: things to do with the kids, filtered by who's playing, how
/// much time there is, and inside or out. "Everyone" finds things that fit
/// every kid's age at once.
struct PlayView: View {
    @EnvironmentObject var model: AppModel
    @State private var who = ""
    @State private var minutes: Int?
    @State private var place: Place?
    @State private var energy: Energy?
    @State private var skill: Skill?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    KidPicker(selection: $who, allowBoth: true)
                        .padding(.horizontal, -16)
                    filters
                    let list = ranked
                    if let pick = list.first {
                        NavigationLink(value: pick.id) {
                            PickCard(activity: pick, favorite: model.state.favoriteActivities.contains(pick.id))
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        NearbyView()
                    } label: {
                        HStack {
                            Text("📍 Places to go nearby").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("Parks, libraries, splash pads").font(.caption).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                    WorkingOnCard(kidIDs: kidIDs)
                    TimeTotalsCard(kidIDs: kidIDs)
                    SectionTitle(text: "Ideas", trailing: "\(list.count)")
                    if list.isEmpty {
                        EmptyNote(emoji: "🧸", text: "Nothing fits all of that. Try more time, or anywhere.").card()
                    } else {
                        ForEach(list.dropFirst()) { activity in
                            NavigationLink(value: activity.id) {
                                ActivityRow(activity: activity, favorite: model.state.favoriteActivities.contains(activity.id),
                                            times: model.timesDone(activity.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Play")
            .navigationDestination(for: String.self) { id in
                if let activity = ActivityLibrary.activity(id) {
                    ActivityDetailView(activity: activity, kidIDs: kidIDs)
                }
            }
            .onAppear {
                if Screenshots.shows("activity"), let first = ranked.first { path = [first.id] }
            }
        }
    }

    private var kidIDs: [String] {
        who.isEmpty ? model.state.kids.map { $0.id } : [who]
    }

    private var ranked: [Activity] {
        let ages = kidIDs.compactMap { model.kid($0)?.ageMonths(on: Date()) }
        let filter = ActivityFilter(agesMonths: ages, maxMinutes: minutes, place: place, energy: energy, skill: skill)
        return ActivityPicker.ranked(filter, done: model.state.activitiesDone, favorites: model.state.favoriteActivities,
                                     today: Dates.key(Date()))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Time", selection: $minutes) {
                        Text("Any length").tag(Int?.none)
                        Text("10 minutes").tag(Int?.some(10))
                        Text("20 minutes").tag(Int?.some(20))
                        Text("30 minutes").tag(Int?.some(30))
                    }
                } label: {
                    chip(minutes.map { "⏱ \($0) min" } ?? "⏱ Any time", on: minutes != nil)
                }
                Menu {
                    Picker("Where", selection: $place) {
                        Text("Anywhere").tag(Place?.none)
                        Text("Inside").tag(Place?.some(.inside))
                        Text("Outside").tag(Place?.some(.outside))
                    }
                } label: {
                    chip(place.map { $0 == .inside ? "🏠 Inside" : "🌳 Outside" } ?? "📍 Anywhere", on: place != nil)
                }
                Menu {
                    Picker("Energy", selection: $energy) {
                        Text("Any energy").tag(Energy?.none)
                        Text("Calm").tag(Energy?.some(.calm))
                        Text("Active").tag(Energy?.some(.active))
                    }
                } label: {
                    chip(energy.map { $0 == .calm ? "🧘 Calm" : "⚡️ Active" } ?? "⚡️ Any energy", on: energy != nil)
                }
                Menu {
                    Picker("Skill", selection: $skill) {
                        Text("Any skill").tag(Skill?.none)
                        ForEach(Skill.allCases) { Text($0.title).tag(Skill?.some($0)) }
                    }
                } label: {
                    chip(skill?.title ?? "🧠 Any skill", on: skill != nil)
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Theme.ink)
            .background(on ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(on ? Theme.accent : Theme.line, lineWidth: 1))
    }
}

/// The top idea, big.
struct PickCard: View {
    let activity: Activity
    let favorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's pick")
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if favorite { Image(systemName: "heart.fill").foregroundStyle(.white) }
            }
            HStack(alignment: .top, spacing: 14) {
                Text(activity.emoji).font(.system(size: 46))
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.title).font(Theme.display(22)).foregroundStyle(.white)
                    Text(activity.why).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(3)
                }
            }
            HStack(spacing: 6) {
                Pill(text: "\(activity.minutes) min", color: .white)
                Pill(text: activity.place.title, color: .white)
                Pill(text: activity.ageLabel, color: .white)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x0E7C70), Color(hex: 0x3B7DD8)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        )
    }
}

struct ActivityRow: View {
    let activity: Activity
    let favorite: Bool
    let times: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(activity.emoji)
                .font(.title)
                .frame(width: 52, height: 52)
                .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activity.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                    if favorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Color.pink) }
                }
                Text("\(activity.minutes) min · \(activity.place.title) · \(activity.energy.title)" + (activity.mess > 0 ? " · messy" : ""))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Text(activity.skills.map { $0.title }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if times > 0 {
                Text("\(times)×").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }
}

struct ActivityDetailView: View {
    @EnvironmentObject var model: AppModel
    let activity: Activity
    let kidIDs: [String]
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Text(activity.emoji)
                        .font(.system(size: 50))
                        .frame(width: 80, height: 80)
                        .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activity.title).font(Theme.display(24)).foregroundStyle(Theme.ink)
                        Text("\(activity.ageLabel) · \(activity.minutes) min · \(activity.place.title)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        HStack(spacing: 6) {
                            ForEach(activity.skills) { Pill(text: $0.title) }
                        }
                    }
                }
                Text(activity.why)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .card()
                if !activity.materials.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You'll need").font(.headline)
                        ForEach(activity.materials, id: \.self) { item in
                            Label(item, systemImage: "circle.fill")
                                .labelStyle(BulletLabel())
                        }
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("How").font(.headline)
                    ForEach(Array(activity.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Theme.accent, in: Circle())
                            Text(step).font(.subheadline).foregroundStyle(Theme.ink)
                        }
                    }
                }
                .card()
                Button {
                    model.markDone(activity.id, kidIDs: kidIDs, hit: true)
                    logged = true
                } label: {
                    Label(logged ? "Nice! Logged for today" : "We did this", systemImage: logged ? "checkmark" : "hand.thumbsup.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(logged)
                Text("Always stay close with water, small parts and anything that goes in a mouth.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let favorite = model.state.favoriteActivities.contains(activity.id)
                Button {
                    model.toggleFavorite(activity.id)
                } label: {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .foregroundStyle(favorite ? Color.pink : Theme.accent)
                }
                .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
            }
        }
    }
}

/// A small dot instead of an icon.
struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            configuration.title.font(.subheadline).foregroundStyle(Theme.ink)
        }
    }
}
