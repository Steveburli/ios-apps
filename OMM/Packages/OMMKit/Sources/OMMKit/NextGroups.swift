import Foundation

/// Picks the next workout's groups, so the home grid opens with one upper,
/// one lower and one core group already chosen.
///
/// Steve's three levels: a body group is a category (upper, lower, core), a
/// muscle group is a grid row (Chest, Back, Thighs, Calves …) and a muscle is
/// one cell (Mid, Traps, Quads …). Each workout takes one muscle from each body
/// group. Within a body group the muscle group rotates: the one trained least
/// recently comes first, so after a Chest workout the next is Back, then
/// Shoulders, then Arms. Never-trained rows count as oldest and go in grid
/// order. Crossed-out muscles are skipped.
///
/// Inside the chosen row, a muscle already started is finished first, else the
/// next one in grid order: Mid, then Upper, Lower, Inner.
public enum NextGroups {
    public static func pick(_ category: MuscleCategory, in state: ProgramState) -> MuscleGroup? {
        let rows = Catalog.rows.filter { $0.category == category }
        let candidates = rows.enumerated().compactMap { index, row -> (index: Int, last: Date?, row: BodyAreaRow)? in
            guard row.groups.contains(where: { !state.isDone($0) }) else { return nil }
            let last = row.groups.compactMap { state.lastTrained[$0.key] }.max()
            return (index, last, row)
        }
        let best = candidates.min { a, b in
            switch (a.last, b.last) {
            case (nil, nil): return a.index < b.index
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x != y ? x < y : a.index < b.index
            }
        }
        guard let row = best?.row else { return nil }
        let open = row.groups.filter { !state.isDone($0) }
        return open.first { state.setsDone($0) > 0 } ?? open.first
    }

    /// One pick per body group, in upper, lower, core order.
    public static func picks(in state: ProgramState) -> [MuscleGroup] {
        MuscleCategory.allCases.compactMap { pick($0, in: state) }
    }
}

extension GroupSelection {
    /// Fills each empty body group with its next pick. Picks already made stay.
    public mutating func fillSuggested(from state: ProgramState) {
        for group in NextGroups.picks(in: state) where self[group.category] == nil {
            toggle(group)
        }
    }
}
