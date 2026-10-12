import AppKit
import UniformTypeIdentifiers
import KeytideCore

// Settings, Words tab: protected and learned words, excluded apps, profile export and import.
final class WordsPane: NSObject {
    let view = Form.pane()
    private let store: ProfileStore
    private let status = Form.status()
    private let window: () -> NSWindow?
    private let word = NSTextField(), apps = NSTextField()
    private let protectedList: WordTable
    private let learnedList: WordTable

    init(store: ProfileStore, window: @escaping () -> NSWindow?) {
        self.store = store; self.window = window
        protectedList = WordTable(label: tr("words.protected"), height: 100) { store.profile.protectedWords }
        learnedList = WordTable(label: tr("words.learned.list"), height: 80) { store.profile.learnedWords }
        super.init()
        word.placeholderString = tr("words.placeholder"); word.setAccessibilityLabel(tr("words.field.a11y"))
        apps.setAccessibilityLabel(tr("words.exclusions.a11y"))
        Form.add(Form.label(tr("words.protected"), bold: true),
                 Form.row(word, Form.button(tr("words.add"), self, #selector(addWord)),
                          Form.button(tr("words.remove"), self, #selector(removeWord))),
                 protectedList.scroll,
                 Form.row(Form.label(tr("words.learned"), bold: true),
                          Form.button(tr("words.forget"), self, #selector(forgetWord)),
                          Form.button(tr("words.forgetAll"), self, #selector(forgetAll))),
                 learnedList.scroll,
                 Form.label(tr("words.exclusions"), bold: true),
                 Form.row(apps, Form.button(tr("words.save"), self, #selector(exclusions))),
                 Form.row(Form.button(tr("words.export"), self, #selector(exportProfile)),
                          Form.button(tr("words.import"), self, #selector(importProfile))),
                 Form.label(tr("words.profile.note")), status, to: view)
    }

    private func show(_ message: String) { status.stringValue = message }

    func refresh() {
        apps.stringValue = store.profile.excludedApps.joined(separator: ", ")
        protectedList.reload(); learnedList.reload()
    }

    @objc private func addWord() {
        let value = Words.normalized(word.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard Words.language(of: value) != nil, store.profile.protectedWords.count < 10_000 else {
            show(tr("words.invalidWord")); return
        }
        store.update { if !$0.protectedWords.contains(value) { $0.protectedWords.append(value); $0.protectedWords.sort() } }
        word.stringValue = ""
    }
    @objc private func removeWord() {
        guard let value = protectedList.selected else { return }
        store.update { $0.protectedWords.removeAll { $0 == value } }
    }
    @objc private func forgetWord() {
        guard let value = learnedList.selected else { return }
        store.update { $0.forget(value) }
    }
    // Clears all learning data, including words undone once and not yet immune.
    @objc private func forgetAll() { store.update { $0.rejectedWords = [:] } }
    @objc private func exclusions() {
        let values = apps.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.count <= 200, values.allSatisfy(Profile.validIdentifier) else { show(tr("words.invalidApps")); return }
        store.update { $0.excludedApps = Array(Set(values)).sorted() }
    }
    @objc private func exportProfile() {
        guard let window = window() else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Keytide-profile.json"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            do { try SecureFile.write(store.encoded(), to: url); show(tr("words.exported")) }
            catch { show(error.localizedDescription) }
        }
    }
    @objc private func importProfile() {
        guard let window = window() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            do { try store.importProfile(url); show(tr("words.imported")) }
            catch { show(error.localizedDescription) }
        }
    }
}
