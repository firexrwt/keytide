import AppKit

// Shared building blocks of the settings panes, so every tab has one look.
enum Form {
    static let inset: CGFloat = 20
    static let width: CGFloat = 600

    static var textWidth: CGFloat { width - 2 * inset }

    // A pane's own line for the result of its actions (export, report), under its buttons. Two lines are reserved,
    // so a longer message does not change the pane's height.
    static func status() -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.preferredMaxLayoutWidth = textWidth
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return field
    }

    static func pane() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        return stack
    }

    static func label(_ title: String, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: title)
        field.font = bold ? .systemFont(ofSize: 14, weight: .semibold) : .systemFont(ofSize: 12)
        field.textColor = bold ? .labelColor : .secondaryLabelColor
        // Without it a wrapping label measures as one line, and the page would be sized too short.
        field.preferredMaxLayoutWidth = textWidth
        return field
    }

    static func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
        NSButton(title: title, target: target, action: action)
    }

    static func row(_ views: NSView...) -> NSStackView {
        let row = NSStackView(views: views); row.spacing = 8; return row
    }

    static func add(_ views: NSView..., to stack: NSStackView) {
        for view in views {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * inset).isActive = true
        }
    }
}

// A borderless button that opens its link in the browser. Only https links to the project's own sites.
final class LinkButton: NSButton {
    private static let hosts: Set<String> = ["firexrwt.com", "github.com"]
    private let link: URL

    init(_ title: String, _ link: URL) {
        assert(link.scheme == "https" && Self.hosts.contains(link.host ?? ""), "unexpected link")
        self.link = link
        super.init(frame: .zero)
        self.title = title; isBordered = false; contentTintColor = .linkColor
        target = self; action = #selector(follow)
        setAccessibilityRole(.link)
        toolTip = link.absoluteString
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // A link shows the pointing hand, not only its color.
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    @objc private func follow() { NSWorkspace.shared.open(link) }
}
