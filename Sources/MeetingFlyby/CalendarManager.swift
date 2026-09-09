import EventKit
import Foundation

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let start: Date
    let location: String?
}

/// A source of upcoming meetings — implemented by EventKit (macOS Calendar) and by
/// GoogleCalendarManager (direct Google sign-in, no macOS Calendar involved).
protocol MeetingSource: AnyObject {
    var isAuthorized: Bool { get }
    func fetchUpcomingMeetings(within window: TimeInterval, completion: @escaping ([UpcomingMeeting]) -> Void)
}

extension MeetingSource {
    /// Default lookahead used by the flyby's own polling loop.
    func fetchUpcomingMeetings(completion: @escaping ([UpcomingMeeting]) -> Void) {
        fetchUpcomingMeetings(within: 24 * 3600, completion: completion)
    }
}

final class CalendarManager: MeetingSource {
    private let store = EKEventStore()
    private(set) var authorized = false

    /// Current OS-level authorization, without prompting — used to decide whether to show
    /// onboarding on launch or jump straight to polling.
    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                self.authorized = granted
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                self.authorized = granted
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    /// Meetings starting between now and `window` seconds from now, plus already-in-progress ones
    /// that started within the last minute (so a fast poll doesn't miss the start).
    func upcomingMeetings(within window: TimeInterval = 24 * 3600) -> [UpcomingMeeting] {
        let now = Date()
        let end = now.addingTimeInterval(window)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map {
                UpcomingMeeting(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Meeting",
                    start: $0.startDate,
                    location: $0.location
                )
            }
    }

    func fetchUpcomingMeetings(within window: TimeInterval, completion: @escaping ([UpcomingMeeting]) -> Void) {
        completion(upcomingMeetings(within: window))
    }
}
