import Foundation
import Network
import CryptoKit
import Cocoa

enum GoogleError: LocalizedError {
    case missingClientID
    case noRedirect
    case tokenExchangeFailed(String)
    case stateMismatch
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "No Google Client ID configured."
        case .noRedirect: return "Didn't receive a response from Google's sign-in page."
        case .tokenExchangeFailed(let detail): return "Google rejected the sign-in exchange: \(detail)"
        case .stateMismatch: return "Sign-in response failed its security check and was rejected. Please try again."
        case .notSignedIn: return "Not signed in to Google."
        }
    }
}

/// Signs in to one or more Google accounts directly (OAuth 2.0 + PKCE) and merges their
/// Calendar events — no macOS Calendar/EventKit involved. Each account's refresh token is
/// stored in the Keychain under its own email, so "Add another account" just runs the same
/// sign-in flow again rather than replacing what's already connected.
final class GoogleCalendarManager: MeetingSource {
    static let shared = GoogleCalendarManager()
    private init() { migrateLegacyTokenIfNeeded() }

    private var accessTokens: [String: (token: String, expiry: Date)] = [:] // keyed by email
    private var listener: NWListener?
    private var loopbackPort: Int = 0
    private var expectedState: String?
    private var signInCompleted = false

    /// Falls back to the bundled client so a fresh install works with no setup at all; a
    /// value pasted on the Advanced page still wins if someone wants their own project.
    var clientID: String? {
        get { UserDefaults.standard.string(forKey: "googleClientID") ?? BundledCredentials.googleClientID }
        set { UserDefaults.standard.set(newValue, forKey: "googleClientID") }
    }

    /// Google's Cloud Console still issues (and, in practice, requires) a client secret for
    /// "Desktop app" OAuth clients even though the PKCE flow doesn't strictly need one for a
    /// public client — omitting it is what caused the earlier "invalid_client" exchange failure.
    var clientSecret: String? {
        get { UserDefaults.standard.string(forKey: "googleClientSecret") ?? BundledCredentials.googleClientSecret }
        set { UserDefaults.standard.set(newValue, forKey: "googleClientSecret") }
    }

    /// Emails of every connected account, in the order they were added.
    private(set) var accounts: [String] {
        get { UserDefaults.standard.stringArray(forKey: "googleAccounts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "googleAccounts") }
    }

    var isAuthorized: Bool { !accounts.isEmpty }

    func disconnect(email: String) {
        Keychain.delete(account: keychainAccount(for: email))
        accounts.removeAll { $0 == email }
        accessTokens[email] = nil
    }

    /// One-time upgrade path: the very first sign-in (before multi-account support existed)
    /// stored its refresh token under a fixed "refreshToken" key with no associated email.
    private func migrateLegacyTokenIfNeeded() {
        let legacyAccount = "refreshToken"
        guard accounts.isEmpty, let token = Keychain.get(account: legacyAccount) else { return }
        let placeholderEmail = "Google Account"
        Keychain.set(token, account: keychainAccount(for: placeholderEmail))
        Keychain.delete(account: legacyAccount)
        accounts = [placeholderEmail]
    }

    private func keychainAccount(for email: String) -> String { "refreshToken:\(email)" }

    // MARK: - Sign-in

    /// Runs the full OAuth flow and adds the resulting account to `accounts` — call again to
    /// connect an additional account; existing ones are left untouched.
    func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let clientID, !clientID.isEmpty else {
            completion(.failure(GoogleError.missingClientID))
            return
        }

        let verifier = Self.randomURLSafeString(length: 32)
        let challenge = Self.codeChallenge(for: verifier)
        // CSRF guard: Google echoes this back on the redirect. Without checking it, the app
        // would accept ANY authorization code delivered to the loopback port — letting someone
        // bind the app to an account the user never chose.
        let state = Self.randomURLSafeString(length: 24)
        expectedState = state
        signInCompleted = false
        listener?.cancel()   // don't leak a listener from an abandoned sign-in attempt
        listener = nil

        startLoopbackServer(
            onReady: { port in
                var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:\(port)"),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: "openid email https://www.googleapis.com/auth/calendar.readonly"),
                    URLQueryItem(name: "code_challenge", value: challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "state", value: state),
                    // select_account forces the account chooser every time, so signing in
                    // again to add a second account doesn't silently reuse the first one.
                    URLQueryItem(name: "prompt", value: "select_account consent")
                ]
                if let url = components.url {
                    NSWorkspace.shared.open(url)
                }
            },
            onCode: { [weak self] result in
                guard let self else { return }
                self.expectedState = nil
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let code):
                    self.exchangeCode(code, verifier: verifier, clientID: clientID, completion: completion)
                }
            }
        )
    }

    // MARK: - Loopback redirect listener

    private func startLoopbackServer(onReady: @escaping (Int) -> Void, onCode: @escaping (Result<String, Error>) -> Void) {
        do {
            // Bind to loopback only. NWListener's default (.any) listens on every interface,
            // which would expose the redirect endpoint to anyone on the same network for the
            // duration of the sign-in.
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.loopbackPort = Int(listener.port?.rawValue ?? 0)
                    onReady(self.loopbackPort)
                case .failed(let error):
                    onCode(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection, onCode: onCode)
            }
            listener.start(queue: .main)
        } catch {
            onCode(.failure(error))
        }
    }

    private func handleConnection(_ connection: NWConnection, onCode: @escaping (Result<String, Error>) -> Void) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }

            // Browsers open extra connections to the redirect origin (favicon, prefetch).
            // Without this guard those arrive after the real callback, find expectedState
            // already cleared, and report a bogus "security check failed" on a sign-in that
            // actually succeeded — calling completion a second time in the process.
            guard !self.signInCompleted else {
                self.respond(connection, status: "204 No Content", body: "")
                return
            }
            self.signInCompleted = true

            defer {
                self.listener?.cancel()
                self.listener = nil
            }

            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first,
                  let path = firstLine.split(separator: " ").dropFirst().first,
                  let url = URL(string: "http://localhost\(path)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                self.respond(connection, status: "400 Bad Request", body: "Sign-in failed — no code received.")
                onCode(.failure(GoogleError.noRedirect))
                return
            }

            // Reject any callback whose state doesn't match the one this app just generated.
            let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
            guard let expected = self.expectedState, returnedState == expected else {
                self.respond(connection, status: "400 Bad Request", body: "Sign-in rejected — security check failed.")
                onCode(.failure(GoogleError.stateMismatch))
                return
            }

            self.respond(connection, status: "200 OK", body: "<h2>You can close this tab.</h2><p>Meeting Flyby is connected to Google Calendar.</p>")
            onCode(.success(code))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = "<html><body style='font-family:-apple-system;padding:40px;text-align:center'>\(body)</body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String, verifier: String, clientID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var params = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": "http://127.0.0.1:\(loopbackPort)"
        ]
        if let clientSecret, !clientSecret.isEmpty { params["client_secret"] = clientSecret }

        postForm(to: "https://oauth2.googleapis.com/token", params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let json):
                guard let accessToken = json["access_token"] as? String,
                      let expiresIn = json["expires_in"] as? Double,
                      let refreshToken = json["refresh_token"] as? String else {
                    DispatchQueue.main.async { completion(.failure(GoogleError.tokenExchangeFailed(Self.describe(json)))) }
                    return
                }
                self.fetchEmail(accessToken: accessToken) { email in
                    let email = email ?? "Google Account \(self.accounts.count + 1)"
                    Keychain.set(refreshToken, account: self.keychainAccount(for: email))
                    if !self.accounts.contains(email) { self.accounts.append(email) }
                    self.accessTokens[email] = (accessToken, Date().addingTimeInterval(expiresIn - 60))
                    DispatchQueue.main.async { completion(.success(())) }
                }
            }
        }
    }

    private func fetchEmail(accessToken: String, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(json["email"] as? String)
        }.resume()
    }

    private func refreshAccessToken(email: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let clientID, let refreshToken = Keychain.get(account: keychainAccount(for: email)) else {
            completion(.failure(GoogleError.notSignedIn))
            return
        }
        var params = ["client_id": clientID, "refresh_token": refreshToken, "grant_type": "refresh_token"]
        if let clientSecret, !clientSecret.isEmpty { params["client_secret"] = clientSecret }

        postForm(to: "https://oauth2.googleapis.com/token", params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let json):
                guard let accessToken = json["access_token"] as? String,
                      let expiresIn = json["expires_in"] as? Double else {
                    DispatchQueue.main.async { completion(.failure(GoogleError.tokenExchangeFailed(Self.describe(json)))) }
                    return
                }
                self.accessTokens[email] = (accessToken, Date().addingTimeInterval(expiresIn - 60))
                DispatchQueue.main.async { completion(.success(accessToken)) }
            }
        }
    }

    /// Surfaces Google's actual "error"/"error_description" fields instead of a generic
    /// message, so failures are diagnosable from the UI alone.
    private static func describe(_ json: [String: Any]) -> String {
        let code = json["error"] as? String ?? "unknown_error"
        let detail = json["error_description"] as? String
        return detail.map { "\(code) — \($0)" } ?? code
    }

    private func validAccessToken(email: String, completion: @escaping (Result<String, Error>) -> Void) {
        if let cached = accessTokens[email], cached.expiry > Date() {
            completion(.success(cached.token))
        } else {
            refreshAccessToken(email: email, completion: completion)
        }
    }

    private func postForm(to urlString: String, params: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no response body"
                completion(.failure(GoogleError.tokenExchangeFailed(raw)))
                return
            }
            completion(.success(json))
        }.resume()
    }

    // MARK: - Fetching events (merged across every connected account)

    func fetchUpcomingMeetings(within window: TimeInterval, completion: @escaping ([UpcomingMeeting]) -> Void) {
        let emails = accounts
        guard !emails.isEmpty else {
            completion([])
            return
        }

        var results: [[UpcomingMeeting]] = Array(repeating: [], count: emails.count)
        let group = DispatchGroup()
        for (index, email) in emails.enumerated() {
            group.enter()
            validAccessToken(email: email) { [weak self] result in
                guard let self else { group.leave(); return }
                switch result {
                case .failure:
                    group.leave()
                case .success(let token):
                    self.fetchEvents(token: token, window: window) { meetings in
                        results[index] = meetings
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) {
            var seenIDs = Set<String>()
            let merged = results.flatMap { $0 }
                .filter { seenIDs.insert($0.id).inserted } // same event on two calendars only shown once
                .sorted { $0.start < $1.start }
            completion(merged)
        }
    }

    private func fetchEvents(token: String, window: TimeInterval, completion: @escaping ([UpcomingMeeting]) -> Void) {
        let iso = ISO8601DateFormatter()
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: Date().addingTimeInterval(-60))),
            URLQueryItem(name: "timeMax", value: iso.string(from: Date().addingTimeInterval(window))),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                completion([])
                return
            }

            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()

            let meetings: [UpcomingMeeting] = items.compactMap { item in
                guard let id = item["id"] as? String,
                      let startInfo = item["start"] as? [String: Any],
                      let dateTimeStr = startInfo["dateTime"] as? String, // skip all-day (date-only) events
                      let start = withFraction.date(from: dateTimeStr) ?? plain.date(from: dateTimeStr)
                else { return nil }
                let title = item["summary"] as? String ?? "Meeting"
                let location = item["location"] as? String
                return UpcomingMeeting(id: id, title: title, start: start, location: location)
            }
            completion(meetings)
        }.resume()
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
