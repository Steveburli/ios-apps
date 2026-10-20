import Foundation

extension PlannerState {
    /// The web app's example list, so a new person can see how it works.
    public mutating func loadExamples(now: Date, calendar: Calendar) {
        let today = CalendarDay(now, calendar: calendar)
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        func due(_ days: Int) -> CalendarDay { today.adding(days: days, calendar: calendar) }
        func make(_ title: String, _ kind: TaskKind, tier: Int, places: [Place], created: Date,
                  _ configure: (inout TaskItem) -> Void = { _ in }) -> TaskItem {
            var task = TaskItem(title: title, created: created)
            task.kind = kind
            task.tier = tier
            task.places = places
            task.isExample = true
            configure(&task)
            return task
        }

        let guitar = make("Practice guitar", .recurring, tier: 2, places: [.home], created: ago(40)) {
            $0.weekly = 120; $0.minBlock = 20; $0.maxSession = 45; $0.focus = .deep; $0.posture = .sit; $0.lastDone = ago(2)
        }
        let spanish = make("Learn Spanish", .recurring, tier: 4, places: [.phone, .computer], created: ago(35)) {
            $0.weekly = 120; $0.minBlock = 10; $0.maxSession = 30; $0.focus = .deep; $0.lastDone = ago(6)
        }
        let examples: [TaskItem] = [
            make("Finish the quarterly report", .task, tier: 1, places: [.computer, .office], created: ago(12)) {
                $0.estimate = 180; $0.spent = 45; $0.deadline = due(3); $0.stakes = 8; $0.maxSession = 60
                $0.focus = .deep; $0.posture = .sit; $0.lastDone = ago(4)
            },
            make("Reply to Sam about the cabin weekend", .task, tier: 2, places: [.phone, .computer], created: ago(3)) {
                $0.estimate = 10; $0.tv = true; $0.posture = .sit
            },
            guitar,
            make("Update the budget spreadsheet", .task, tier: 2, places: [.computer], created: ago(20)) {
                $0.estimate = 45; $0.deadline = due(9); $0.stakes = 5; $0.focus = .deep; $0.posture = .sit
            },
            make("Buy a birthday card for Mom", .errand, tier: 2, places: [.errand], created: ago(5)) {
                $0.place = "Pharmacy on 5th"; $0.estimate = 15; $0.deadline = due(6); $0.stakes = 8
            },
            make("Water the plants", .task, tier: 3, places: [.home], created: ago(30)) {
                $0.estimate = 10; $0.posture = .move; $0.lastDone = ago(6)
            },
            make("Fold the laundry", .task, tier: 3, places: [.home], created: ago(2)) {
                $0.estimate = 15; $0.tv = true
            },
            make("Wipe down the kitchen counters", .task, tier: 3, places: [.home], created: ago(4)) {
                $0.estimate = 10; $0.posture = .move
            },
            make("Pick up the dry cleaning", .errand, tier: 3, places: [.errand], created: ago(6)) {
                $0.place = "Main St Cleaners"; $0.estimate = 10; $0.deadline = due(4); $0.stakes = 4
            },
            make("Return library books", .errand, tier: 3, places: [.errand], created: ago(9)) {
                $0.place = "Library"; $0.estimate = 10; $0.deadline = due(2); $0.stakes = 3
            },
            make("Take a walk around the block", .task, tier: 3, places: [.home], created: ago(8)) {
                $0.estimate = 20; $0.posture = .move; $0.outside = true; $0.binge = true; $0.lastDone = ago(3)
            },
            spanish,
            make("Plan the vegetable garden", .task, tier: 4, places: [.home], created: ago(110)) {
                $0.estimate = 90; $0.binge = true; $0.posture = .move; $0.outside = true
            },
        ]
        tasks.append(contentsOf: examples)

        let practice: [(TaskItem, Double, Int)] = [
            (guitar, 2, 30), (guitar, 5, 45), (guitar, 9, 30), (guitar, 12, 40), (guitar, 16, 30),
            (guitar, 20, 45), (guitar, 23, 40), (spanish, 6, 10), (spanish, 15, 15),
        ]
        log.append(contentsOf: practice.map { LogEntry(taskID: $0.0.id, at: ago($0.1), minutes: $0.2) })

        events.append(PlannerEvent(title: "Jordan’s soccer game", day: today, start: 18 * 60, end: 19 * 60 + 30,
                                   minStay: 45, travel: 15, isExample: true))
        events.append(PlannerEvent(title: "Book club", day: due(1), start: 19 * 60 + 30, end: 21 * 60,
                                   minStay: 60, travel: 10, isExample: true))
    }

    public mutating func removeExamples() {
        let ids = Set(tasks.filter(\.isExample).map(\.id))
        tasks.removeAll(where: \.isExample)
        events.removeAll(where: \.isExample)
        log.removeAll { ids.contains($0.taskID) }
        if let active, active.taskIDs.contains(where: { ids.contains($0) }) {
            self.active = nil
        }
    }
}
