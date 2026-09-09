import Cocoa

/// NSScrollView document views are bottom-anchored by default, which makes a list of rows
/// start at the bottom and scroll the wrong way. Flipping fixes that.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A rounded "card" container used to group each section of the preferences window.
private final class SectionCard: NSView {
    init(content: NSView, padding: CGFloat = 14) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        ])
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }
}

/// A clickable chip — used for character and heads-up-time selection. A plain NSView with its
/// own hitTest override rather than an NSButton, since NSButton's bezel styles can't produce
/// the selected/unselected look this needs.
private final class ChipCard: NSView {
    private let onClick: () -> Void
    private let background = CALayer()

    init(text: String, fontSize: CGFloat, selected: Bool, size: NSSize, accent: NSColor, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true

        background.cornerRadius = 10
        background.borderWidth = selected ? 0 : 1
        background.backgroundColor = (selected ? accent : NSColor.controlColor).cgColor
        background.borderColor = NSColor.separatorColor.cgColor
        layer?.addSublayer(background)

        if selected {
            layer?.shadowColor = accent.cgColor
            layer?.shadowOpacity = 0.35
            layer?.shadowRadius = 6
            layer?.shadowOffset = NSSize(width: 0, height: -2)
        }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: fontSize, weight: selected ? .semibold : .regular)
        label.textColor = selected ? .white : .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height)
        ])
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    override func layout() {
        super.layout()
        background.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// The single consolidated preferences window: connection status, character, heads-up time,
/// sound preview, a live test, and the actual upcoming meetings for the next 72 hours — so
/// the whole setup is verifiable in one place.
final class PreferencesWindowController: NSWindowController {
    private let characters: [String]
    private var currentCharacter: String
    private var currentLeadMinutes: Int
    private let sourceLabel: () -> String
    private let fetchMeetings: (TimeInterval, @escaping ([UpcomingMeeting]) -> Void) -> Void
    private let onCharacterChanged: (String) -> Void
    private let onLeadMinutesChanged: (Int) -> Void
    private let onTestFlyby: (String) -> Void
    private let onManageConnections: () -> Void

    private let contentWidth: CGFloat = 400

    private var characterRow: NSStackView!
    private var leadRow: NSStackView!
    private var connectionLabel: NSTextField!
    private var meetingsStatus: NSTextField!
    private var meetingsList: NSStackView!
    private var heroLabel: NSTextField?
    private var tintedViews: [NSView] = []
    private var accentDots: [NSView] = []

    init(
        characters: [String],
        currentCharacter: String,
        currentLeadMinutes: Int,
        sourceLabel: @escaping () -> String,
        fetchMeetings: @escaping (TimeInterval, @escaping ([UpcomingMeeting]) -> Void) -> Void,
        onCharacterChanged: @escaping (String) -> Void,
        onLeadMinutesChanged: @escaping (Int) -> Void,
        onTestFlyby: @escaping (String) -> Void,
        onManageConnections: @escaping () -> Void
    ) {
        self.characters = characters
        self.currentCharacter = currentCharacter
        self.currentLeadMinutes = currentLeadMinutes
        self.sourceLabel = sourceLabel
        self.fetchMeetings = fetchMeetings
        self.onCharacterChanged = onCharacterChanged
        self.onLeadMinutesChanged = onLeadMinutesChanged
        self.onTestFlyby = onTestFlyby
        self.onManageConnections = onManageConnections

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 456, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting Flyby"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        window.center()
        refreshMeetings()
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    // MARK: - Small builders

    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.preferredMaxLayoutWidth = contentWidth - 28
        return field
    }

    private func icon(_ symbol: String, size: CGFloat, tint: NSColor) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold)) ?? NSImage())
        view.contentTintColor = tint
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size + 3).isActive = true
        view.heightAnchor.constraint(equalToConstant: size + 3).isActive = true
        return view
    }

    private func sectionHeader(_ symbol: String, _ text: String, trailing: NSView? = nil) -> NSStackView {
        var views: [NSView] = [icon(symbol, size: 12, tint: .secondaryLabelColor),
                               label(text.uppercased(), size: 10, weight: .bold, color: .secondaryLabelColor)]
        if let trailing {
            views.append(NSView()) // flexible spacer pushes the trailing control to the right
            views.append(trailing)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    /// Wraps chips in a row that stays left-aligned instead of stretching them to fill.
    private func chipRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 8
        return row
    }

    private func linkButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = Theme.accent
        button.font = .systemFont(ofSize: 11, weight: .medium)
        return button
    }

    // MARK: - Layout

    private func buildUI() {
        guard let window, let contentView = window.contentView else { return }

        // Header
        let hero = label("\(currentCharacter) Meeting Flyby", size: 20, weight: .bold)
        heroLabel = hero
        let tagline = label("A little friend flies across your screen before every meeting.", size: 11, color: .secondaryLabelColor)

        // Connection
        connectionLabel = label(sourceLabel(), size: 12, weight: .medium)
        let connectionIcon = icon("checkmark.seal.fill", size: 13, tint: .systemGreen)
        let manageLink = linkButton("Manage…", action: #selector(manageConnections))
        let connectionRow = NSStackView(views: [connectionIcon, connectionLabel, NSView(), manageLink])
        connectionRow.orientation = .horizontal
        connectionRow.alignment = .centerY
        connectionRow.spacing = 8
        let connectionCard = SectionCard(content: connectionRow, padding: 12)

        // Character
        characterRow = chipRow()
        rebuildCharacterRow()
        let characterSection = NSStackView(views: [sectionHeader("face.smiling.inverse", "Your character"), characterRow])
        characterSection.orientation = .vertical
        characterSection.alignment = .leading
        characterSection.spacing = 10

        // Heads-up time
        leadRow = chipRow()
        rebuildLeadRow()
        let leadSection = NSStackView(views: [sectionHeader("clock.fill", "Heads-up time"), leadRow])
        leadSection.orientation = .vertical
        leadSection.alignment = .leading
        leadSection.spacing = 10

        let testButton = NSButton(title: "  Test flyby  ", target: self, action: #selector(testFlyby))
        testButton.bezelStyle = .rounded
        testButton.controlSize = .large
        testButton.keyEquivalent = ""

        let settingsInner = NSStackView(views: [characterSection, leadSection, testButton])
        settingsInner.orientation = .vertical
        settingsInner.alignment = .leading
        settingsInner.spacing = 18
        let settingsCard = SectionCard(content: settingsInner)

        // Meetings
        let refreshButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") ?? NSImage(), target: self, action: #selector(refreshMeetings))
        refreshButton.bezelStyle = .inline
        refreshButton.isBordered = false
        refreshButton.contentTintColor = Theme.accent
        tintedViews.append(refreshButton)
        let meetingsHeader = sectionHeader("calendar", "Next 72 hours", trailing: refreshButton)

        meetingsStatus = label("Loading…", size: 11, color: .secondaryLabelColor)

        meetingsList = NSStackView()
        meetingsList.orientation = .vertical
        meetingsList.alignment = .leading
        meetingsList.spacing = 2
        meetingsList.translatesAutoresizingMaskIntoConstraints = false

        // A flipped document view whose height tracks the list — without the bottom anchor the
        // container collapses to zero height and the rows render invisible.
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(meetingsList)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let listWidth = contentWidth - 28
        NSLayoutConstraint.activate([
            meetingsList.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            meetingsList.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            meetingsList.topAnchor.constraint(equalTo: document.topAnchor),
            document.bottomAnchor.constraint(equalTo: meetingsList.bottomAnchor),
            document.widthAnchor.constraint(equalToConstant: listWidth),
            scroll.widthAnchor.constraint(equalToConstant: listWidth),
            scroll.heightAnchor.constraint(equalToConstant: 200)
        ])

        let meetingsInner = NSStackView(views: [meetingsHeader, meetingsStatus, scroll])
        meetingsInner.orientation = .vertical
        meetingsInner.alignment = .leading
        meetingsInner.spacing = 8
        let meetingsCard = SectionCard(content: meetingsInner)

        let root = NSStackView(views: [hero, tagline, connectionCard, settingsCard, meetingsCard])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.setCustomSpacing(4, after: hero)
        root.setCustomSpacing(18, after: tagline)
        root.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            connectionCard.widthAnchor.constraint(equalToConstant: contentWidth),
            settingsCard.widthAnchor.constraint(equalToConstant: contentWidth),
            meetingsCard.widthAnchor.constraint(equalToConstant: contentWidth),
            connectionRow.widthAnchor.constraint(equalToConstant: contentWidth - 24),
            meetingsHeader.widthAnchor.constraint(equalToConstant: listWidth)
        ])
    }

    // MARK: - Character picker

    private func rebuildCharacterRow() {
        characterRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for character in characters {
            // Each pet keeps its own accent, so the row reads as a palette, not one blue blob.
            let chip = ChipCard(text: character, fontSize: 24, selected: character == currentCharacter,
                                size: NSSize(width: 62, height: 52), accent: Theme.accent(for: character)) { [weak self] in
                self?.selectCharacter(character)
            }
            characterRow.addArrangedSubview(chip)
        }
        let previewButton = NSButton(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Preview sound") ?? NSImage(), target: self, action: #selector(previewSound))
        previewButton.bezelStyle = .inline
        previewButton.isBordered = false
        previewButton.contentTintColor = Theme.accent
        tintedViews.append(previewButton)
        previewButton.toolTip = "Hear this character's sound"
        characterRow.addArrangedSubview(previewButton)
    }

    private func selectCharacter(_ character: String) {
        currentCharacter = character
        onCharacterChanged(character)
        rebuildCharacterRow()
        rebuildLeadRow()   // heads-up chips follow the new accent
        retint()
    }

    /// Re-applies the newly selected character's accent to everything outside the chip rows.
    private func retint() {
        heroLabel?.stringValue = "\(currentCharacter) Meeting Flyby"
        for view in tintedViews {
            (view as? NSImageView)?.contentTintColor = Theme.accent
            (view as? NSButton)?.contentTintColor = Theme.accent
        }
        for dot in accentDots {
            dot.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.85).cgColor
        accentDots.append(dot)
        }
    }

    @objc private func previewSound() {
        AnimalSound.play(for: currentCharacter)
    }

    // MARK: - Heads-up time picker

    private func rebuildLeadRow() {
        leadRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for minutes in [2, 5, 10] {
            let chip = ChipCard(text: "\(minutes) min", fontSize: 12, selected: minutes == currentLeadMinutes,
                                size: NSSize(width: 74, height: 34), accent: Theme.accent(for: currentCharacter)) { [weak self] in
                self?.selectLead(minutes)
            }
            leadRow.addArrangedSubview(chip)
        }
    }

    private func selectLead(_ minutes: Int) {
        currentLeadMinutes = minutes
        onLeadMinutesChanged(minutes)
        rebuildLeadRow()
    }

    // MARK: - Actions

    @objc private func testFlyby() {
        onTestFlyby(currentCharacter)
    }

    @objc private func manageConnections() {
        onManageConnections()
    }

    // MARK: - Meetings list

    @objc func refreshMeetings() {
        connectionLabel.stringValue = sourceLabel()
        meetingsStatus.stringValue = "Loading…"
        meetingsList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        accentDots.removeAll()

        fetchMeetings(72 * 3600) { [weak self] meetings in
            guard let self else { return }
            guard !meetings.isEmpty else {
                self.meetingsStatus.stringValue = "No meetings in the next 72 hours."
                return
            }
            self.meetingsStatus.stringValue = "\(meetings.count) meeting\(meetings.count == 1 ? "" : "s") synced from your calendar."

            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE, MMM d"
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            var lastDay: String?
            for meeting in meetings {
                let day = dayFormatter.string(from: meeting.start)
                if day != lastDay {
                    self.meetingsList.addArrangedSubview(self.dayHeader(Calendar.current.isDateInToday(meeting.start) ? "Today" : day))
                    lastDay = day
                }
                self.meetingsList.addArrangedSubview(self.meetingRow(meeting: meeting, formatter: timeFormatter))
            }
        }
    }

    private func dayHeader(_ text: String) -> NSView {
        let field = label(text, size: 10, weight: .bold, color: .tertiaryLabelColor)
        let container = NSView()
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3)
        ])
        return container
    }

    private func meetingRow(meeting: UpcomingMeeting, formatter: DateFormatter) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.85).cgColor
        accentDots.append(dot)
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let time = label(formatter.string(from: meeting.start), size: 11, weight: .semibold)
        time.translatesAutoresizingMaskIntoConstraints = false
        time.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let title = label(meeting.title, size: 11)
        title.preferredMaxLayoutWidth = 250
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        let row = NSStackView(views: [dot, time, title])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        return row
    }
}
