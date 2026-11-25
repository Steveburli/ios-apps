import Foundation

public enum MilestoneDomain: String, CaseIterable, Identifiable {
    case social, language, thinking, movement

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .social: return "Social & emotional"
        case .language: return "Language & communication"
        case .thinking: return "Thinking & problem-solving"
        case .movement: return "Movement & physical"
        }
    }

    public var emoji: String {
        switch self {
        case .social: return "💛"
        case .language: return "💬"
        case .thinking: return "🧩"
        case .movement: return "🏃"
        }
    }
}

public enum MilestoneStatus: String, Codable, CaseIterable, Identifiable {
    case yes, notYet, unsure

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .yes: return "Yes"
        case .notYet: return "Not yet"
        case .unsure: return "Not sure"
        }
    }
}

public struct Milestone: Identifiable, Hashable {
    public var id: String
    public var months: Int
    public var domain: MilestoneDomain
    public var text: String
}

/// Developmental milestones by checkup age, paraphrased from the CDC's
/// "Learn the Signs. Act Early." checklists (2022 revision, public domain):
/// things most children (75% or more) can do by each age.
public enum Milestones {
    public static let ages = [2, 4, 6, 9, 12, 15, 18, 24, 30, 36, 48, 60]

    public static func ageTitle(_ months: Int) -> String {
        months < 24 ? "\(months) months" : (months % 12 == 0 ? "\(months / 12) years" : "\(months / 12)½ years")
    }

    /// The checklist to look at now: the latest checkup age reached, or the
    /// first one for a newborn.
    public static func current(ageMonths: Int) -> Int {
        ages.last { $0 <= ageMonths } ?? ages[0]
    }

    /// The next checkup age after the current one, if any.
    public static func upcoming(ageMonths: Int) -> Int? {
        ages.first { $0 > ageMonths }
    }

    public static func list(for months: Int) -> [Milestone] {
        all.filter { $0.months == months }
    }

    /// How many of an age's milestones are marked yes, and how many there are.
    public static func progress(months: Int, statuses: [String: MilestoneStatus]) -> (done: Int, total: Int) {
        let items = list(for: months)
        return (items.filter { statuses[$0.id] == .yes }.count, items.count)
    }

    /// Milestones from earlier ages still marked "not yet", worth raising at a checkup.
    public static func toMention(ageMonths: Int, statuses: [String: MilestoneStatus]) -> [Milestone] {
        all.filter { $0.months < current(ageMonths: ageMonths) && statuses[$0.id] == .notYet }
    }

    private static func make(_ months: Int, _ items: [(MilestoneDomain, String)]) -> [Milestone] {
        items.enumerated().map { index, item in
            Milestone(id: "m\(months)-\(index)", months: months, domain: item.0, text: item.1)
        }
    }

    public static let all: [Milestone] = [
        make(2, [
            (.social, "Calms down when spoken to or picked up"),
            (.social, "Looks at your face"),
            (.social, "Seems happy to see you when you walk up"),
            (.social, "Smiles when you talk to or smile at them"),
            (.language, "Makes sounds other than crying"),
            (.language, "Reacts to loud sounds"),
            (.thinking, "Watches you as you move"),
            (.thinking, "Looks at a toy for several seconds"),
            (.movement, "Holds head up when on tummy"),
            (.movement, "Moves both arms and both legs"),
            (.movement, "Opens hands briefly"),
        ]),
        make(4, [
            (.social, "Smiles on their own to get your attention"),
            (.social, "Chuckles when you try to make them laugh"),
            (.social, "Looks at you, moves or makes sounds to get or keep your attention"),
            (.language, "Makes cooing sounds like \"oooo\" and \"aahh\""),
            (.language, "Makes sounds back when you talk to them"),
            (.language, "Turns head toward the sound of your voice"),
            (.thinking, "Opens mouth when they see breast or bottle, if hungry"),
            (.thinking, "Looks at their hands with interest"),
            (.movement, "Holds head steady without support when you hold them"),
            (.movement, "Holds a toy when you put it in their hand"),
            (.movement, "Uses an arm to swing at toys"),
            (.movement, "Brings hands to mouth"),
            (.movement, "Pushes up onto elbows or forearms when on tummy"),
        ]),
        make(6, [
            (.social, "Knows familiar people"),
            (.social, "Likes to look at themselves in a mirror"),
            (.social, "Laughs"),
            (.language, "Takes turns making sounds with you"),
            (.language, "Blows \"raspberries\""),
            (.language, "Makes squealing noises"),
            (.thinking, "Puts things in their mouth to explore them"),
            (.thinking, "Reaches to grab a toy they want"),
            (.thinking, "Closes lips to show they don't want more food"),
            (.movement, "Rolls from tummy to back"),
            (.movement, "Pushes up with straight arms when on tummy"),
            (.movement, "Leans on hands to support themselves when sitting"),
        ]),
        make(9, [
            (.social, "Is shy, clingy or fearful around strangers"),
            (.social, "Shows several facial expressions, like happy, sad, angry and surprised"),
            (.social, "Looks when you call their name"),
            (.social, "Reacts when you leave (looks, reaches for you or cries)"),
            (.social, "Smiles or laughs when you play peekaboo"),
            (.language, "Makes lots of different sounds like \"mamamama\" and \"babababa\""),
            (.language, "Lifts arms up to be picked up"),
            (.thinking, "Looks for objects when dropped out of sight"),
            (.thinking, "Bangs two things together"),
            (.movement, "Gets to a sitting position by themselves"),
            (.movement, "Moves things from one hand to the other"),
            (.movement, "Uses fingers to \"rake\" food toward themselves"),
            (.movement, "Sits without support"),
        ]),
        make(12, [
            (.social, "Plays games with you, like pat-a-cake"),
            (.language, "Waves \"bye-bye\""),
            (.language, "Calls a parent \"mama\", \"dada\" or another special name"),
            (.language, "Understands \"no\" (pauses or stops when you say it)"),
            (.thinking, "Puts something in a container, like a block in a cup"),
            (.thinking, "Looks for things they see you hide"),
            (.movement, "Pulls up to stand"),
            (.movement, "Walks, holding on to furniture"),
            (.movement, "Drinks from a cup without a lid, as you hold it"),
            (.movement, "Picks things up between thumb and pointer finger"),
        ]),
        make(15, [
            (.social, "Copies other children while playing"),
            (.social, "Shows you an object they like"),
            (.social, "Claps when excited"),
            (.social, "Hugs a stuffed doll or other toy"),
            (.social, "Shows you affection (hugs, cuddles or kisses)"),
            (.language, "Tries to say one or two words besides \"mama\" or \"dada\""),
            (.language, "Looks at a familiar object when you name it"),
            (.language, "Follows directions given with a gesture and words"),
            (.language, "Points to ask for something or to get help"),
            (.thinking, "Tries to use things the right way, like a phone, cup or book"),
            (.thinking, "Stacks at least two small objects, like blocks"),
            (.movement, "Takes a few steps on their own"),
            (.movement, "Uses fingers to feed themselves some food"),
        ]),
        make(18, [
            (.social, "Moves away from you but looks to make sure you're close by"),
            (.social, "Points to show you something interesting"),
            (.social, "Puts hands out for you to wash them"),
            (.social, "Looks at a few pages in a book with you"),
            (.social, "Helps you dress them by pushing an arm through a sleeve or lifting a foot"),
            (.language, "Tries to say three or more words besides \"mama\" or \"dada\""),
            (.language, "Follows one-step directions without gestures, like \"Give it to me\""),
            (.thinking, "Copies you doing chores, like sweeping"),
            (.thinking, "Plays with toys in a simple way, like pushing a toy car"),
            (.movement, "Walks without holding on"),
            (.movement, "Scribbles"),
            (.movement, "Drinks from a cup without a lid and may spill sometimes"),
            (.movement, "Feeds themselves with fingers"),
            (.movement, "Tries to use a spoon"),
            (.movement, "Climbs on and off a couch or chair without help"),
        ]),
        make(24, [
            (.social, "Notices when others are hurt or upset"),
            (.social, "Looks at your face to see how to react in a new situation"),
            (.language, "Points to things in a book when you ask"),
            (.language, "Says at least two words together, like \"More milk\""),
            (.language, "Points to at least two body parts when you ask"),
            (.language, "Uses more gestures than waving and pointing, like blowing a kiss or nodding"),
            (.thinking, "Holds something in one hand while using the other"),
            (.thinking, "Tries to use switches, knobs or buttons on a toy"),
            (.thinking, "Plays with more than one toy at the same time"),
            (.movement, "Kicks a ball"),
            (.movement, "Runs"),
            (.movement, "Walks (not climbs) up a few stairs, with or without help"),
            (.movement, "Eats with a spoon"),
        ]),
        make(30, [
            (.social, "Plays next to other children and sometimes plays with them"),
            (.social, "Shows you what they can do by saying \"Look at me!\""),
            (.social, "Follows simple routines when told, like helping pick up toys"),
            (.language, "Says about 50 words"),
            (.language, "Says two or more words together, with one action word, like \"Doggie run\""),
            (.language, "Names things in a book when you point and ask"),
            (.language, "Says words like \"I\", \"me\" or \"we\""),
            (.thinking, "Uses things to pretend, like feeding a block to a doll"),
            (.thinking, "Shows simple problem-solving, like standing on a stool to reach something"),
            (.thinking, "Follows two-step instructions, like \"Put the toy down and close the door\""),
            (.thinking, "Knows at least one color"),
            (.movement, "Uses hands to twist things, like turning doorknobs or unscrewing lids"),
            (.movement, "Takes some clothes off by themselves"),
            (.movement, "Jumps off the ground with both feet"),
            (.movement, "Turns book pages, one at a time, when you read"),
        ]),
        make(36, [
            (.social, "Calms down within 10 minutes after you leave, like at drop-off"),
            (.social, "Notices other children and joins them to play"),
            (.language, "Talks with you in a conversation of at least two back-and-forth exchanges"),
            (.language, "Asks \"who\", \"what\", \"where\" or \"why\" questions"),
            (.language, "Says what action is happening in a picture or book"),
            (.language, "Says their first name when asked"),
            (.language, "Talks well enough for others to understand, most of the time"),
            (.thinking, "Draws a circle when you show them how"),
            (.thinking, "Avoids touching hot things when you warn them"),
            (.movement, "Strings items together, like large beads or macaroni"),
            (.movement, "Puts on some clothes by themselves"),
            (.movement, "Uses a fork"),
        ]),
        make(48, [
            (.social, "Pretends to be something else during play, like a teacher, superhero or dog"),
            (.social, "Asks to go play with children if none are around"),
            (.social, "Comforts others who are hurt or sad"),
            (.social, "Avoids danger, like not jumping from tall heights"),
            (.social, "Likes to be a \"helper\""),
            (.social, "Changes behavior based on where they are (library, playground)"),
            (.language, "Says sentences with four or more words"),
            (.language, "Says some words from a song, story or nursery rhyme"),
            (.language, "Talks about at least one thing that happened during the day"),
            (.language, "Answers simple questions, like \"What is a coat for?\""),
            (.thinking, "Names a few colors of items"),
            (.thinking, "Tells what comes next in a well-known story"),
            (.thinking, "Draws a person with three or more body parts"),
            (.movement, "Catches a large ball most of the time"),
            (.movement, "Serves themselves food or pours water, with adult supervision"),
            (.movement, "Unbuttons some buttons"),
            (.movement, "Holds a crayon or pencil between fingers and thumb (not a fist)"),
        ]),
        make(60, [
            (.social, "Follows rules or takes turns when playing games with other children"),
            (.social, "Sings, dances or acts for you"),
            (.social, "Does simple chores at home, like matching socks or clearing the table"),
            (.language, "Tells a story they heard or made up with at least two events"),
            (.language, "Answers simple questions about a book or story after you read it"),
            (.language, "Keeps a conversation going with more than three back-and-forth exchanges"),
            (.language, "Uses or recognizes simple rhymes (bat–cat, ball–tall)"),
            (.thinking, "Counts to 10"),
            (.thinking, "Names some numbers between 1 and 5 when you point to them"),
            (.thinking, "Uses words about time, like \"yesterday\", \"tomorrow\", \"morning\" or \"night\""),
            (.thinking, "Pays attention for 5 to 10 minutes during activities"),
            (.thinking, "Writes some letters in their name"),
            (.thinking, "Names some letters when you point to them"),
            (.movement, "Buttons some buttons"),
            (.movement, "Hops on one foot"),
        ]),
    ].flatMap { $0 }
}
