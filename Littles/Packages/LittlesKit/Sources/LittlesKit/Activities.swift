import Foundation

public enum Place: String, Codable, CaseIterable, Identifiable {
    case inside, outside, either
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .inside: return "Inside"
        case .outside: return "Outside"
        case .either: return "Anywhere"
        }
    }
}

public enum Energy: String, Codable, CaseIterable, Identifiable {
    case calm, active
    public var id: String { rawValue }
    public var title: String { self == .calm ? "Calm" : "Active" }
}

public enum Skill: String, Codable, CaseIterable, Identifiable {
    case movement, language, senses, creative, thinking, social, lifeSkills

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .movement: return "Movement"
        case .language: return "Language"
        case .senses: return "Senses"
        case .creative: return "Creative"
        case .thinking: return "Thinking"
        case .social: return "Feelings & friends"
        case .lifeSkills: return "Life skills"
        }
    }
}

public struct Activity: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var emoji: String
    public var minMonths: Int
    public var maxMonths: Int
    public var minutes: Int
    public var place: Place
    public var energy: Energy
    /// 0 none, 1 some, 2 a lot.
    public var mess: Int
    public var skills: [Skill]
    public var materials: [String]
    public var steps: [String]
    public var why: String

    public init(_ id: String, _ title: String, _ emoji: String, ages: ClosedRange<Int>, minutes: Int, place: Place,
                energy: Energy, mess: Int = 0, skills: [Skill], materials: [String] = [], steps: [String], why: String) {
        self.id = id
        self.title = title
        self.emoji = emoji
        minMonths = ages.lowerBound
        maxMonths = ages.upperBound
        self.minutes = minutes
        self.place = place
        self.energy = energy
        self.mess = mess
        self.skills = skills
        self.materials = materials
        self.steps = steps
        self.why = why
    }

    public func fits(ageMonths: Int) -> Bool {
        ageMonths >= minMonths && ageMonths <= maxMonths
    }

    public var ageLabel: String {
        maxMonths >= 72 ? "\(Age.short(months: minMonths)) +" : "\(Age.short(months: minMonths))–\(Age.short(months: maxMonths))"
    }
}

/// An activity someone did, with which kids, and whether it was a hit.
public struct ActivityDone: Codable, Identifiable, Hashable {
    public var id: String
    public var activityID: String
    public var day: String
    public var kidIDs: [String]
    public var hit: Bool

    public init(id: String = UUID().uuidString, activityID: String, day: String, kidIDs: [String], hit: Bool = true) {
        self.id = id
        self.activityID = activityID
        self.day = day
        self.kidIDs = kidIDs
        self.hit = hit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        activityID = try c.decodeIfPresent(String.self, forKey: .activityID) ?? ""
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        kidIDs = try c.decodeIfPresent([String].self, forKey: .kidIDs) ?? []
        hit = try c.decodeIfPresent(Bool.self, forKey: .hit) ?? true
    }
}

public struct ActivityFilter: Equatable {
    /// Every chosen kid's age must fit, so "both" finds things they can do together.
    public var agesMonths: [Int]
    public var maxMinutes: Int?
    public var place: Place?
    public var energy: Energy?
    public var maxMess: Int
    public var skill: Skill?

    public init(agesMonths: [Int], maxMinutes: Int? = nil, place: Place? = nil, energy: Energy? = nil,
                maxMess: Int = 2, skill: Skill? = nil) {
        self.agesMonths = agesMonths
        self.maxMinutes = maxMinutes
        self.place = place
        self.energy = energy
        self.maxMess = maxMess
        self.skill = skill
    }
}

public enum ActivityPicker {
    public static func matches(_ filter: ActivityFilter, in list: [Activity] = ActivityLibrary.all) -> [Activity] {
        list.filter { activity in
            if !filter.agesMonths.allSatisfy({ activity.fits(ageMonths: $0) }) { return false }
            if let max = filter.maxMinutes, activity.minutes > max { return false }
            if let place = filter.place, activity.place != .either, activity.place != place { return false }
            if let energy = filter.energy, activity.energy != energy { return false }
            if activity.mess > filter.maxMess { return false }
            if let skill = filter.skill, !activity.skills.contains(skill) { return false }
            return true
        }
    }

    /// Matches in a useful order: favorites and hits first, then things not
    /// done lately, then the rest. Stable for a given day.
    public static func ranked(_ filter: ActivityFilter, done: [ActivityDone], favorites: [String], today: String,
                              in list: [Activity] = ActivityLibrary.all, calendar: Calendar = Dates.calendar) -> [Activity] {
        let found = matches(filter, in: list)
        let recent = Set(done.filter { Dates.ordinal($0.day, calendar: calendar) >= Dates.ordinal(today, calendar: calendar) - 3 }
            .map { $0.activityID })
        let favoriteSet = Set(favorites)
        let day = Dates.ordinal(today, calendar: calendar)
        func score(_ activity: Activity, _ index: Int) -> Int {
            var value = 0
            if favoriteSet.contains(activity.id) { value += 100 }
            if recent.contains(activity.id) { value -= 200 }
            // A daily shuffle so the same few don't always lead.
            value += ((index + day) * 37) % 50
            return value
        }
        return found.enumerated()
            .map { (activity: $0.element, score: score($0.element, $0.offset)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.activity.id < $1.activity.id }
            .map { $0.activity }
    }

    /// Today's one idea for the kids together, or nil when nothing fits both.
    public static func todaysPick(ages: [Int], done: [ActivityDone], favorites: [String], today: String,
                                  calendar: Calendar = Dates.calendar) -> Activity? {
        ranked(ActivityFilter(agesMonths: ages), done: done, favorites: favorites, today: today, calendar: calendar).first
    }
}

/// The app's own library of things to do with little kids.
public enum ActivityLibrary {
    public static func activity(_ id: String) -> Activity? {
        all.first { $0.id == id }
    }

    public static let all: [Activity] = [
        // Babies
        Activity("tummy-mirror", "Tummy time mirror", "🪞", ages: 0...6, minutes: 5, place: .inside, energy: .calm,
                 skills: [.movement, .social], materials: ["Baby-safe mirror or your phone's selfie camera"],
                 steps: ["Lay baby on a blanket on their tummy.", "Prop a mirror in front of them.", "Get down at eye level and talk about the baby in the mirror."],
                 why: "Faces are the most interesting thing to a baby, and lifting the head to look builds neck and back strength."),
        Activity("narrate", "Narrate your day", "🗣️", ages: 0...18, minutes: 10, place: .either, energy: .calm,
                 skills: [.language],
                 steps: ["While you change, feed or cook, say what you're doing.", "Pause after a coo or babble, like it's their turn to talk."],
                 why: "Back-and-forth talk, even before words, is one of the strongest builders of language."),
        Activity("high-contrast", "High-contrast cards", "🔲", ages: 0...4, minutes: 5, place: .inside, energy: .calm,
                 skills: [.senses], materials: ["Black-and-white pictures or a book"],
                 steps: ["Hold a card 8–12 inches from baby's face.", "Move it slowly side to side and watch their eyes follow."],
                 why: "Young babies see bold contrast best; tracking builds eye control."),
        Activity("crinkle", "Crinkle and shake", "🎵", ages: 2...10, minutes: 10, place: .inside, energy: .calm,
                 skills: [.senses, .thinking], materials: ["A crinkly fabric, a rattle or a sealed bottle of rice"],
                 steps: ["Shake on one side of baby, then the other.", "Let them grab and shake it themselves."],
                 why: "Finding where a sound comes from, and learning they can make it, is early cause and effect."),
        Activity("peekaboo", "Peekaboo", "🙈", ages: 4...18, minutes: 5, place: .either, energy: .calm,
                 skills: [.social, .thinking], materials: ["A light cloth"],
                 steps: ["Hide your face behind your hands or a cloth.", "Pop out with a big \"Peekaboo!\"", "Try hiding a toy under the cloth next."],
                 why: "Teaches that things still exist when out of sight, and it's a big early laugh."),
        Activity("sensory-bottles", "Sensory bottles", "🧪", ages: 4...24, minutes: 15, place: .inside, energy: .calm,
                 skills: [.senses], materials: ["Clear plastic bottle", "Water, glitter, beads or pom-poms", "Strong tape or glue for the cap"],
                 steps: ["Fill a bottle with water and a few floaty things.", "Glue or tape the cap shut.", "Roll it, shake it, watch it settle."],
                 why: "Calming to watch and great for rolling and chasing once they crawl."),
        Activity("bubbles-baby", "Bubbles", "🫧", ages: 4...72, minutes: 10, place: .either, energy: .active, mess: 1,
                 skills: [.senses, .movement], materials: ["Bubble solution"],
                 steps: ["Blow bubbles for baby to watch and reach for.", "Older kids chase, pop, stomp or clap them.", "Call out \"big\", \"small\", \"up\", \"pop\"."],
                 why: "Tracking, reaching, chasing and lots of simple words, for every age at once."),
        Activity("tissue-pull", "Tissue box pull", "📦", ages: 7...18, minutes: 10, place: .inside, energy: .calm,
                 skills: [.thinking, .movement], materials: ["Empty tissue box", "Scarves or fabric scraps"],
                 steps: ["Stuff scarves into the empty box.", "Let baby pull them out, one by one.", "Stuff them back in together."],
                 why: "The pull they want to do with real tissues, plus pincer grasp practice."),
        Activity("muffin-tin", "Muffin tin sort", "🧁", ages: 8...30, minutes: 10, place: .inside, energy: .calm,
                 skills: [.thinking, .movement], materials: ["Muffin tin", "Balls, blocks or big pom-poms"],
                 steps: ["Show how to drop one thing into each cup.", "Older kids sort by color or count into each cup."],
                 why: "In and out, then sorting and counting: the same toy grows with them."),
        Activity("crawl-tunnel", "Cushion obstacle course", "🛋️", ages: 8...48, minutes: 15, place: .inside, energy: .active,
                 skills: [.movement], materials: ["Couch cushions, pillows, a blanket over chairs"],
                 steps: ["Lay out cushions to climb over and a blanket tunnel to crawl through.", "Crawlers explore; walkers climb; preschoolers race the course."],
                 why: "Climbing and crawling build strength, balance and body awareness."),
        Activity("pots-pans", "Kitchen band", "🥁", ages: 6...48, minutes: 10, place: .inside, energy: .active,
                 skills: [.senses, .creative], materials: ["Pots, pans, wooden spoons"],
                 steps: ["Hand out spoons and upside-down pots.", "Play loud, then quiet, fast, then slow.", "Freeze when the music stops."],
                 why: "Loud and soft, fast and slow, start and stop: rhythm and self-control in one game."),
        Activity("board-books", "Lap reading", "📚", ages: 0...72, minutes: 10, place: .either, energy: .calm,
                 skills: [.language, .social], materials: ["Picture books"],
                 steps: ["Snuggle up with a book.", "Point and name pictures for babies; ask \"What do you see?\" for toddlers.", "With preschoolers, pause and ask what happens next."],
                 why: "Reading together every day is linked with bigger vocabularies and an easier start at school."),
        Activity("water-play", "Water table", "💦", ages: 9...72, minutes: 20, place: .outside, energy: .calm, mess: 2,
                 skills: [.senses, .thinking], materials: ["Bin of water", "Cups, funnels, spoons, bath toys"],
                 steps: ["Set out a shallow bin of water and things that pour.", "Ask what sinks and what floats.", "Always stay within arm's reach."],
                 why: "Pouring, filling and floating are early science and great for hand control."),

        // Toddlers
        Activity("sticky-wall", "Sticky wall", "🧻", ages: 10...36, minutes: 15, place: .inside, energy: .calm, mess: 0,
                 skills: [.senses, .movement, .creative], materials: ["Contact paper", "Tape", "Paper scraps, feathers, leaves"],
                 steps: ["Tape contact paper sticky side out on a wall at their height.", "Hand them things to press on and peel off."],
                 why: "Pressing and peeling builds finger strength for later drawing."),
        Activity("ball-roll", "Roll it back", "⚽", ages: 8...36, minutes: 10, place: .either, energy: .active,
                 skills: [.movement, .social], materials: ["A soft ball"],
                 steps: ["Sit facing each other, legs in a V.", "Roll the ball back and forth.", "Older toddlers try to kick it or throw it into a basket."],
                 why: "Turn-taking is a first social skill; tracking a rolling ball builds coordination."),
        Activity("bubble-wrap", "Bubble wrap stomp", "👣", ages: 12...60, minutes: 10, place: .inside, energy: .active,
                 skills: [.movement, .senses], materials: ["Bubble wrap", "Tape"],
                 steps: ["Tape bubble wrap to the floor.", "Stomp, jump, tiptoe and crawl across it."],
                 why: "A satisfying way to get big energy out on a rainy day."),
        Activity("color-hunt", "Color hunt", "🎨", ages: 18...72, minutes: 15, place: .either, energy: .active,
                 skills: [.language, .thinking], materials: ["A basket"],
                 steps: ["Pick a color.", "Find things that color around the house or yard and put them in the basket.", "Count them up at the end."],
                 why: "Color words, counting and a reason to run around."),
        Activity("playdough", "Homemade playdough", "🟣", ages: 18...72, minutes: 30, place: .inside, energy: .calm, mess: 1,
                 skills: [.creative, .movement, .senses], materials: ["1 cup flour", "½ cup salt", "1 tbsp oil", "½ cup water", "Food coloring"],
                 steps: ["Mix together, adding water until it's soft (salt makes it taste bad, so it won't get eaten much).", "Roll snakes, make pancakes, cut with a plastic knife or cookie cutters."],
                 why: "Squeezing and rolling builds the hand muscles needed for holding a pencil."),
        Activity("animal-walks", "Animal walks", "🐸", ages: 18...72, minutes: 10, place: .either, energy: .active,
                 skills: [.movement, .language],
                 steps: ["Call out an animal: frog jumps, bear crawls, crab walks, flamingo stands.", "Take turns choosing the next animal."],
                 why: "Big-muscle work and silly fun; a good reset before nap or dinner."),
        Activity("sink-float", "Sink or float", "🛁", ages: 24...72, minutes: 15, place: .inside, energy: .calm, mess: 1,
                 skills: [.thinking, .language], materials: ["Bin or tub of water", "Spoon, cork, coin, leaf, toy, crayon"],
                 steps: ["Hold up one thing and ask \"Will it sink or float?\"", "Drop it in and see.", "Make two piles: sinkers and floaters."],
                 why: "Guessing, testing and sorting is the scientific method at toddler size."),
        Activity("helper", "Little helper", "🧺", ages: 15...72, minutes: 15, place: .inside, energy: .calm,
                 skills: [.lifeSkills, .social],
                 steps: ["Give a real job: match socks, wipe the table, put spoons away, feed the pet.", "Thank them for the help, specifically."],
                 why: "Toddlers want to help; real jobs build confidence and the habit of pitching in."),
        Activity("puddle-jump", "Puddle walk", "☔", ages: 15...72, minutes: 20, place: .outside, energy: .active, mess: 2,
                 skills: [.movement, .senses], materials: ["Rain boots"],
                 steps: ["After rain, head out in boots.", "Jump in puddles, float leaves, look for worms."],
                 why: "Fresh air, big movement and a world of new things to name."),
        Activity("nature-walk", "Nature scavenger hunt", "🍂", ages: 18...72, minutes: 30, place: .outside, energy: .active,
                 skills: [.thinking, .language, .senses], materials: ["A bag", "A list: leaf, stick, rock, flower, something rough, something smooth"],
                 steps: ["Walk the block or a park with the list.", "Check off each find.", "Line them up at home, smallest to biggest."],
                 why: "Describing words (rough, smooth, tall), counting and comparing."),
        Activity("dance-freeze", "Freeze dance", "🕺", ages: 15...72, minutes: 10, place: .inside, energy: .active,
                 skills: [.movement, .social], materials: ["Music"],
                 steps: ["Play music and dance.", "Pause it: everyone freezes.", "Try freezing in a funny shape."],
                 why: "Stopping on cue is practice for impulse control, which preschool asks a lot of."),
        Activity("sticker-line", "Sticker lines", "⭐", ages: 18...48, minutes: 15, place: .inside, energy: .calm,
                 skills: [.movement, .thinking], materials: ["Stickers", "Paper and a marker"],
                 steps: ["Draw straight, wavy and zigzag lines.", "Have them put stickers along each line."],
                 why: "Peeling stickers is great pincer practice, and following lines prepares for tracing."),
        Activity("tape-road", "Tape roads", "🚗", ages: 18...60, minutes: 20, place: .inside, energy: .calm,
                 skills: [.creative, .thinking], materials: ["Painter's tape", "Toy cars"],
                 steps: ["Tape roads across the floor with curves and a parking lot.", "Drive cars along them, park by color, build a car wash from a box."],
                 why: "Pretend play plus following paths; the roads can stay up for days."),
        Activity("pouring", "Pouring station", "🫗", ages: 18...48, minutes: 15, place: .either, energy: .calm, mess: 1,
                 skills: [.lifeSkills, .movement], materials: ["Small pitcher", "Cups", "Dry rice or water", "A tray"],
                 steps: ["Put everything on a tray.", "Show how to pour slowly from pitcher to cup.", "Then pour back. Spills are part of it."],
                 why: "Pouring their own water is a real skill preschools work on."),

        // Preschoolers
        Activity("letter-hunt", "Letter hunt", "🔤", ages: 36...72, minutes: 15, place: .either, energy: .active,
                 skills: [.language, .thinking],
                 steps: ["Pick the first letter of their name.", "Find it on signs, boxes and books.", "Then find something that starts with that sound."],
                 why: "Recognizing letters and their sounds is a big pre-reading step."),
        Activity("story-dice", "Make up a story", "📖", ages: 36...72, minutes: 10, place: .either, energy: .calm,
                 skills: [.language, .creative],
                 steps: ["Start: \"Once upon a time there was a…\" and let them finish.", "Take turns adding one sentence.", "Ask \"And then what happened?\""],
                 why: "Storytelling builds the sequence and vocabulary skills behind reading."),
        Activity("feelings-faces", "Feelings faces", "😀", ages: 30...72, minutes: 10, place: .either, energy: .calm,
                 skills: [.social, .language], materials: ["A mirror (optional)"],
                 steps: ["Make a face (happy, mad, sad, surprised, scared) and have them name it.", "Swap: they make one, you guess.", "Ask \"When do you feel that way?\""],
                 why: "Naming feelings is the first step to handling them."),
        Activity("cooking", "Cook together", "🧑‍🍳", ages: 24...72, minutes: 30, place: .inside, energy: .calm, mess: 2,
                 skills: [.lifeSkills, .thinking, .senses], materials: ["A simple recipe: muffins, pancakes, fruit salad"],
                 steps: ["Give them jobs: pour, stir, mash, tear, count scoops.", "Talk about measuring: full, half, more, less.", "Eat what you made."],
                 why: "Kids are more likely to try foods they helped make, and it's math and science in disguise."),
        Activity("counting-jumps", "Count and jump", "🔢", ages: 30...72, minutes: 10, place: .either, energy: .active,
                 skills: [.thinking, .movement],
                 steps: ["Roll a die or hold up fingers.", "Jump, clap or hop that many times.", "Count out loud together."],
                 why: "Matching a number to an amount is a key early math skill."),
        Activity("cut-practice", "Scissor practice", "✂️", ages: 36...72, minutes: 15, place: .inside, energy: .calm, mess: 1,
                 skills: [.movement, .lifeSkills], materials: ["Kid scissors", "Junk mail or playdough snakes", "Paper strips with lines"],
                 steps: ["Start by snipping playdough snakes or narrow paper strips.", "Move on to cutting along straight lines.", "\"Thumb on top, like a thumbs-up.\""],
                 why: "Preschool teachers love kids who can snip; it strengthens the hand for writing."),
        Activity("chalk-art", "Sidewalk chalk", "🖍️", ages: 24...72, minutes: 20, place: .outside, energy: .calm, mess: 1,
                 skills: [.creative, .movement], materials: ["Chalk"],
                 steps: ["Draw together; trace each other's shadows or bodies.", "Draw a hopscotch or a road for bikes.", "Spray with water to make the colors pop."],
                 why: "Big arm movements on the ground build shoulder strength for writing."),
        Activity("hopscotch", "Hopscotch", "🦘", ages: 36...72, minutes: 15, place: .outside, energy: .active,
                 skills: [.movement, .thinking], materials: ["Chalk", "A small stone"],
                 steps: ["Draw squares numbered 1–8.", "Toss the stone, hop over its square, and back.", "Younger kids can just jump square to square."],
                 why: "Hopping on one foot is a 4–5-year milestone; numbers come along for free."),
        Activity("pretend-store", "Play store", "🏪", ages: 30...72, minutes: 20, place: .inside, energy: .calm,
                 skills: [.social, .thinking, .language], materials: ["Pantry items", "Paper money or coins", "A bag"],
                 steps: ["Set up a shelf of cans and boxes.", "Take turns being shopper and cashier.", "Count the items and pay."],
                 why: "Role play builds language, turn-taking and early counting."),
        Activity("fort", "Build a fort", "🏰", ages: 24...72, minutes: 30, place: .inside, energy: .calm,
                 skills: [.creative, .thinking, .social], materials: ["Blankets", "Chairs", "Clothespins", "A flashlight"],
                 steps: ["Build together: drape, clip and prop.", "Read or have a snack inside with a flashlight."],
                 why: "Planning, problem-solving and a cozy reset for everyone."),
        Activity("matching-memory", "Memory game", "🃏", ages: 36...72, minutes: 15, place: .inside, energy: .calm,
                 skills: [.thinking, .social], materials: ["Matching cards (or two sets of the same stickers on index cards)"],
                 steps: ["Start with 4–6 pairs face down.", "Flip two at a time; keep a match.", "Add pairs as they get good."],
                 why: "Working memory and taking turns, with a natural way to scale it up."),
        Activity("garden", "Plant a seed", "🌱", ages: 30...72, minutes: 20, place: .either, energy: .calm, mess: 2,
                 skills: [.thinking, .lifeSkills], materials: ["Cup with soil", "Bean or sunflower seeds", "Water"],
                 steps: ["Poke a hole, drop a seed, cover it.", "Water a little each day.", "Measure it with blocks as it grows."],
                 why: "Patience, caring for something and watching change over days."),
        Activity("bike-ride", "Balance bike ride", "🚲", ages: 24...72, minutes: 30, place: .outside, energy: .active,
                 skills: [.movement], materials: ["Balance bike or trike", "Helmet"],
                 steps: ["Helmet on.", "Push along, then glide with feet up.", "Set a goal: the next driveway, the stop sign."],
                 why: "Balance bikes teach balance first, which makes pedal bikes easier later."),
        Activity("big-little", "Big kid teaches", "🤝", ages: 30...72, minutes: 10, place: .either, energy: .calm,
                 skills: [.social, .language],
                 steps: ["Ask the older one to show the baby a toy, a song or a book.", "Narrate: \"Look how the baby is watching you!\""],
                 why: "Gives the big sibling a proud role and gets the two connecting."),
        Activity("sing-actions", "Action songs", "🎶", ages: 6...60, minutes: 10, place: .either, energy: .active,
                 skills: [.language, .movement, .social],
                 steps: ["Sing songs with motions: Wheels on the Bus, Head Shoulders Knees and Toes, Itsy Bitsy Spider.", "Slow it down, then speed it up."],
                 why: "Rhyme and rhythm build early reading skills, and both kids can join in."),
        Activity("library", "Library story time", "🏛️", ages: 0...72, minutes: 45, place: .outside, energy: .calm,
                 skills: [.language, .social],
                 steps: ["Check your library's story time schedule.", "Let each kid pick books to bring home.", "Get the older one a library card."],
                 why: "Free, social and a weekly rhythm kids love."),
        Activity("playground", "Playground", "🛝", ages: 9...72, minutes: 45, place: .outside, energy: .active,
                 skills: [.movement, .social],
                 steps: ["Bucket swing for the baby; climbing and slides for the big kid.", "Play \"the floor is lava\" on the equipment."],
                 why: "Climbing, swinging and sliding work balance and strength in a way nothing indoors does."),
    ]
}
