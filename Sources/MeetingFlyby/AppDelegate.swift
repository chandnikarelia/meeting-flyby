import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let calendar = CalendarManager()
    private let google = GoogleCalendarManager.shared
    private let ics = ICSCalendarManager.shared
    private var pollTimer: Timer?
    private var alreadyFlown = Set<String>()
    private var onboarding: OnboardingWindowController?
    private var preferences: PreferencesWindowController?
    private var lastMeetings: [UpcomingMeeting] = []

    private let characters = ["🐶", "🐱", "🐷", "🐰"]
    private var character: String {
        get { UserDefaults.standard.string(forKey: "character") ?? "🐶" }
        set { UserDefaults.standard.set(newValue, forKey: "character") }
    }
    private var leadMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "leadMinutes")
            return v == 0 ? 5 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "leadMinutes") }
    }

    /// Preference order when more than one happens to be connected: Google sign-in (can merge
    /// multiple accounts), then a pasted ICS link, then macOS Calendar.
    private var activeSource: MeetingSource? {
        if google.isAuthorized { return google }
        if ics.isAuthorized { return ics }
        if calendar.isAuthorized { return calendar }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !characters.contains(character) { character = characters[0] }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = character
        rebuildMenu(status: nil)

        if activeSource != nil {
            startPolling()
        } else {
            showOnboarding()
        }
    }

    private func showOnboarding(atConnections: Bool = false) {
        if onboarding == nil {
            onboarding = OnboardingWindowController(calendar: calendar, google: google, ics: ics) { [weak self] in
                guard let self else { return }
                if self.activeSource != nil {
                    self.startPolling()
                } else {
                    self.rebuildMenu(status: "No calendar connected yet — pick \"Setup Instructions…\" from this menu when you're ready.")
                }
                self.preferences?.refreshMeetings()
            }
        }
        if atConnections { onboarding?.showConnectionsManager() }
        NSApp.activate(ignoringOtherApps: true)
        onboarding?.showWindow(nil)
        onboarding?.window?.makeKeyAndOrderFront(nil)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkMeetings()
        }
        pollTimer?.fire()
    }

    private func checkMeetings() {
        guard let source = activeSource else { return }
        let now = Date()
        source.fetchUpcomingMeetings { [weak self] meetings in
            guard let self else { return }
            self.lastMeetings = meetings
            self.rebuildMenu(status: nil, meetings: meetings)

            for meeting in meetings {
                guard !self.alreadyFlown.contains(meeting.id) else { continue }
                let secondsUntil = meeting.start.timeIntervalSince(now)
                let leadSeconds = TimeInterval(self.leadMinutes * 60)
                // Fire once we're inside the lead window (and not more than a minute late, in case of sleep/wake).
                if secondsUntil <= leadSeconds && secondsUntil > -60 {
                    self.alreadyFlown.insert(meeting.id)
                    let mins = max(0, Int(secondsUntil / 60))
                    let message = BannerMessages.next(title: meeting.title, minutes: mins)
                    FlybyOverlay.fly(character: self.character, message: message)
                }
            }
        }
    }

    private var sourceLabel: String {
        if google.isAuthorized {
            let count = google.accounts.count
            return count > 1 ? "Connected: Google Calendar (\(count) accounts)" : "Connected: Google Calendar"
        }
        if ics.isAuthorized { return "Connected: Calendar link (ICS)" }
        if calendar.isAuthorized { return "Connected: macOS Calendar" }
        return "Not connected"
    }

    private func rebuildMenu(status: String?, meetings: [UpcomingMeeting]? = nil) {
        let menu = NSMenu()
        let meetings = meetings ?? lastMeetings

        if let status {
            menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem(title: sourceLabel, action: nil, keyEquivalent: ""))

        if !meetings.isEmpty {
            menu.addItem(withTitle: "Today's meetings", action: nil, keyEquivalent: "")
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            for meeting in meetings.prefix(8) {
                let item = NSMenuItem(title: "\(formatter.string(from: meeting.start))  \(meeting.title)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Setup Instructions…", action: #selector(showOnboardingFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func showOnboardingFromMenu() {
        showOnboarding()
    }

    @objc private func showPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController(
                characters: characters,
                currentCharacter: character,
                currentLeadMinutes: leadMinutes,
                sourceLabel: { [weak self] in self?.sourceLabel ?? "Not connected" },
                fetchMeetings: { [weak self] window, completion in
                    guard let self, let source = self.activeSource else { completion([]); return }
                    source.fetchUpcomingMeetings(within: window, completion: completion)
                },
                onCharacterChanged: { [weak self] newCharacter in
                    guard let self else { return }
                    self.character = newCharacter
                    self.statusItem.button?.title = newCharacter
                    self.rebuildMenu(status: nil)
                },
                onLeadMinutesChanged: { [weak self] newLead in
                    self?.leadMinutes = newLead
                },
                onTestFlyby: { character in
                    FlybyOverlay.fly(character: character, message: BannerMessages.sample())
                },
                onManageConnections: { [weak self] in
                    self?.showOnboarding(atConnections: true)
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
    }
}
