import CatnapCore
import Cocoa

// MARK: - Link Button

/// A borderless button that opens a URL when clicked.
private class LinkButton: NSButton {
    let linkURL: URL?

    init(title: String, url: String) {
        self.linkURL = URL(string: url)
        super.init(frame: .zero)
        self.title = title
        self.isBordered = false
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        self.contentTintColor = .linkColor
        self.alignment = .center
        self.toolTip = url
        self.translatesAutoresizingMaskIntoConstraints = false
        self.target = self
        self.action = #selector(openURL)
    }

    init(image: NSImage, url: String) {
        self.linkURL = URL(string: url)
        super.init(frame: .zero)
        self.image = image
        self.isBordered = false
        self.imagePosition = .imageOnly
        self.contentTintColor = .labelColor
        self.toolTip = url
        self.translatesAutoresizingMaskIntoConstraints = false
        self.target = self
        self.action = #selector(openURL)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        if linkURL != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    @objc private func openURL() {
        if let url = linkURL {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Action Link Button

/// A borderless button that performs an action when clicked (no URL).
private class ActionLinkButton: NSButton {
    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.isBordered = false
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        self.contentTintColor = .linkColor
        self.alignment = .center
        self.translatesAutoresizingMaskIntoConstraints = false
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - About View Controller

class AboutViewController: NSViewController {

    private var checkUpdatesButton: ActionLinkButton!

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    /// Every label here is baked from `L10n` when the view loads, so an open
    /// About window would keep the previous language after a menu switch.
    /// Rebuilding the subviews (instead of the whole controller) keeps the
    /// window's size and position intact.
    func reloadForLanguageChange() {
        for subview in view.subviews {
            subview.removeFromSuperview()
        }
        setupUI()
    }

    private func setupUI() {
        let container = view

        // ═══════════════════════════════════════════════════════════
        // Left Panel — App Info
        // ═══════════════════════════════════════════════════════════

        let leftPanel = NSView()
        leftPanel.translatesAutoresizingMaskIntoConstraints = false

        // App icon
        let iconImageView = NSImageView()
        iconImageView.image = NSImage(named: "main")
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // App name & version
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? AppConstants.appName
        let appVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?.?.?"

        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: appVersion)
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        // "check for updates" link
        checkUpdatesButton = ActionLinkButton(
            title: L10n.t(.checkForUpdates),
            target: self,
            action: #selector(checkForUpdatesClicked)
        )

        // "Author" section — the person maintaining this build. The upstream
        // author gets its own line below; calling deseven "the author" of an
        // app that has its own name, icon, updater and behaviour would be
        // misleading.
        let createdByLabel = NSTextField(labelWithString: L10n.t(.createdBy))
        createdByLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        createdByLabel.textColor = .secondaryLabelColor
        createdByLabel.alignment = .center
        createdByLabel.translatesAutoresizingMaskIntoConstraints = false

        let authorLink = LinkButton(title: "solitudechn", url: BundleIdentity.repositoryURL)

        // "Upstream author" section — where the code this app grew out of
        // lives. The link goes to the repository rather than a marketing site:
        // for someone running this app, "where does it come from" is the
        // useful question, and the answer is the source.
        let upstreamByLabel = NSTextField(labelWithString: L10n.t(.upstreamBy))
        upstreamByLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        upstreamByLabel.textColor = .secondaryLabelColor
        upstreamByLabel.alignment = .center
        upstreamByLabel.translatesAutoresizingMaskIntoConstraints = false

        let desevenLink = LinkButton(title: "deseven", url: AppConstants.upstreamRepoURL)

        // "Original code" section
        let originalCodeByLabel = NSTextField(labelWithString: L10n.t(.originalCodeBy))
        originalCodeByLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        originalCodeByLabel.textColor = .secondaryLabelColor
        originalCodeByLabel.alignment = .center
        originalCodeByLabel.translatesAutoresizingMaskIntoConstraints = false

        let fikriLink = LinkButton(title: "Fikri Karim", url: AppConstants.originalRepoURL)

        // "icons by" section
        let iconsByLabel = NSTextField(labelWithString: L10n.t(.iconsBy))
        iconsByLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        iconsByLabel.textColor = .secondaryLabelColor
        iconsByLabel.alignment = .center
        iconsByLabel.translatesAutoresizingMaskIntoConstraints = false

        let boxiconsLink = LinkButton(title: "boxicons", url: AppConstants.boxiconsURL)

        // Link to this project. The upstream project's own social links (Ko-fi,
        // Discord, Reddit) are deliberately not repeated here: they point at
        // someone else's donation and community pages.
        let githubButton = makeIconButton(imageName: "bx-github", url: BundleIdentity.repositoryURL)

        let socialStack = NSStackView()
        socialStack.orientation = .horizontal
        socialStack.spacing = 16
        socialStack.translatesAutoresizingMaskIntoConstraints = false
        socialStack.addView(githubButton, in: .center)

        // Add all subviews to left panel
        let leftSubviews: [NSView] = [
            iconImageView, nameLabel, versionLabel, checkUpdatesButton,
            createdByLabel, authorLink,
            upstreamByLabel, desevenLink,
            originalCodeByLabel, fikriLink,
            iconsByLabel, boxiconsLink,
            socialStack,
        ]
        for sv in leftSubviews {
            leftPanel.addSubview(sv)
        }

        // Layout constants
        let iconSize: CGFloat = 96
        let tightGap: CGFloat = 2
        let sectionGap: CGFloat = 14

        NSLayoutConstraint.activate([
            // Icon
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),
            iconImageView.topAnchor.constraint(equalTo: leftPanel.topAnchor, constant: 16),
            iconImageView.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // App name
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 6),
            nameLabel.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // Version
            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: tightGap),
            versionLabel.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // Check for updates
            checkUpdatesButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: tightGap),
            checkUpdatesButton.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // "Author"
            createdByLabel.topAnchor.constraint(
                equalTo: checkUpdatesButton.bottomAnchor, constant: sectionGap),
            createdByLabel.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // author link
            authorLink.topAnchor.constraint(equalTo: createdByLabel.bottomAnchor, constant: tightGap),
            authorLink.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // "Upstream author"
            upstreamByLabel.topAnchor.constraint(equalTo: authorLink.bottomAnchor, constant: sectionGap),
            upstreamByLabel.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // deseven link
            desevenLink.topAnchor.constraint(equalTo: upstreamByLabel.bottomAnchor, constant: tightGap),
            desevenLink.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // "Original code"
            originalCodeByLabel.topAnchor.constraint(equalTo: desevenLink.bottomAnchor, constant: sectionGap),
            originalCodeByLabel.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // Fikri Karim link
            fikriLink.topAnchor.constraint(equalTo: originalCodeByLabel.bottomAnchor, constant: tightGap),
            fikriLink.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // "Icons"
            iconsByLabel.topAnchor.constraint(equalTo: fikriLink.bottomAnchor, constant: sectionGap),
            iconsByLabel.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // boxicons link
            boxiconsLink.topAnchor.constraint(equalTo: iconsByLabel.bottomAnchor, constant: tightGap),
            boxiconsLink.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),

            // Social icons
            socialStack.topAnchor.constraint(equalTo: boxiconsLink.bottomAnchor, constant: sectionGap + 5),
            socialStack.centerXAnchor.constraint(equalTo: leftPanel.centerXAnchor),
            socialStack.bottomAnchor.constraint(lessThanOrEqualTo: leftPanel.bottomAnchor, constant: -16),
        ])

        // ═══════════════════════════════════════════════════════════
        // Separator
        // ═══════════════════════════════════════════════════════════

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // ═══════════════════════════════════════════════════════════
        // Right Panel — License
        // ═══════════════════════════════════════════════════════════

        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .bezelBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            textView.textColor = .textColor
            textView.backgroundColor = .textBackgroundColor
            textView.drawsBackground = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.string = Self.loadLicenseText()
        }

        // ═══════════════════════════════════════════════════════════
        // Main Layout
        // ═══════════════════════════════════════════════════════════

        container.addSubview(leftPanel)
        container.addSubview(separator)
        container.addSubview(scrollView)

        let outerPad: CGFloat = 20
        let leftPanelWidth: CGFloat = 200
        let columnGap: CGFloat = 16

        NSLayoutConstraint.activate([
            // Left panel
            leftPanel.topAnchor.constraint(equalTo: container.topAnchor, constant: outerPad),
            leftPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: outerPad),
            leftPanel.widthAnchor.constraint(equalToConstant: leftPanelWidth),
            leftPanel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -outerPad),

            // Separator
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: outerPad),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -outerPad),
            separator.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: columnGap),

            // Right panel
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: outerPad),
            scrollView.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: columnGap),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -outerPad),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -outerPad),
        ])
    }

    // MARK: - Update Check

    /// Sparkle owns the whole update flow — checking, downloading, installing,
    /// the "you're up to date" dialog and every failure message — so this link
    /// only has to kick it off. `nil` sender keeps Sparkle from trying to bind
    /// the check to a menu item it does not know about.
    @objc private func checkForUpdatesClicked() {
        Updater.shared.checkForUpdates(nil)
    }

    // MARK: - Helpers

    private static func loadLicenseText() -> String {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            return text
        }
        return L10n.t(.licenseUnavailable)
    }

    private func makeIconButton(imageName: String, url: String) -> LinkButton {
        let originalImage = NSImage(named: imageName)
        let image =
            (originalImage?.copy() as? NSImage)
            ?? NSImage(size: NSSize(width: 24, height: 24))
        image.isTemplate = true
        image.size = NSSize(width: 24, height: 24)
        return LinkButton(image: image, url: url)
    }
}
