import AppKit

// The settings window in the native macOS style: tabs with icons in the toolbar, the window title follows the tab,
// and the window takes the height of each pane.
final class SettingsWindow: NSObject {
    enum Tab: Int { case general, words, about }
    private let window: NSWindow
    private let tabs = NSTabViewController()
    private var general: GeneralPane!
    private var words: WordsPane!
    private var about: AboutPane!

    init(store: ProfileStore, engine: Coordinator, updater: Updater) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Form.width, height: 400),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        let host: () -> NSWindow? = { [weak self] in self?.window }
        general = GeneralPane(store: store, engine: engine, updater: updater)
        words = WordsPane(store: store, window: host)
        about = AboutPane(store: store, engine: engine, updater: updater, window: host)
        tabs.tabStyle = .toolbar
        for (title, symbol, view) in [(tr("settings.tab.general"), "gearshape", general.view),
                                      (tr("settings.tab.words"), "character.book.closed", words.view),
                                      (tr("settings.tab.about"), "info.circle", about.view)] {
            let item = NSTabViewItem(viewController: Self.page(view, title: title))
            item.label = title
            // The toolbar label already names the tab.
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
        refresh()
    }

    // A pane pinned to the top of a page as tall as the laid-out pane: the window resizes to each tab.
    private static func page(_ pane: NSStackView, title: String) -> NSViewController {
        let page = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Form.width, height: 400))
        container.addSubview(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: container.topAnchor),
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: Form.width),
        ])
        container.layoutSubtreeIfNeeded()
        page.view = container
        page.title = title
        page.preferredContentSize = NSSize(width: Form.width, height: container.fittingSize.height)
        return page
    }

    var isVisible: Bool { window.isVisible }

    func show(_ message: String) { general.show(message) }

    // `tab`: nil keeps the tab the window shows.
    func open(_ tab: Tab? = nil) {
        refresh()
        if let tab { tabs.selectedTabViewItemIndex = tab.rawValue }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        WhatsNew.showOnce(attachedTo: window)
    }

    func refresh() { general.refresh(); words.refresh(); about.refresh() }
}
