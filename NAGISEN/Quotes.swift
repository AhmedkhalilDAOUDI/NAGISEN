import Foundation

/// A line to set on a share card. Lines without an author are NAGISEN's own; the classical ones use
/// public-domain translations (George Long for Marcus Aurelius and Epictetus, R. M. Gummere for Seneca).
struct Quote: Equatable, Identifiable {
    enum Theme: CaseIterable { case streak, day, move, strength, weight, trophy, any }

    let text: String
    let author: String?
    let themes: Set<Theme>

    var id: String { text }
}

enum Quotes {
    /// A line for this kind of card, never the one already showing.
    static func pick(for theme: Quote.Theme, after current: Quote? = nil) -> Quote {
        let fitting = all.filter { $0.themes.contains(theme) || $0.themes.contains(.any) }
        let pool = fitting.filter { $0 != current }
        return pool.randomElement() ?? all[0]
    }

    private static func q(_ text: String, _ themes: Quote.Theme..., by author: String? = nil) -> Quote {
        Quote(text: text, author: author, themes: Set(themes))
    }

    static let all: [Quote] = classical + streak + day + move + strength + weight + trophy + general

    // MARK: Classical (30)

    static let classical: [Quote] = [
        q("A journey of a thousand miles begins with a single step.", .move, .any, by: "Lao Tzu"),
        q("He who conquers others is strong; he who conquers himself is mighty.", .strength, .trophy, by: "Lao Tzu"),
        q("Knowing others is wisdom; knowing yourself is enlightenment.", .any, by: "Lao Tzu"),
        q("That which is an obstacle on the road helps us on this road.", .move, .strength, by: "Marcus Aurelius"),
        q("Waste no more time arguing about what a good man should be. Be one.", .any, by: "Marcus Aurelius"),
        q("Very little is needed to make a happy life.", .day, .any, by: "Marcus Aurelius"),
        q("Confine yourself to the present.", .day, .move, by: "Marcus Aurelius"),
        q("The soul becomes dyed with the colour of its thoughts.", .any, by: "Marcus Aurelius"),
        q("No great thing is produced suddenly, since not even the grape or the fig is.", .weight, .streak, by: "Epictetus"),
        q("First say to yourself what you would be; and then do what you have to do.", .strength, .any, by: "Epictetus"),
        q("It is impossible for a man to learn what he thinks he already knows.", .any, by: "Epictetus"),
        q("Begin at once to live, and count each separate day as a separate life.", .day, .streak, by: "Seneca"),
        q("While we are postponing, life speeds by.", .day, .any, by: "Seneca"),
        q("We suffer more often in imagination than in reality.", .strength, .any, by: "Seneca"),
        q("As long as you live, keep learning how to live.", .any, by: "Seneca"),
        q("Adopt the pace of nature: her secret is patience.", .weight, .move, by: "Ralph Waldo Emerson"),
        q("The years teach much which the days never know.", .streak, .weight, by: "Ralph Waldo Emerson"),
        q("Our life is frittered away by detail. Simplify, simplify.", .day, by: "Henry David Thoreau"),
        q("Methinks that the moment my legs begin to move, my thoughts begin to flow.", .move, by: "Henry David Thoreau"),
        q("All truly great thoughts are conceived while walking.", .move, by: "Friedrich Nietzsche"),
        q("I have walked myself into my best thoughts.", .move, by: "Søren Kierkegaard"),
        q("Well begun is half done.", .day, .move, by: "Aristotle"),
        q("The beginning is the most important part of the work.", .streak, .strength, by: "Plato"),
        q("Dripping water hollows a stone.", .streak, .weight, by: "Ovid"),
        q("No man ever steps in the same river twice.", .move, .any, by: "Heraclitus"),
        q("Real knowledge is to know the extent of one's ignorance.", .any, by: "Confucius"),
        q("Today is victory over yourself of yesterday.", .trophy, .strength, by: "Miyamoto Musashi"),
        q("Fall seven times, stand up eight.", .strength, .streak, by: "Japanese proverb"),
        q("Little by little, one travels far.", .move, .weight, by: "Spanish proverb"),
        q("The best time to plant a tree was twenty years ago. The second best time is now.", .day, .any, by: "Proverb"),
    ]

    // MARK: Streak, consistency (30)

    static let streak: [Quote] = [
        q("Another day kept. Quietly.", .streak),
        q("Not loud. Just every day.", .streak),
        q("The chain grows one link at a time.", .streak),
        q("I didn't feel like it. I did it anyway.", .streak),
        q("Consistency is a form of respect.", .streak),
        q("Small, again. Small, again. Then large.", .streak),
        q("Nobody claps for day forty. Do it anyway.", .streak),
        q("The habit is the reward.", .streak),
        q("Show up. Then show up again.", .streak),
        q("Discipline is remembering what you want.", .streak),
        q("Same time. Same place. Same promise.", .streak),
        q("Repetition is where the change hides.", .streak),
        q("I don't count the days. The days count me.", .streak),
        q("Ordinary days, kept in a row.", .streak),
        q("Motivation leaves. Routine stays.", .streak),
        q("The streak is just proof of the promise.", .streak),
        q("One more day of not giving up.", .streak),
        q("Quiet hands keep long streaks.", .streak),
        q("I'm not on a streak. I'm becoming someone.", .streak),
        q("Each day: a stone. Together: a road.", .streak),
        q("The work doesn't need witnesses.", .streak, .any),
        q("Keep the light on, one day at a time.", .streak),
        q("No break in the line.", .streak),
        q("I kept the door open again today.", .streak),
        q("It's not about the start. It's about the next day.", .streak),
        q("Even on the slow days, the day counts.", .streak),
        q("I keep showing up for the version I'm building.", .streak),
        q("Patience, practised daily.", .streak, .weight),
        q("This is what staying looks like.", .streak),
        q("The calendar remembers what the mirror can't see yet.", .streak, .weight),
    ]

    // MARK: The day, food (25)

    static let day: [Quote] = [
        q("Eat well. Rest well. Repeat.", .day),
        q("A quiet day, well fed.", .day),
        q("Fuel, not punishment.", .day),
        q("Today, I listened to my body.", .day),
        q("Good food. Clear mind.", .day),
        q("Balance isn't found. It's chosen, meal by meal.", .day),
        q("Simple plates, steady days.", .day),
        q("Nourish the work ahead.", .day),
        q("The day was logged. The day was mine.", .day),
        q("I fed the person I'm becoming.", .day),
        q("Enough is a beautiful number.", .day),
        q("Slow food. Steady progress.", .day),
        q("Water first. Everything else after.", .day),
        q("A calm day is still a strong day.", .day),
        q("No drama. Just a good day.", .day),
        q("Eat like you plan to stay.", .day),
        q("Today was taken care of.", .day),
        q("Small choices, all day long.", .day),
        q("Hungry for progress, not for punishment.", .day),
        q("I didn't chase perfect. I chased better.", .day, .weight),
        q("The quiet work of a good day.", .day),
        q("Measured, not restricted.", .day),
        q("Clarity tastes like a simple meal.", .day),
        q("Today I chose care over noise.", .day),
        q("A day in order is a mind at rest.", .day),
    ]

    // MARK: Moving: run, walk, ride, hike (30)

    static let move: [Quote] = [
        q("Out the door. That's the hard part.", .move),
        q("Breathe. Step. Repeat.", .move),
        q("The road was quiet. So was I.", .move),
        q("Before the city wakes.", .move),
        q("Every kilometre, earned.", .move),
        q("Slow is still forward.", .move),
        q("I ran to clear my head. It worked.", .move),
        q("Footsteps are a kind of thinking.", .move),
        q("The pace doesn't matter. The leaving does.", .move),
        q("Lungs open. Mind empty.", .move),
        q("I went the long way on purpose.", .move),
        q("Distance is just patience in motion.", .move, .weight),
        q("The street lights were my crowd.", .move),
        q("Tired legs, rested mind.", .move),
        q("Running away from nothing. Toward everything.", .move),
        q("Wind on the face. Nothing else to do.", .move),
        q("Kilometre by kilometre, quietly.", .move),
        q("The hill was steep. I was steady.", .move),
        q("I don't run fast. I run often.", .move, .streak),
        q("Movement is the cheapest therapy.", .move),
        q("Wheels turning, thoughts settling.", .move),
        q("The trail doesn't care who's watching.", .move),
        q("Up the climb, one breath at a time.", .move),
        q("Moving through the noise.", .move),
        q("Today the city was my track.", .move),
        q("A walk is a small way of starting over.", .move),
        q("Sweat first, thoughts later.", .move),
        q("The finish line was my front door.", .move),
        q("I went out heavy. I came back light.", .move),
        q("Somewhere between the first step and the last, I found it.", .move),
    ]

    // MARK: Strength, workouts, records (30)

    static let strength: [Quote] = [
        q("The weight doesn't lie.", .strength),
        q("Strong is a slow word.", .strength),
        q("One more rep. Quietly.", .strength),
        q("Iron is patient. So am I.", .strength),
        q("Earned under the bar.", .strength),
        q("Silence between the sets.", .strength),
        q("The body keeps the receipts.", .strength),
        q("Heavy things, carried well.", .strength),
        q("Form first. Ego last.", .strength),
        q("Every rep is a vote for who I'm becoming.", .strength, .streak),
        q("I didn't come here to be comfortable.", .strength),
        q("Effort is the only thing I control.", .strength),
        q("Rest is part of the program.", .strength),
        q("The hard set is where it happens.", .strength),
        q("Strength is built in the boring reps.", .strength, .streak),
        q("New number. Same quiet.", .strength, .trophy),
        q("Lift it. Set it down. Lift it again.", .strength),
        q("No shortcuts under load.", .strength),
        q("Done before the doubt arrived.", .strength),
        q("The bar moved. So did I.", .strength, .trophy),
        q("Calm hands, heavy weight.", .strength),
        q("Pressure makes the shape.", .strength),
        q("The work was honest today.", .strength, .day),
        q("Built, not bought.", .strength),
        q("I trained the part of me that wanted to stop.", .strength),
        q("Steady breath, steady bar.", .strength),
        q("Muscles remember. So does the mind.", .strength),
        q("A session is a promise kept.", .strength, .streak),
        q("Strong enough to be gentle.", .strength),
        q("The quiet ones lift the most.", .strength),
    ]

    // MARK: Weight, patience, change (20)

    static let weight: [Quote] = [
        q("The change is quiet. Then it isn't.", .weight),
        q("Slower than I wanted. Faster than I expected.", .weight),
        q("Progress is a long sentence.", .weight),
        q("Not a diet. A direction.", .weight),
        q("The scale is a witness, not a judge.", .weight),
        q("I stopped racing. I started changing.", .weight),
        q("Lighter, in more ways than one.", .weight),
        q("The curve bends for the patient.", .weight),
        q("Week by week, the line moves.", .weight),
        q("This took months. It was worth every one.", .weight),
        q("Proof that slow works.", .weight),
        q("I trusted the process. The process kept its word.", .weight),
        q("Less noise, more change.", .weight),
        q("A body changed by many small yeses.", .weight),
        q("The numbers caught up with the habits.", .weight, .streak),
        q("Not perfect. Persistent.", .weight, .streak),
        q("I'm not chasing a weight. I'm building a life.", .weight),
        q("The mirror is slower than the work. Wait for it.", .weight),
        q("Every week, a little more like me.", .weight),
        q("Change is a quiet guest. It stays when you're kind to it.", .weight),
    ]

    // MARK: Trophies, milestones (15)

    static let trophy: [Quote] = [
        q("Earned, not given.", .trophy),
        q("A small medal for a long effort.", .trophy),
        q("Proof of the quiet work.", .trophy),
        q("Unlocked by showing up.", .trophy, .streak),
        q("The reward was the routine. This is just the receipt.", .trophy),
        q("Milestone reached. Road continues.", .trophy),
        q("Not the end. A marker.", .trophy),
        q("I didn't aim for this. I aimed for the next day.", .trophy, .streak),
        q("Quietly collected.", .trophy),
        q("A new line in the story.", .trophy),
        q("Some trophies are just better habits.", .trophy),
        q("Earned in the hours nobody saw.", .trophy, .strength),
        q("Here's to the version that didn't quit.", .trophy),
        q("Celebrate, then continue.", .trophy),
        q("This one was a long time coming.", .trophy),
    ]

    // MARK: Anywhere (20)

    static let general: [Quote] = [
        q("The art of quiet progress.", .any),
        q("Progress makes no sound.", .any),
        q("Rise. Move. Rest. Repeat.", .any),
        q("No one sees the repetition. It shows later.", .any),
        q("In silence.", .any),
        q("Step by step. Even when no one is watching.", .any),
        q("Calm is a discipline.", .any),
        q("Less, but better.", .any),
        q("Stillness is also work.", .any),
        q("Be patient with the person you're becoming.", .any),
        q("A slow life, lived on purpose.", .any),
        q("What you do daily, you become.", .any),
        q("Keep it simple. Keep it going.", .any),
        q("The quiet before the work.", .any),
        q("Gentle with myself. Firm with my habits.", .any),
        q("Nothing to prove. Everything to keep.", .any),
        q("The work is the reward.", .any),
        q("Here, now, again.", .any),
        q("Soft voice, strong will.", .any),
        q("Becoming, slowly.", .any),
    ]
}
