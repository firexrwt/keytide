import Carbon
import KeytideCore

final class InputSources {
    struct Stroke {
        let key: UInt16
        let shift: Bool
        let character: Character
    }
    struct Entry {
        let id: String
        let name: String
        let language: Language
        let source: TISInputSource
    }
    private(set) var entries: [Entry] = []
    private(set) var english: Entry?
    private(set) var russian: Entry?
    private(set) var map: LayoutMap?
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var configuration = Profile()
    private var strokes: [String: [Character: Stroke]] = [:]

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in self?.onChange?() }
    }

    deinit { if let observer { DistributedNotificationCenter.default().removeObserver(observer) } }

    var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return Self.property(source, kTISPropertyInputSourceID) as? String
    }

    func configure(_ profile: Profile) {
        guard map == nil || entries.isEmpty || configuration.englishSource != profile.englishSource ||
              configuration.russianSource != profile.russianSource else { return }
        configuration = profile
        entries = []; english = nil; russian = nil; map = nil; strokes = [:]
        let filter = [kTISPropertyInputSourceIsEnabled as String: true,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        entries = list.compactMap { source in
            guard let id = Self.property(source, kTISPropertyInputSourceID) as? String,
                  let name = Self.property(source, kTISPropertyLocalizedName) as? String,
                  let languages = Self.property(source, kTISPropertyInputSourceLanguages) as? [String],
                  let language = languages.compactMap({ Language(rawValue: String($0.prefix(2))) }).first,
                  Self.property(source, kTISPropertyUnicodeKeyLayoutData) != nil else { return nil }
            return Entry(id: id, name: name, language: language, source: source)
        }
        let current = currentID
        func choose(_ language: Language, _ preferred: String?) -> Entry? {
            let options = entries.filter { $0.language == language }
            return options.first { $0.id == preferred } ?? options.first { $0.id == current } ?? options.first
        }
        english = choose(.en, profile.englishSource)
        russian = choose(.ru, profile.russianSource)
        guard let english, let russian else { map = nil; return }
        var forward: [Character: Character] = [:], backward: [Character: Character] = [:]
        for key in UInt16(0)..<UInt16(51) {
            for shift in [false, true] {
                guard let a = Self.translate(key, shift: shift, source: english.source),
                      let b = Self.translate(key, shift: shift, source: russian.source) else { continue }
                if strokes[english.id]?[a] == nil {
                    strokes[english.id, default: [:]][a] = Stroke(key: key, shift: shift, character: a)
                }
                if strokes[russian.id]?[b] == nil {
                    strokes[russian.id, default: [:]][b] = Stroke(key: key, shift: shift, character: b)
                }
                guard a != b else { continue }
                forward[a] = b; backward[b] = a
            }
        }
        map = LayoutMap(englishToRussian: forward, russianToEnglish: backward)
    }

    func reload() { entries = []; configure(configuration) }

    func targetID(_ language: Language) -> String? { language == .en ? english?.id : russian?.id }

    func keystrokes(_ word: String, source: String) -> [Stroke]? {
        guard Words.language(of: word) != nil, let keys = strokes[source] else { return nil }
        let result = word.compactMap { keys[$0] }
        return result.count == word.count ? result : nil
    }

    func stroke(_ character: Character, source: String) -> Stroke? { strokes[source]?[character] }

    func select(_ id: String) -> Bool {
        if currentID == id { return true }
        guard let entry = entries.first(where: { $0.id == id }), TISSelectInputSource(entry.source) == noErr else { return false }
        return currentID == id
    }

    static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func translate(_ key: UInt16, shift: Bool, source: TISInputSource) -> Character? {
        guard let object = property(source, kTISPropertyUnicodeKeyLayoutData), CFGetTypeID(object) == CFDataGetTypeID() else { return nil }
        let data = unsafeBitCast(object, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let result = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), shift ? 2 : 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &length, &chars)
        guard result == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        return text.count == 1 && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? text.first : nil
    }
}
