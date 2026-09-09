import Foundation

/// Reads events from a plain ICS/iCal feed URL — e.g. Google Calendar's "Secret address in
/// iCal format", or Outlook/iCloud's equivalent. No OAuth, no developer account, no login:
/// just a URL the user copies from their own calendar's sharing settings.
final class ICSCalendarManager: MeetingSource {
    static let shared = ICSCalendarManager()
    private init() {}

    var feedURL: String? {
        get { UserDefaults.standard.string(forKey: "icsFeedURL") }
        set { UserDefaults.standard.set(newValue, forKey: "icsFeedURL") }
    }

    var isAuthorized: Bool {
        guard let feedURL else { return false }
        return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func disconnect() {
        feedURL = nil
    }

    func fetchUpcomingMeetings(within window: TimeInterval, completion: @escaping ([UpcomingMeeting]) -> Void) {
        guard let feedURL, let url = URL(string: feedURL) else {
            completion([])
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let now = Date()
            let windowEnd = now.addingTimeInterval(window)
            let meetings = Self.parseICS(text)
                .filter { $0.start >= now.addingTimeInterval(-60) && $0.start <= windowEnd }
                .sorted { $0.start < $1.start }
            DispatchQueue.main.async { completion(meetings) }
        }.resume()
    }

    /// Quick sanity check when the user first pastes a link — fetches once and reports
    /// whether it looks like a real, parseable calendar feed.
    func validate(urlString: String, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(ICSError.invalidURL))
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data, let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else {
                DispatchQueue.main.async { completion(.failure(ICSError.notACalendar)) }
                return
            }
            let count = Self.parseICS(text).count
            DispatchQueue.main.async { completion(.success(count)) }
        }.resume()
    }

    // MARK: - Parsing

    private static func parseICS(_ text: String) -> [UpcomingMeeting] {
        let unfolded = unfoldLines(text.replacingOccurrences(of: "\r\n", with: "\n"))

        var meetings: [UpcomingMeeting] = []
        var inEvent = false
        var uid: String?
        var summary: String?
        var location: String?
        var startDate: Date?

        for line in unfolded {
            if line == "BEGIN:VEVENT" {
                inEvent = true; uid = nil; summary = nil; location = nil; startDate = nil
                continue
            }
            if line == "END:VEVENT" {
                if inEvent, let startDate {
                    meetings.append(UpcomingMeeting(id: uid ?? UUID().uuidString, title: summary ?? "Meeting", start: startDate, location: location))
                }
                inEvent = false
                continue
            }
            guard inEvent else { continue }

            if line.hasPrefix("UID:") {
                uid = String(line.dropFirst(4))
            } else if line.hasPrefix("SUMMARY:") {
                summary = unescape(String(line.dropFirst(8)))
            } else if line.hasPrefix("LOCATION:") {
                location = unescape(String(line.dropFirst(9)))
            } else if line.hasPrefix("DTSTART") {
                startDate = parseDTStart(line)
            }
        }
        return meetings
    }

    /// ICS "folds" long lines by breaking them and prefixing continuations with a space/tab.
    private static func unfoldLines(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    private static func parseDTStart(_ line: String) -> Date? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let params = line[line.index(line.startIndex, offsetBy: "DTSTART".count)..<colonIndex]
        let value = String(line[line.index(after: colonIndex)...])

        if params.contains("VALUE=DATE") { return nil } // all-day event — skip, matches EventKit behavior

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
        } else {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            if let tzRange = params.range(of: "TZID=") {
                let tzid = String(params[tzRange.upperBound...]).components(separatedBy: ";").first ?? "UTC"
                formatter.timeZone = TimeZone(identifier: tzid) ?? .current
            } else {
                formatter.timeZone = .current
            }
        }
        return formatter.date(from: value)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

enum ICSError: LocalizedError {
    case invalidURL
    case notACalendar

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid URL."
        case .notACalendar: return "That link didn't return a calendar feed — double check it's the ICS/iCal link, not a regular calendar page URL."
        }
    }
}
