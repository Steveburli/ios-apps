import Foundation

public enum TipSituation: String, CaseIterable, Identifiable {
    case meltdown, notListening, siblings, bedtime, mealtime, transitions, dropoff, everyday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meltdown: return "Meltdowns"
        case .notListening: return "Not listening"
        case .siblings: return "Siblings"
        case .bedtime: return "Bedtime"
        case .mealtime: return "Mealtime"
        case .transitions: return "Leaving & switching"
        case .dropoff: return "School drop-off"
        case .everyday: return "Every day"
        }
    }

    public var emoji: String {
        switch self {
        case .meltdown: return "🌋"
        case .notListening: return "👂"
        case .siblings: return "👦👶"
        case .bedtime: return "🌙"
        case .mealtime: return "🍽️"
        case .transitions: return "🚪"
        case .dropoff: return "🏫"
        case .everyday: return "☀️"
        }
    }
}

/// A short script for a hard moment: what to say instead, and why it works.
/// Written for this app from widely used positive-parenting ideas.
public struct ParentingTip: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var situations: [TipSituation]
    public var insteadOf: String
    public var tryThis: String
    public var why: String
}

public enum Tips {
    /// One tip a day, the same all day.
    public static func ofTheDay(_ day: String, calendar: Calendar = Dates.calendar) -> ParentingTip {
        all[Dates.ordinal(day, calendar: calendar) % all.count]
    }

    public static func tips(for situation: TipSituation) -> [ParentingTip] {
        all.filter { $0.situations.contains(situation) }
    }

    public static let all: [ParentingTip] = [
        ParentingTip(id: "name-feeling", title: "Name the feeling", situations: [.meltdown, .siblings],
                     insteadOf: "\"Stop crying, it's not a big deal.\"",
                     tryThis: "\"You're so mad the tower fell. You worked hard on it.\"",
                     why: "Feeling understood calms the body faster than being told to calm down. Naming it also teaches the word for next time."),
        ParentingTip(id: "two-choices", title: "Offer two good choices", situations: [.notListening, .bedtime, .transitions],
                     insteadOf: "\"Put your shoes on. Now.\"",
                     tryThis: "\"Do you want to wear the red shoes or the blue ones?\"",
                     why: "Little kids crave control. Two choices you're fine with gives them some, and the job still gets done."),
        ParentingTip(id: "when-then", title: "When… then…", situations: [.notListening, .everyday],
                     insteadOf: "\"If you don't pick up, no park!\"",
                     tryThis: "\"When the blocks are in the bin, then we'll head to the park.\"",
                     why: "Same deal, but it sounds like a plan instead of a threat, so it invites cooperation."),
        ParentingTip(id: "describe", title: "Describe what you see", situations: [.notListening, .everyday],
                     insteadOf: "\"How many times do I have to tell you to hang up your coat?\"",
                     tryThis: "\"I see a coat on the floor.\"",
                     why: "Describing the problem lets them figure out what to do, which feels better than being told."),
        ParentingTip(id: "one-word", title: "Say it in one word", situations: [.notListening],
                     insteadOf: "A long lecture about brushing teeth.",
                     tryThis: "\"Teeth!\" (with a smile)",
                     why: "Short reminders are easier to hear and don't trigger the urge to tune out."),
        ParentingTip(id: "warning", title: "Give a heads-up", situations: [.transitions, .bedtime],
                     insteadOf: "\"Time to go!\" out of nowhere.",
                     tryThis: "\"Two more slides, then we're walking to the car.\" Or set a timer they can see.",
                     why: "Switching gears is hard for young brains. A warning lets them finish in their head first."),
        ParentingTip(id: "playful", title: "Make it a game", situations: [.notListening, .transitions, .bedtime],
                     insteadOf: "Repeating the same request louder.",
                     tryThis: "\"Can you hop to the bathroom like a bunny? I bet I can beat you!\"",
                     why: "Play turns a power struggle into connection, and kids move faster when it's fun."),
        ParentingTip(id: "connect-first", title: "Connect before you correct", situations: [.meltdown, .everyday],
                     insteadOf: "Calling instructions from across the room.",
                     tryThis: "Get down to their level, touch their shoulder, wait for eye contact, then talk.",
                     why: "A kid has to feel connected before they can listen. It's faster than repeating yourself."),
        ParentingTip(id: "stay-close", title: "Stay close in a meltdown", situations: [.meltdown],
                     insteadOf: "\"Go to your room until you can be nice.\"",
                     tryThis: "\"I'm right here. I'll help you when you're ready.\" Then say less.",
                     why: "Mid-meltdown, the thinking brain is offline. Your calm presence is what helps them reset."),
        ParentingTip(id: "no-compare", title: "Skip the comparisons", situations: [.siblings],
                     insteadOf: "\"Why can't you sit nicely like your brother?\"",
                     tryThis: "Speak only to the child in front of you: \"Your plate is still full. Want to try one bite?\"",
                     why: "Comparisons, even good ones, set siblings up as rivals."),
        ParentingTip(id: "sibling-fight", title: "Referee, don't judge", situations: [.siblings],
                     insteadOf: "\"Who started it?\"",
                     tryThis: "\"Two kids and one truck. That's a hard problem. What could we do?\"",
                     why: "Describing both sides and asking for ideas teaches problem-solving instead of tattling."),
        ParentingTip(id: "special-time", title: "Ten minutes of special time", situations: [.siblings, .everyday],
                     insteadOf: "Only one-on-one time when something's wrong.",
                     tryThis: "Ten minutes a day with each kid, phone away, where they choose what to play.",
                     why: "Kids who get regular one-on-one attention seek it less through misbehavior. Especially helpful after a new baby."),
        ParentingTip(id: "praise-effort", title: "Praise the effort", situations: [.everyday],
                     insteadOf: "\"You're so smart!\"",
                     tryThis: "\"You kept trying until that puzzle piece fit!\"",
                     why: "Praising effort builds kids who keep at hard things instead of avoiding them."),
        ParentingTip(id: "division", title: "You decide what, they decide how much", situations: [.mealtime],
                     insteadOf: "\"Three more bites, then you can be done.\"",
                     tryThis: "Serve the meal (with one food they usually eat), then let them decide what and how much to eat from it.",
                     why: "Pressure, even praise for eating, tends to backfire. Kids who are trusted to listen to their hunger are less picky over time."),
        ParentingTip(id: "new-food", title: "No-pressure tries", situations: [.mealtime],
                     insteadOf: "\"Just try it, you'll like it.\"",
                     tryThis: "Put a little of the new food on the plate and eat it yourself. \"You don't have to eat it. You can lick it or smell it.\"",
                     why: "It can take 10 or more exposures before a kid accepts a food. Seeing, touching and smelling count."),
        ParentingTip(id: "bedtime-routine", title: "Same routine, same order", situations: [.bedtime],
                     insteadOf: "A different bedtime every night.",
                     tryThis: "Bath, pajamas, teeth, two books, song, lights out. Make a picture chart they can follow.",
                     why: "Predictable steps cue the body for sleep and cut down on negotiating."),
        ParentingTip(id: "goodbye", title: "Short, sure goodbyes", situations: [.dropoff, .transitions],
                     insteadOf: "Sneaking out, or lingering through tears.",
                     tryThis: "A goodbye ritual (two hugs and a high-five), then \"I'll see you after nap time!\" and go.",
                     why: "A quick, confident goodbye tells them school is safe. Most kids settle within minutes."),
        ParentingTip(id: "after-school", title: "Ask better questions", situations: [.dropoff, .everyday],
                     insteadOf: "\"How was school?\" (\"Fine.\")",
                     tryThis: "\"What made you laugh today?\" or \"Who did you sit by at snack?\"",
                     why: "Specific questions are easier to answer. Ask at bedtime, when kids tend to open up."),
        ParentingTip(id: "yes-space", title: "Find a way to say yes", situations: [.notListening, .everyday],
                     insteadOf: "\"No, you can't have a cookie.\"",
                     tryThis: "\"Yes, you can have a cookie after dinner. Let's put it on the counter so it waits for you.\"",
                     why: "Same limit, but \"yes, later\" lands softer than \"no\"."),
        ParentingTip(id: "repair", title: "Repair after you yell", situations: [.everyday, .meltdown],
                     insteadOf: "Moving on like it didn't happen.",
                     tryThis: "\"I yelled and that was scary. I'm sorry. I was frustrated. Next time I'll take a breath.\"",
                     why: "Every parent loses it sometimes. Repairing teaches kids how to make things right."),
    ]
}
