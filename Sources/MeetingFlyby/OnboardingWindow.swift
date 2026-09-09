import Cocoa

/// A small icon + text row used for inline status ("checking…", "connected", "failed") —
/// replaces plain text with an emoji prefix with a real SF Symbol, colored per state.
private final class StatusIndicator: NSView {
    enum Kind {
        case idle, working, success, warning, error

        var symbol: String {
            switch self {
            case .idle: return "circle.dashed"
            case .working: return "arrow.triangle.2.circlepath"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }

        var tint: NSColor {
            switch self {
            case .idle: return .tertiaryLabelColor
            case .working: return .secondaryLabelColor
            case .success: return .systemGreen
            case .warning: return .systemOrange
            case .error: return .systemRed
            }
        }
    }

    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        icon.imageScaling = .scaleProportionallyUpOrDown

        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 360

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        icon.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    func set(_ kind: Kind, _ text: String) {
        icon.isHidden = false
        icon.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        icon.contentTintColor = kind.tint
        label.stringValue = text
        label.textColor = kind == .idle ? .secondaryLabelColor : .labelColor
    }

    func clear() {
        icon.isHidden = true
        label.stringValue = ""
    }
}

/// A clickable "card" — icon, bold title, secondary subtitle — built as a plain NSView
/// instead of an NSButton. AppKit's `.rounded` bezel style silently ignores multi-line
/// titles no matter what wrap/lineBreakMode flags are set on the cell, which is why an
/// NSButton-based version of this rendered as an empty-looking blob with no subtitle.
/// Overrides hitTest to claim its entire bounds before AppKit can hand a click to one of
/// its child labels instead (which would otherwise swallow the click silently).
private final class OptionCard: NSView {
    private let onClick: () -> Void
    private let background = CALayer()

    init(symbol: String, title: String, subtitle: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true

        background.cornerRadius = 10
        background.borderWidth = 1
        layer?.addSublayer(background)
        updateBackground(pressed: false)

        let iconView = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium)) ?? NSImage())
        iconView.contentTintColor = Theme.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.preferredMaxLayoutWidth = 300

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.preferredMaxLayoutWidth = 300

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let row = NSStackView(views: [iconView, textStack])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            widthAnchor.constraint(equalToConstant: 384)
        ])
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    override func layout() {
        super.layout()
        background.frame = bounds
    }

    private func updateBackground(pressed: Bool) {
        background.backgroundColor = (pressed ? Theme.accent.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).cgColor
        background.borderColor = NSColor.separatorColor.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        updateBackground(pressed: true)
    }

    override func mouseUp(with event: NSEvent) {
        updateBackground(pressed: false)
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) { onClick() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// A small text button that calls a closure — avoids threading per-row state through
/// target/action selectors when building dynamic lists.
private final class ActionButton: NSButton {
    private let onClick: () -> Void

    init(title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .inline
        isBordered = false
        font = .systemFont(ofSize: 11, weight: .medium)
        contentTintColor = .secondaryLabelColor
        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    @objc private func fire() { onClick() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// First-run window: a chooser screen lets the user pick one connection method, then shows
/// only that path's steps — instead of dumping all three options onto one cluttered page.
/// Reachable again anytime via the menu bar's "Setup Instructions…" item.
final class OnboardingWindowController: NSWindowController {
    private let calendar: CalendarManager
    private let google: GoogleCalendarManager
    private let ics: ICSCalendarManager
    private let onFinished: () -> Void

    private var icsField: NSTextField!
    private var icsButton: NSButton!
    private var icsStatus: StatusIndicator!
    private var macStatus: StatusIndicator!
    private var grantButton: NSButton!
    private var googleStatus: StatusIndicator!
    private var googleButton: NSButton!

    /// Which page "Back" returns to — the chooser during first-run setup, the connections
    /// list when the window was opened from Preferences → Manage.
    private var homeIsConnections = false

    init(calendar: CalendarManager, google: GoogleCalendarManager, ics: ICSCalendarManager, onFinished: @escaping () -> Void) {
        self.calendar = calendar
        self.google = google
        self.ics = ics
        self.onFinished = onFinished
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Meeting Flyby"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        showChooser()
        window.center()
    }

    /// Opens straight to the connections list (add *and* remove), rather than the first-run
    /// chooser which only offers adding.
    func showConnectionsManager() {
        homeIsConnections = true
        window?.title = "Calendar Connections"
        showConnectionsPage()
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    // MARK: - Reusable pieces

    private func wrappingLabel(_ text: String, bold: Bool = false, size: CGFloat = 12, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.preferredMaxLayoutWidth = 380
        return field
    }

    private func icon(_ symbol: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, tint: NSColor = .labelColor) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) ?? NSImage())
        view.contentTintColor = tint
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: pointSize + 4).isActive = true
        view.heightAnchor.constraint(equalToConstant: pointSize + 4).isActive = true
        return view
    }

    /// A page heading: icon + bold text, side by side.
    private func titleRow(symbol: String, text: String) -> NSView {
        let row = NSStackView(views: [icon(symbol, pointSize: 17, weight: .medium), wrappingLabel(text, bold: true, size: 16)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func backButton() -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back") ?? NSImage(), target: self, action: #selector(backToChooser))
        button.title = "Back"
        button.imagePosition = .imageLeading
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.font = .systemFont(ofSize: 11)
        return button
    }

    /// A numbered, icon-led step row — used instead of a wall of prose so instructions read
    /// as a scannable visual sequence.
    private func stepRow(number: Int, symbol: String, text: String) -> NSView {
        let badge = NSTextField(labelWithString: "\(number)")
        badge.font = .boldSystemFont(ofSize: 11)
        badge.alignment = .center
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = Theme.accent.cgColor
        badge.layer?.cornerRadius = 9
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 18).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let stepIcon = icon(symbol, pointSize: 14, tint: .secondaryLabelColor)
        let label = wrappingLabel(text, size: 12)
        label.preferredMaxLayoutWidth = 300

        let row = NSStackView(views: [badge, stepIcon, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        return row
    }

    private func optionButton(symbol: String, title: String, subtitle: String, action: Selector) -> NSView {
        OptionCard(symbol: symbol, title: title, subtitle: subtitle, onClick: { [weak self] in
            guard let self else { return }
            _ = self.perform(action)
        })
    }

    /// Replaces the window's content with `stack` and resizes the window to fit it.
    private func present(_ stack: NSStackView) {
        guard let window else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalToConstant: 440)
        ])
        window.contentView = contentView
        contentView.layoutSubtreeIfNeeded()

        window.setContentSize(NSSize(width: 440, height: stack.fittingSize.height))
    }

    @objc private func backToChooser() {
        homeIsConnections ? showConnectionsPage() : showChooser()
    }

    // MARK: - Connections manager (add and remove)

    private func showConnectionsPage() {
        let title = titleRow(symbol: "calendar.badge.checkmark", text: "Calendar connections")
        let subtitle = wrappingLabel("Everything Meeting Flyby is reading from. Meetings from all connected calendars are merged together.", size: 12, secondary: true)

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8

        var hasAny = false
        for email in google.accounts {
            hasAny = true
            list.addArrangedSubview(connectionRow(
                symbol: "person.crop.circle.fill",
                title: email,
                detail: "Google Calendar",
                removeTitle: "Sign out",
                onRemove: { [weak self] in
                    self?.google.disconnect(email: email)
                    self?.showConnectionsPage()
                }
            ))
        }
        if ics.isAuthorized {
            hasAny = true
            list.addArrangedSubview(connectionRow(
                symbol: "link.circle.fill",
                title: "Calendar link",
                detail: ics.feedURL.map { String($0.prefix(46)) + ($0.count > 46 ? "…" : "") } ?? "ICS feed",
                removeTitle: "Disconnect",
                onRemove: { [weak self] in
                    self?.ics.disconnect()
                    self?.showConnectionsPage()
                }
            ))
        }
        if calendar.isAuthorized {
            hasAny = true
            list.addArrangedSubview(connectionRow(
                symbol: "laptopcomputer",
                title: "macOS Calendar",
                detail: "Managed in System Settings",
                removeTitle: "Open Settings",
                onRemove: { [weak self] in self?.openPrivacySettings() }
            ))
        }
        if !hasAny {
            list.addArrangedSubview(wrappingLabel("Nothing connected yet.", size: 12, secondary: true))
        }

        let addCard = OptionCard(
            symbol: "plus.circle.fill",
            title: "Add a calendar",
            subtitle: "Connect another Google account, your macOS Calendar, or a calendar link.",
            onClick: { [weak self] in self?.showChooser() }
        )

        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, subtitle, list, addCard, doneButton])
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(18, after: list)
        stack.setCustomSpacing(22, after: addCard)
        present(stack)
    }

    private func connectionRow(symbol: String, title: String, detail: String, removeTitle: String, onRemove: @escaping () -> Void) -> NSView {
        let leading = icon(symbol, pointSize: 16, weight: .medium, tint: Theme.accent)

        let titleLabel = wrappingLabel(title, bold: true, size: 12)
        titleLabel.preferredMaxLayoutWidth = 250
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        let detailLabel = wrappingLabel(detail, size: 10, secondary: true)
        detailLabel.preferredMaxLayoutWidth = 250
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1

        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let removeButton = ActionButton(title: removeTitle, onClick: onRemove)

        let row = NSStackView(views: [leading, text, NSView(), removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 384).isActive = true
        return row
    }

    // MARK: - Chooser page

    private func showChooser() {
        let title = titleRow(symbol: "calendar.badge.clock", text: "Connect a calendar")
        let subtitle = wrappingLabel("Pick whichever fits your setup — you can change this later from \"Setup Instructions…\" in the menu bar.")

        let googleOption = optionButton(
            symbol: "person.crop.circle.badge.plus",
            title: "Sign in with Google",
            subtitle: "Recommended. Works with your Mindtickle account — sign in and you're done. You can connect more than one.",
            action: #selector(chooseGoogle)
        )
        let macOption = optionButton(
            symbol: "laptopcomputer",
            title: "Use macOS Calendar",
            subtitle: "Works with any calendar already synced to your Mac — including most work/Google Workspace accounts.",
            action: #selector(chooseMac)
        )
        let icsOption = optionButton(
            symbol: "link",
            title: "Paste a calendar link",
            subtitle: "Simplest for a personal Gmail/Google Calendar — usually unavailable on work accounts.",
            action: #selector(chooseICS)
        )

        let stack = NSStackView(views: [title, subtitle, googleOption, macOption, icsOption])
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(12, after: googleOption)
        stack.setCustomSpacing(12, after: macOption)
        present(stack)
    }

    @objc private func chooseICS() { showICSPage() }
    @objc private func chooseMac() { showMacPage() }
    @objc private func chooseGoogle() { showGooglePage() }

    // MARK: - Option A: ICS link

    private func showICSPage() {
        let back = backButton()
        let title = titleRow(symbol: "link", text: "Paste your calendar link")
        let stepsLabel = wrappingLabel("For a personal Google account:", bold: true, size: 12)

        let steps = NSStackView(views: [
            stepRow(number: 1, symbol: "gearshape", text: "Open calendar.google.com → click the gear icon → Settings"),
            stepRow(number: 2, symbol: "calendar", text: "On the left, under \"Settings for my calendars,\" click your calendar"),
            stepRow(number: 3, symbol: "arrow.triangle.branch", text: "Scroll to \"Integrate calendar\""),
            stepRow(number: 4, symbol: "doc.on.clipboard", text: "Copy \"Secret address in iCal format\" and paste it below")
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 8

        let warningRow = NSStackView(views: [
            icon("exclamationmark.triangle.fill", pointSize: 13, tint: .systemOrange),
            wrappingLabel("Work/Google Workspace accounts often don't show a secret address (only a \"public\" one, which would expose your whole calendar). If you don't see one, use \"macOS Calendar\" or \"Sign in with Google\" instead.", size: 11, secondary: true)
        ])
        warningRow.orientation = .horizontal
        warningRow.alignment = .top
        warningRow.spacing = 8

        icsField = NSTextField(string: ics.feedURL ?? "")
        icsField.placeholderString = "https://calendar.google.com/calendar/ical/.../private-.../basic.ics"
        icsField.font = .systemFont(ofSize: 12)
        icsField.translatesAutoresizingMaskIntoConstraints = false
        icsField.widthAnchor.constraint(equalToConstant: 380).isActive = true

        icsButton = NSButton(title: "Connect", target: self, action: #selector(connectICS))
        let icsDisconnectButton = NSButton(title: "Disconnect", target: self, action: #selector(disconnectICS))
        icsDisconnectButton.bezelStyle = .inline
        icsDisconnectButton.isBordered = false
        icsDisconnectButton.contentTintColor = .systemRed
        icsDisconnectButton.font = .systemFont(ofSize: 11)
        let icsButtonRow = NSStackView(views: [icsButton, icsDisconnectButton])
        icsButtonRow.orientation = .horizontal
        icsButtonRow.spacing = 12

        icsStatus = StatusIndicator()
        if ics.isAuthorized { icsStatus.set(.success, "Connected.") }

        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [back, title, stepsLabel, steps, warningRow, icsField, icsButtonRow, icsStatus, doneButton])
        stack.setCustomSpacing(14, after: back)
        stack.setCustomSpacing(10, after: stepsLabel)
        stack.setCustomSpacing(16, after: steps)
        stack.setCustomSpacing(16, after: warningRow)
        stack.setCustomSpacing(20, after: icsStatus)
        present(stack)
    }

    @objc private func disconnectICS() {
        ics.disconnect()
        icsField.stringValue = ""
        icsStatus.set(.idle, "Disconnected.")
    }

    @objc private func connectICS() {
        let value = icsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            icsStatus.set(.warning, "Paste a calendar link into the field above first.")
            return
        }
        icsStatus.set(.working, "Checking…")
        icsButton.isEnabled = false
        ics.validate(urlString: value) { [weak self] result in
            guard let self else { return }
            self.icsButton.isEnabled = true
            switch result {
            case .success(let count):
                self.ics.feedURL = value
                self.icsStatus.set(.success, "Connected — found \(count) upcoming event(s).")
            case .failure(let error):
                self.icsStatus.set(.error, "Couldn't connect: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Option B: macOS Calendar

    private func showMacPage() {
        let back = backButton()
        let title = titleRow(symbol: "laptopcomputer", text: "Use macOS Calendar")

        let step1Title = wrappingLabel("Step 1 — Connect your calendar to macOS", bold: true, size: 12)
        let step1Body = wrappingLabel("If your Google, Outlook, or iCloud meetings already show up in the Calendar app, skip to the next button. Otherwise, add your account first — this works for work/Workspace accounts too.")
        let step1Button = NSButton(title: "Open Internet Accounts Settings…", target: self, action: #selector(openInternetAccounts))

        let step2Title = wrappingLabel("Step 2 — Let Meeting Flyby read it", bold: true, size: 12)
        let step2Body = wrappingLabel("Meeting Flyby only reads event titles and times, locally on your Mac. Nothing is uploaded anywhere.")
        let step2Button = NSButton(title: "Grant Calendar Access", target: self, action: #selector(grantAccess))
        grantButton = step2Button

        macStatus = StatusIndicator()
        if calendar.isAuthorized { macStatus.set(.success, "Calendar access already granted.") }

        let settingsLink = NSButton(title: "Open Privacy & Security Settings…", target: self, action: #selector(openPrivacySettings))
        settingsLink.bezelStyle = .inline
        settingsLink.isBordered = false
        settingsLink.contentTintColor = Theme.accent
        settingsLink.font = .systemFont(ofSize: 11)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            back, title,
            step1Title, step1Body, step1Button,
            step2Title, step2Body, step2Button, macStatus, settingsLink,
            doneButton
        ])
        stack.setCustomSpacing(14, after: back)
        stack.setCustomSpacing(16, after: step1Button)
        stack.setCustomSpacing(20, after: settingsLink)
        present(stack)
    }

    @objc private func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.internetaccounts")!)
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    @objc private func grantAccess() {
        macStatus.set(.working, "Requesting…")
        calendar.requestAccess { [weak self] granted in
            guard let self else { return }
            if granted {
                self.macStatus.set(.success, "Calendar access granted. You're all set!")
                self.grantButton.isEnabled = false
            } else {
                self.macStatus.set(.error, "Access denied. Use the link below to enable it, then try again.")
            }
        }
    }

    // MARK: - Google sign-in (supports multiple accounts)

    private var accountsStack: NSStackView!

    private func showGooglePage() {
        let back = backButton()
        let title = titleRow(symbol: "person.crop.circle.badge.plus", text: "Sign in with Google")
        let body = wrappingLabel("Connects directly to your Google account via the Calendar API. Nothing to set up — just sign in. You can connect more than one account; meetings from all of them are merged.")

        let keychainNoteRow = NSStackView(views: [
            icon("lock.shield", pointSize: 13, tint: .secondaryLabelColor),
            wrappingLabel("After signing in, macOS may ask for your Mac's login password (the one you use to unlock your Mac) to save the sign-in securely — that's Apple's Keychain protecting it, not a new password and nothing being sent anywhere. Choose \"Always Allow.\" This only happens once.", size: 11, secondary: true)
        ])
        keychainNoteRow.orientation = .horizontal
        keychainNoteRow.alignment = .top
        keychainNoteRow.spacing = 8

        let accountsTitle = wrappingLabel("Connected accounts", bold: true, size: 12)
        accountsStack = NSStackView()
        accountsStack.orientation = .vertical
        accountsStack.alignment = .leading
        accountsStack.spacing = 6

        googleButton = NSButton(title: "Add a Google account…", target: self, action: #selector(signInWithGoogle))
        googleStatus = StatusIndicator()

        let doneButton = NSButton(title: "Done", target: self, action: #selector(finish))
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [back, title, body, keychainNoteRow, accountsTitle, accountsStack, googleButton, googleStatus, doneButton])
        stack.setCustomSpacing(14, after: back)
        stack.setCustomSpacing(12, after: body)
        stack.setCustomSpacing(18, after: keychainNoteRow)
        stack.setCustomSpacing(8, after: accountsTitle)
        stack.setCustomSpacing(14, after: accountsStack)
        stack.setCustomSpacing(20, after: googleStatus)
        present(stack)
        refreshAccountsList()
    }

    private func refreshAccountsList() {
        accountsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if google.accounts.isEmpty {
            accountsStack.addArrangedSubview(wrappingLabel("None yet.", size: 12, secondary: true))
        } else {
            for email in google.accounts {
                accountsStack.addArrangedSubview(accountRow(email: email))
            }
        }
        // Re-run layout/resize now that the account list's height has changed.
        if let window {
            window.contentView?.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: 440, height: (window.contentView?.fittingSize.height) ?? window.frame.height))
        }
    }

    private func accountRow(email: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? NSImage())
        icon.contentTintColor = .systemGreen
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = wrappingLabel(email, size: 12)
        label.preferredMaxLayoutWidth = 260

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeAccount(_:)))
        removeButton.bezelStyle = .inline
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.font = .systemFont(ofSize: 11)
        removeButton.identifier = NSUserInterfaceItemIdentifier(email)

        let row = NSStackView(views: [icon, label, removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc private func removeAccount(_ sender: NSButton) {
        guard let email = sender.identifier?.rawValue else { return }
        google.disconnect(email: email)
        refreshAccountsList()
    }

    @objc private func signInWithGoogle() {
        if google.clientID == nil || google.clientID?.isEmpty == true {
            promptForClientID { [weak self] in
                self?.startGoogleSignIn()
            }
        } else {
            startGoogleSignIn()
        }
    }

    private func promptForClientID(then next: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Google OAuth Client ID"
        alert.informativeText = "Paste the Client ID from Google Cloud Console (APIs & Services → Credentials → OAuth client ID, type \"Desktop app\")."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "123456-abc.apps.googleusercontent.com"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            self.google.clientID = value
            next()
        }
    }

    private func startGoogleSignIn() {
        googleStatus.set(.working, "Opening your browser to sign in…")
        google.signIn { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.googleStatus.set(.success, "Account connected.")
                self.refreshAccountsList()
            case .failure(let error):
                self.googleStatus.set(.error, "Sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Shared

    @objc private func finish() {
        onFinished()
        window?.close()
    }
}
