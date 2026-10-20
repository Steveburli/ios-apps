import SwiftUI
import CloudKit
import MutualKit

struct HomeView: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session

    var body: some View {
        let group = session.group(in: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are we deciding?")
                        .font(Theme.display(40))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Everyone swipes on their own phone. Mutual shows you what you agree on.")
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 12)

                if store.sortedGroups.count > 1, let group {
                    GroupSwitcher(current: group)
                }

                if store.accountStatus == .noAccount || store.accountStatus == .restricted {
                    Text("You’re not signed in to iCloud, so decks stay on this phone. You can still pass the phone around. Sign in to iCloud in Settings to swipe together on separate phones.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                decks(in: group)

                Button {
                    session.sheet = .newDeck
                } label: {
                    Label("New deck", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashedButtonStyle())
                .disabled(group.map { !store.canWrite($0.id) } ?? false)

                if let group {
                    InvitePanel(group: group)
                        .padding(.top, 8)
                }

                HowItWorks()
                    .padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    BrandMark()
                    Text("Mutual")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Mutual")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    session.sheet = .groups
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("Groups and sharing")
                if let group {
                    WhoButton(groupID: group.id)
                }
            }
        }
    }

    @ViewBuilder
    private func decks(in group: SwipeGroup?) -> some View {
        let decks = group.map { store.decks(in: $0.id) } ?? []
        if decks.isEmpty {
            VStack(spacing: 6) {
                Text("No decks yet")
                    .font(Theme.display(22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Make one for dinners, movies, trips or anything else you’re deciding together.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(decks) { deck in
                    NavigationLink(value: deck.id) {
                        DeckTile(deck: deck)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct GroupSwitcher: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let current: SwipeGroup

    var body: some View {
        Menu {
            ForEach(store.sortedGroups) { group in
                Button {
                    session.currentGroupID = group.id
                } label: {
                    if group.id == current.id {
                        Label(group.name, systemImage: "checkmark")
                    } else {
                        Text(group.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("GROUP").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.muted)
                Text(current.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line))
        }
        .accessibilityLabel("Group: \(current.name)")
    }
}

/// "Swiping as …": who's using this phone right now.
struct WhoButton: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let groupID: String

    var body: some View {
        let me = session.me(in: groupID, store: store).flatMap { store.players[$0] }
        Button {
            session.sheet = .player(groupID)
        } label: {
            if let me {
                HStack(spacing: 8) {
                    PlayerDot(player: me)
                    Text(me.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.ink)
                }
                .padding(.leading, 4)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
            } else {
                Text("Who’s swiping?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Theme.accent))
            }
        }
        .accessibilityLabel(me.map { "Swiping as \($0.name). Switch person" } ?? "Who’s swiping? Choose your name")
    }
}

private struct DeckTile: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: Deck

    var body: some View {
        let me = session.me(in: deck.groupID, store: store)
        let state = store.state(of: deck.id, me: me)
        let total = state.cards.count
        let swipers = state.activeParticipants
        HStack(spacing: 16) {
            ZStack {
                ForEach(Array(state.cards.prefix(3).enumerated()), id: \.offset) { index, card in
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.cardColor(card.id))
                        .frame(width: 54, height: 74)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .rotationEffect(.degrees([-11, -2, 8][index]), anchor: .bottom)
                        .offset(x: [-3, 0, 3][index])
                }
                if state.cards.isEmpty {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.sunk).frame(width: 54, height: 74)
                }
            }
            .frame(width: 62, height: 80)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(deck.kind.plural.uppercased()) · \(total) CARD\(total == 1 ? "" : "S")")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.muted)
                Text(deck.title)
                    .font(Theme.display(21, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if !deck.blurb.isEmpty {
                    Text(deck.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                FlowLayout(spacing: 6) {
                    if state.matchCount > 0 {
                        Pill(text: "\(state.matchCount) match\(state.matchCount == 1 ? "" : "es")", tint: Theme.accent, background: Theme.accentSoft)
                    }
                    if me != nil && total > 0 {
                        if state.queue.isEmpty {
                            Pill(text: "You’re done", tint: Vote.like.color, background: Vote.like.soft)
                        } else {
                            Pill(text: "\(state.queue.count) left for you")
                        }
                    }
                    if !swipers.isEmpty {
                        HStack(spacing: -5) {
                            ForEach(swipers, id: \.self) { id in
                                PlayerDot(player: store.players[id], size: 22)
                                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                            }
                        }
                        .padding(.leading, 5)
                    }
                }
                .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Inviting people: iCloud sharing for the group.
private struct InvitePanel: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let group: SwipeGroup
    @State private var working = false

    var body: some View {
        Panel {
            if group.isOwned {
                Text(group.isShared ? "Swiping together" : "Bring people in")
                    .font(Theme.display(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(group.isShared
                     ? (group.participants.isEmpty ? "You’ve invited people to “\(group.name)”. They’ll appear here once they join."
                                                    : "Shared with \(group.participants.formatted(.list(type: .and))).")
                     : "Invite people to “\(group.name)” so they can swipe these decks on their own iPhones. They need to be signed in to iCloud.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Button(group.isShared ? "Manage people" : "Invite people") {
                    Task {
                        working = true
                        defer { working = false }
                        do {
                            let share = try await store.share(for: group.id)
                            SharingPresenter.present(share: share, container: store.container, title: group.name)
                        } catch {
                            session.show(error.localizedDescription)
                        }
                    }
                }
                .buttonStyle(.mutual())
                .disabled(working)
            } else {
                Text("Shared with you")
                    .font(Theme.display(18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(group.readOnly
                     ? "You can see “\(group.name)” but not change it."
                     : "You’re swiping in “\(group.name)”. Everyone in it sees the same decks.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Text("Sharing one phone? Tap your name at the top to switch who’s swiping.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct HowItWorks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(Theme.line)
            Text("How it works")
                .font(Theme.display(19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                move(.love, "Swipe up · super like")
                move(.like, "Swipe right")
                move(.nope, "Swipe left · reject")
                move(.never, "Swipe down · super reject")
            }
            VStack(alignment: .leading, spacing: 10) {
                rule(.perfect, "Everyone super liked it.")
                rule(.match, "Everyone liked or super liked it.")
                rule(.debate, "Someone super liked it and someone rejected it.")
                rule(.trash, "Anyone super rejected it, or everyone rejected it. Once someone super rejects a card, it skips the stack for everyone else.")
            }
        }
    }

    private func move(_ vote: Vote, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vote.symbol)
                .foregroundStyle(vote.color)
                .frame(width: 38, height: 38)
                .background(vote.soft, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(vote.label).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rule(_ verdict: Verdict, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdict.symbol)
                .font(.caption)
                .foregroundStyle(verdict.color)
                .frame(width: 28, height: 28)
                .background(verdict.soft, in: Circle())
            (Text(verdict.label).bold().foregroundStyle(Theme.ink) + Text("  " + text).foregroundStyle(Theme.muted))
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DashedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 12)
            .background(Color.clear)
            .overlay(Capsule().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
