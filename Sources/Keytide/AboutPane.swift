import AppKit
import KeytideCore

// Settings, About tab: what this build is, where it comes from, and how to report a problem with it.
final class AboutPane: NSObject {
    let view = Form.pane()
    private let store: ProfileStore
    private let engine: Coordinator
    private let updater: Updater
    private let status = Form.status()
    private let window: () -> NSWindow?
    private let diagnostics = NSButton(checkboxWithTitle: tr("about.diagnostics"), target: nil, action: nil)

    init(store: ProfileStore, engine: Coordinator, updater: Updater, window: @escaping () -> NSWindow?) {
        self.store = store; self.engine = engine; self.updater = updater; self.window = window
        super.init()
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.setAccessibilityElement(false)  // decorative: the name follows it
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = Form.label("Keytide", bold: true); name.font = .systemFont(ofSize: 20, weight: .semibold)
        let info = Bundle.main.infoDictionary ?? [:]
        let identity = NSStackView(views: [name, Form.label(tr("about.version",
                info["CFBundleShortVersionString"] as? String ?? "?", info["CFBundleVersion"] as? String ?? "?")),
            Form.label(Self.signature),
            Form.label(tr("about.system", DiagnosticReport.system, DiagnosticReport.architecture))])
        identity.orientation = .vertical; identity.alignment = .leading; identity.spacing = 2
        let header = Form.row(icon, identity); header.spacing = 14
        diagnostics.target = self; diagnostics.action = #selector(toggleDiagnostics)
        InputDiagnostics.onChange = { [weak self] in self?.refresh() }
        let site = URL(string: "https://firexrwt.com")!, repo = URL(string: "https://github.com/firexrwt/keytide")!
        Form.add(header, Form.label(tr("about.tagline")),
                 Form.label(tr("about.links"), bold: true),
                 Form.row(LinkButton(tr("about.site"), site), LinkButton(tr("about.repo"), repo)),
                 Form.row(LinkButton(tr("about.releases"), repo.appendingPathComponent("releases")),
                          LinkButton(tr("about.license"), repo.appendingPathComponent("blob/main/LICENSE"))),
                 Form.row(Form.button(tr("about.checkUpdates"), self, #selector(checkUpdates))),
                 Form.label(tr("about.help"), bold: true), diagnostics,
                 Form.row(Form.button(tr("about.saveReport"), self, #selector(saveReport)),
                          Form.button(tr("about.reportBug"), self, #selector(reportBug))),
                 Form.label(tr("about.report.note")), status, to: view)
    }

    private func show(_ message: String) { status.stringValue = message }

    func refresh() { diagnostics.state = InputDiagnostics.enabled ? .on : .off }

    private static var signature: String {
        switch UpdateInstaller.signature {
        case .keytide: return tr("about.signed")
        case .other: return tr("about.signedOther")
        case .adhoc: return tr("about.adhoc")
        }
    }

    // The request may take up to 20 s: say so until the answer (a window) comes.
    @objc private func checkUpdates() {
        show(tr("update.checking"))
        updater.check(manual: true) { [weak self] in self?.show("") }
    }
    @objc private func toggleDiagnostics() { InputDiagnostics.setEnabled(diagnostics.state == .on) }
    @objc private func reportBug() { if let link = DiagnosticReport.bugLink { NSWorkspace.shared.open(link) } }
    // The whole report is shown first, and exactly that text is saved: nothing leaves without being seen.
    @objc private func saveReport() {
        guard let window = window(), window.attachedSheet == nil else { return }
        let report = DiagnosticReport.text(store: store, engine: engine, updater: updater)
        let preview = NSAlert()
        preview.messageText = tr("about.preview.title")
        preview.informativeText = tr("about.preview.text")
        preview.accessoryView = Self.reportView(report)
        preview.addButton(withTitle: tr("about.preview.save"))
        preview.addButton(withTitle: tr("about.preview.cancel"))
        preview.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            save(report, from: window)
        }
    }

    private func save(_ report: String, from window: NSWindow) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Keytide-report.txt"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            do { try SecureFile.write(Data(report.utf8), to: url); show(tr("about.reportSaved")) }
            catch { show(tr("about.reportFailed", error.localizedDescription)) }
        }
    }

    private static func reportView(_ report: String) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 280)
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false; text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.string = report
            text.setAccessibilityLabel(tr("about.preview.title"))
        }
        return scroll
    }
}
