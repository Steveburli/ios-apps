import Foundation

/// Merges another phone's family file into this one, so two parents (or a
/// sitter) can log on their own phones and swap files to catch up. Log
/// entries keep the newer copy; everything else keeps this phone's copy and
/// adds what's new. Things deleted on either phone stay deleted.
public enum FamilySync {
    public struct Result {
        public var state: FamilyState
        /// Log entries that came from the other phone (new or newer).
        public var newLogs: Int
        /// Other things added: routines, events, contacts and so on.
        public var newOther: Int
    }

    public static func merge(_ mine: FamilyState, _ theirs: FamilyState) -> Result {
        let deleted = Set(mine.deleted).union(theirs.deleted)
        var state = mine
        var newOther = 0

        func union<T: Identifiable>(_ a: [T], _ b: [T]) -> [T] where T.ID == String {
            let have = Set(a.map { $0.id })
            let added = b.filter { !have.contains($0.id) && !deleted.contains($0.id) }
            newOther += added.count
            return (a + added).filter { !deleted.contains($0.id) }
        }

        // Logs: the newer copy wins.
        var byID: [String: LogEntry] = [:]
        for entry in mine.logs { byID[entry.id] = entry }
        var newLogs = 0
        for entry in theirs.logs where !deleted.contains(entry.id) {
            if let current = byID[entry.id] {
                if (entry.updated ?? entry.start) > (current.updated ?? current.start) {
                    byID[entry.id] = entry
                    newLogs += 1
                }
            } else {
                byID[entry.id] = entry
                newLogs += 1
            }
        }
        state.logs = byID.values.filter { !deleted.contains($0.id) }.sorted { $0.start < $1.start }

        // Kids: keep this phone's, but take a birthday or sex this phone doesn't have.
        var kids = union(mine.kids, theirs.kids)
        for index in kids.indices {
            if let other = theirs.kids.first(where: { $0.id == kids[index].id }) {
                if kids[index].birthday.isEmpty { kids[index].birthday = other.birthday }
                if kids[index].sex.isEmpty { kids[index].sex = other.sex }
            }
        }
        state.kids = kids
        state.routines = union(mine.routines, theirs.routines)
        state.events = union(mine.events, theirs.events)
        state.packItems = union(mine.packItems, theirs.packItems)
        state.activitiesDone = union(mine.activitiesDone, theirs.activitiesDone)
        state.charts = union(mine.charts, theirs.charts)
        state.contacts = union(mine.contacts, theirs.contacts)
        var shopping = union(mine.shopping, theirs.shopping)
        for index in shopping.indices where theirs.shopping.contains(where: { $0.id == shopping[index].id && $0.done }) {
            shopping[index].done = true
        }
        state.shopping = shopping

        state.packed = Array(Set(mine.packed).union(theirs.packed)).sorted()
        state.chartDone = Array(Set(mine.chartDone).union(theirs.chartDone)).sorted()
        state.favoriteActivities = mine.favoriteActivities + theirs.favoriteActivities.filter { !mine.favoriteActivities.contains($0) }
        for (kidID, marks) in theirs.milestones {
            var merged = state.milestones[kidID] ?? [:]
            for (id, status) in marks where merged[id] == nil { merged[id] = status }
            state.milestones[kidID] = merged
        }
        for (kidID, doses) in theirs.vaccines {
            var merged = state.vaccines[kidID] ?? [:]
            for (id, day) in doses where merged[id] == nil { merged[id] = day }
            state.vaccines[kidID] = merged
        }
        state.onboarded = mine.onboarded || theirs.onboarded
        state.deleted = Array(deleted).sorted()
        return Result(state: state, newLogs: newLogs, newOther: newOther)
    }
}

/// The pediatrician report: the last two weeks for one kid, as a web page the
/// app prints to PDF.
public enum PediatricianReport {
    public static func html(kid: Kid, state: FamilyState, now: Date, days: Int = 14, calendar: Calendar = Dates.calendar) -> String {
        let units = state.units
        let today = Dates.key(now, calendar: calendar)
        let first = Dates.addDays(today, -(days - 1), calendar: calendar)
        let logs = state.logs.filter { $0.kidID == kid.id && Dates.key($0.start, calendar: calendar) >= first }
        func esc(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var totals = DaySummary()
        var dayCount = 0
        for offset in 0..<days {
            let key = Dates.addDays(first, offset, calendar: calendar)
            guard let date = Dates.date(key, calendar: calendar) else { continue }
            let day = Summary.day(state.logs, kidID: kid.id, on: date, now: now, calendar: calendar)
            if day.bottles + day.diapers + day.sleepMinutes + day.meals + day.nursing > 0 { dayCount += 1 }
            totals.bottles += day.bottles
            totals.bottleOz += day.bottleOz
            totals.nursing += day.nursing
            totals.diapers += day.diapers
            totals.wet += day.wet
            totals.dirty += day.dirty
            totals.sleepMinutes += day.sleepMinutes
            totals.meals += day.meals
        }
        let perDay = Double(max(1, dayCount))
        var html = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 11pt; color: #222; margin: 28px; }
        h1 { font-size: 20pt; margin: 0 0 4px; } h2 { font-size: 13pt; margin: 18px 0 6px; border-bottom: 1px solid #ccc; }
        table { border-collapse: collapse; width: 100%; } td, th { text-align: left; padding: 3px 6px; border-bottom: 1px solid #eee; font-size: 10pt; }
        .muted { color: #777; } .warn { color: #b3261e; font-weight: 600; }
        </style></head><body>
        <h1>\(esc(kid.name))</h1>
        <div class="muted">Born \(esc(kid.birthday)) · \(esc(kid.ageLabel(on: now, calendar: calendar))) · Report for \(esc(first)) to \(esc(today)), from the Littles app</div>
        """
        html += "<h2>Daily averages (\(dayCount) days logged)</h2><table>"
        if totals.bottles > 0 {
            html += "<tr><td>Bottles</td><td>\(String(format: "%.1f", Double(totals.bottles) / perDay)) a day, \(units.volume(totals.bottleOz / perDay)) a day</td></tr>"
        }
        if totals.nursing > 0 { html += "<tr><td>Nursing</td><td>\(String(format: "%.1f", Double(totals.nursing) / perDay)) sessions a day</td></tr>" }
        if totals.diapers > 0 {
            html += "<tr><td>Diapers</td><td>\(String(format: "%.1f", Double(totals.wet) / perDay)) wet, \(String(format: "%.1f", Double(totals.dirty) / perDay)) dirty a day</td></tr>"
        }
        if totals.sleepMinutes > 0 { html += "<tr><td>Sleep</td><td>\(String(format: "%.1f", Double(totals.sleepMinutes) / 60 / perDay)) hours a day</td></tr>" }
        if totals.meals > 0 { html += "<tr><td>Meals</td><td>\(String(format: "%.1f", Double(totals.meals) / perDay)) a day</td></tr>" }
        html += "</table>"

        // Foods and reactions.
        let stats = FoodProgress.stats(state.logs, kidID: kid.id)
        if !stats.isEmpty {
            html += "<h2>Foods</h2><p>\(stats.count) foods tried in all.</p>"
            let reactions = state.logs.filter { $0.kidID == kid.id && $0.kind == .solids && $0.bites.contains { $0.reaction } }
            if !reactions.isEmpty {
                html += "<p class=\"warn\">Possible reactions:</p><table>"
                for entry in reactions.sorted(by: { $0.start > $1.start }) {
                    let names = entry.bites.filter { $0.reaction }.map { FoodGuide.food($0.foodID)?.name ?? $0.foodID }.joined(separator: ", ")
                    html += "<tr><td>\(Dates.key(entry.start, calendar: calendar))</td><td>\(esc(names))</td><td>\(esc(entry.note))</td></tr>"
                }
                html += "</table>"
            }
            let allergens = FoodProgress.allergens(state.logs, kidID: kid.id, now: now)
            html += "<p>Allergens: " + allergens.map { "\($0.allergen.title): \($0.state.title.lowercased())" }.joined(separator: " · ") + "</p>"
        }

        // Growth.
        let growth = Summary.growth(state.logs, kidID: kid.id)
        if !growth.isEmpty {
            html += "<h2>Growth</h2><table><tr><th>Date</th><th>Weight</th><th>Height</th><th>Head</th></tr>"
            for entry in growth.suffix(6).reversed() {
                let days = Growth.ageDays(birthday: kid.birthday, at: entry.start, calendar: calendar)
                func pct(_ kind: Growth.Kind, _ value: Double?) -> String {
                    guard let value, let p = Growth.percentile(kind, value: value, ageDays: days, sex: kid.sex) else { return "" }
                    return " (\(Growth.label(p)))"
                }
                html += "<tr><td>\(Dates.key(entry.start, calendar: calendar))</td>"
                html += "<td>\(entry.weightLb.map { units.weight($0) } ?? "")\(pct(.weight, entry.weightLb))</td>"
                html += "<td>\(entry.heightIn.map { units.length($0) } ?? "")\(pct(.height, entry.heightIn))</td>"
                html += "<td>\(entry.headIn.map { units.length($0) } ?? "")</td></tr>"
            }
            html += "</table>"
        }

        // Sick days and medicine.
        let health = logs.filter { [.meds, .temperature, .symptom].contains($0.kind) }.sorted { $0.start > $1.start }
        if !health.isEmpty {
            html += "<h2>Illness and medicine</h2><table>"
            for entry in health {
                html += "<tr><td>\(entry.start.formatted(date: .abbreviated, time: .shortened))</td><td>\(entry.kind.title)</td><td>\(esc(entry.detail(now: now, units: units)))</td></tr>"
            }
            html += "</table>"
        }

        // Milestones not yet.
        let marks = state.milestones[kid.id] ?? [:]
        let age = kid.ageMonths(on: now, calendar: calendar)
        let notYet = Milestones.all.filter { $0.months <= Milestones.current(ageMonths: age) && marks[$0.id] == .notYet }
        let unsure = Milestones.all.filter { $0.months <= Milestones.current(ageMonths: age) && marks[$0.id] == .unsure }
        if !notYet.isEmpty || !unsure.isEmpty {
            html += "<h2>Milestones to talk about</h2><table>"
            for item in notYet { html += "<tr><td>Not yet</td><td>\(esc(item.text))</td><td class=\"muted\">by \(Milestones.ageTitle(item.months))</td></tr>" }
            for item in unsure { html += "<tr><td>Not sure</td><td>\(esc(item.text))</td><td class=\"muted\">by \(Milestones.ageTitle(item.months))</td></tr>" }
            html += "</table>"
        }

        // Vaccines.
        let given = state.vaccines[kid.id] ?? [:]
        let due = HealthSchedule.dueNow(ageMonths: age, given: given)
        if !given.isEmpty || !due.isEmpty {
            html += "<h2>Vaccines</h2><table>"
            for dose in HealthSchedule.doses { if let day = given[dose.id] { html += "<tr><td>\(esc(dose.short)) \(esc(dose.dose))</td><td>Given \(esc(day))</td></tr>" } }
            for dose in due { html += "<tr><td>\(esc(dose.short)) \(esc(dose.dose))</td><td class=\"warn\">Due by the parent's log</td></tr>" }
            html += "</table>"
        }

        let notes = logs.filter { $0.kind == .note && !$0.note.isEmpty }.sorted { $0.start > $1.start }
        if !notes.isEmpty {
            html += "<h2>Notes</h2><table>"
            for entry in notes { html += "<tr><td>\(Dates.key(entry.start, calendar: calendar))</td><td>\(esc(entry.note))</td></tr>" }
            html += "</table>"
        }
        html += "<p class=\"muted\">Logged by parents in Littles. Not a medical record.</p></body></html>"
        return html
    }
}

/// A month's highlights for one kid, to save or send to grandparents.
public enum Recap {
    public struct Month: Equatable {
        public var title: String
        public var firsts: [String]
        public var quotes: [String]
        public var newFoods: [String]
        public var lovedFood: String?
        public var weightChange: Double?
        public var heightChange: Double?
        public var activities: Int
        public var photos: [String]
        public var milestonesDone: Int
    }

    /// `month` is "yyyy-MM".
    public static func month(_ month: String, kid: Kid, state: FamilyState, calendar: Calendar = Dates.calendar) -> Month {
        let inMonth = state.logs.filter { $0.kidID == kid.id && Dates.key($0.start, calendar: calendar).hasPrefix(month) }
            .sorted { $0.start < $1.start }
        let before = state.logs.filter { $0.kidID == kid.id && Dates.key($0.start, calendar: calendar) < month + "-01" }
        let triedBefore = Set(FoodProgress.stats(before, kidID: kid.id).keys)
        let monthStats = FoodProgress.stats(inMonth, kidID: kid.id)
        let newFoods = monthStats.keys.filter { !triedBefore.contains($0) }.compactMap { FoodGuide.food($0)?.name }.sorted()
        let loved = monthStats.values.filter { $0.loved > 0 }.max { ($0.loved, $1.foodID) < ($1.loved, $0.foodID) }
        let growth = Summary.growth(state.logs, kidID: kid.id)
        let start = growth.last { Dates.key($0.start, calendar: calendar) < month + "-01" } ?? growth.first
        let end = growth.last { Dates.key($0.start, calendar: calendar).hasPrefix(month) }
        func change(_ path: KeyPath<LogEntry, Double?>) -> Double? {
            guard let start, let end, start.id != end.id, let a = start[keyPath: path], let b = end[keyPath: path] else { return nil }
            return b - a
        }
        var title = month
        if let date = Dates.date(month + "-01", calendar: calendar) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM yyyy"
            title = formatter.string(from: date)
        }
        let done = state.activitiesDone.filter { $0.day.hasPrefix(month) && ($0.kidIDs.isEmpty || $0.kidIDs.contains(kid.id)) }.count
        let marks = state.milestones[kid.id] ?? [:]
        let age = kid.ageMonths(on: Dates.date(month + "-28", calendar: calendar) ?? Date(), calendar: calendar)
        let milestonesDone = Milestones.list(for: Milestones.current(ageMonths: age)).filter { marks[$0.id] == .yes }.count
        return Month(title: title,
                     firsts: inMonth.filter { $0.kind == .first }.map { $0.note },
                     quotes: inMonth.filter { $0.kind == .quote }.map { $0.note },
                     newFoods: newFoods,
                     lovedFood: loved.flatMap { FoodGuide.food($0.foodID)?.name },
                     weightChange: change(\.weightLb),
                     heightChange: change(\.heightIn),
                     activities: done,
                     photos: inMonth.map { $0.photo }.filter { !$0.isEmpty },
                     milestonesDone: milestonesDone)
    }

    /// Firsts and quotes for the memories timeline, newest first.
    public static func memories(_ logs: [LogEntry], kidID: String?) -> [LogEntry] {
        logs.filter { ($0.kind.isMemory || !$0.photo.isEmpty) && (kidID == nil || $0.kidID == kidID) }.sorted { $0.start > $1.start }
    }
}

/// Activities that practice the milestones a kid is working on.
public enum MilestoneActivities {
    /// Words in a milestone and the activities that practice them.
    static let links: [(words: [String], activities: [String])] = [
        (["tummy", "head up", "pushes up", "elbows"], ["tummy-mirror"]),
        (["coo", "sounds", "babbl", "words", "talk", "conversation", "says", "name"], ["narrate", "board-books", "sing-actions", "story-dice"]),
        (["looks for", "hide", "peekaboo"], ["peekaboo", "tissue-pull"]),
        (["container", "stack", "blocks"], ["muffin-tin", "tissue-pull"]),
        (["walks", "climb", "stairs", "runs"], ["crawl-tunnel", "playground", "animal-walks"]),
        (["kick", "ball", "catch"], ["ball-roll"]),
        (["jumps", "hops", "one foot"], ["hopscotch", "animal-walks", "counting-jumps"]),
        (["scribbl", "draws", "crayon", "pencil", "circle", "writes"], ["chalk-art", "sticker-line", "playdough", "cut-practice"]),
        (["color"], ["color-hunt"]),
        (["counts", "numbers"], ["counting-jumps", "pretend-store"]),
        (["letters"], ["letter-hunt"]),
        (["pretend"], ["pretend-store", "fort", "tape-road"]),
        (["turns", "rules", "games"], ["matching-memory", "ball-roll", "dance-freeze"]),
        (["chores", "helper", "copies you"], ["helper", "cooking"]),
        (["feelings", "hurt", "upset", "comforts", "calms"], ["feelings-faces", "big-little"]),
        (["buttons", "twist", "strings"], ["pouring", "playdough"]),
        (["spoon", "fork", "cup", "pours"], ["pouring", "cooking"]),
        (["rhyme", "song", "sings"], ["sing-actions"]),
        (["story"], ["story-dice", "board-books"]),
    ]

    public struct Pick: Identifiable, Equatable {
        public var milestone: Milestone
        public var activities: [Activity]
        public var id: String { milestone.id }
    }

    /// For the kid's current checklist: milestones not yet marked "yes", each
    /// with the activities that fit the kid's age and practice it.
    public static func picks(ageMonths: Int, statuses: [String: MilestoneStatus]) -> [Pick] {
        let checkpoint = Milestones.current(ageMonths: ageMonths)
        let upcoming = Milestones.upcoming(ageMonths: ageMonths)
        let items = Milestones.all.filter { ($0.months == checkpoint || $0.months == upcoming) && statuses[$0.id] != .yes }
        return items.compactMap { item -> Pick? in
            let text = item.text.lowercased()
            let ids = links.filter { link in link.words.contains { text.contains($0) } }.flatMap { $0.activities }
            var seen = Set<String>()
            let activities = ids.filter { seen.insert($0).inserted }
                .compactMap { ActivityLibrary.activity($0) }
                .filter { $0.fits(ageMonths: ageMonths) }
            return activities.isEmpty ? nil : Pick(milestone: item, activities: Array(activities.prefix(3)))
        }
    }
}
