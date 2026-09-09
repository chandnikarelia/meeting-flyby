import Foundation

/// Rotating banner copy, so the same flyby doesn't read identically every time. The index
/// persists across launches and advances on every flight, which guarantees a different line
/// each time rather than the repeats you'd get from picking at random.
enum BannerMessages {
    /// Lines used when the meeting hasn't started yet. `%@` is the meeting title, `%d` the
    /// whole minutes remaining.
    private static let upcoming: [String] = [
        "%1$@ in %2$d min — look busy!",
        "Psst… %1$@ starts in %2$d min",
        "%2$d min until %1$@. Save your work!",
        "Heads up! %1$@ is %2$d min away",
        "%1$@ — %2$d min. Time to find your good angle",
        "Incoming: %1$@ in %2$d min",
        "%2$d min to %1$@. Coffee refill window!",
        "%1$@ in %2$d min — unmute practice starts now",
        "Flap flap! %1$@ in %2$d min",
        "%1$@ lands in %2$d min. Brace yourself",
        "%2$d min till %1$@. Close those 47 tabs",
        "Special delivery: %1$@ in %2$d min",
        "%1$@ in %2$d min — camera-ready check!",
        "Tick tock… %1$@ in %2$d min",
        "%2$d min out: %1$@. You've got this",
        "%1$@ approaching in %2$d min. Buckle up",
        "Wrapping up? %1$@ starts in %2$d min",
        "%2$d min warning: %1$@"
    ]

    /// Lines used when the meeting is starting right about now.
    private static let now: [String] = [
        "%1$@ is starting NOW!",
        "Go go go — %1$@ has begun!",
        "%1$@ — you're on!",
        "Showtime! %1$@ is live",
        "%1$@ started. Run!",
        "Curtain up: %1$@",
        "%1$@ is happening right now",
        "This is your %1$@ alarm. GO!"
    ]

    private static let indexKey = "bannerMessageIndex"

    /// Builds the next line in the rotation for a meeting `minutes` away (0 = starting now).
    static func next(title: String, minutes: Int) -> String {
        let defaults = UserDefaults.standard
        let index = defaults.integer(forKey: indexKey)
        defaults.set(index &+ 1, forKey: indexKey)

        if minutes <= 0 {
            let template = now[abs(index) % now.count]
            return String(format: template, title)
        }
        let template = upcoming[abs(index) % upcoming.count]
        return String(format: template, title, minutes)
    }

    /// A random line for the "Test flyby" button, so testing shows off the variety.
    static func sample() -> String {
        let titles = ["Stand-up", "Design review", "1:1 with Sam", "Sprint planning", "Coffee chat"]
        let title = titles.randomElement() ?? "Stand-up"
        return next(title: title, minutes: [2, 5, 10].randomElement() ?? 5)
    }
}
