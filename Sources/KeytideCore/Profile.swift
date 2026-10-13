import Foundation
import CoreFoundation

public struct Profile: Codable, Equatable {
    public var version = 1
    public var enabled = true
    public var spelling = true
    public var learning = false
    public var undo = Shortcut.undo
    public var protect = Shortcut.protect
    public var protectedWords: [String] = []
    public var rejectedWords: [String: Int] = [:]
    // Code editors and terminals: identifiers there are not prose, `len` would become `дут`.
    public var excludedApps = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "com.google.android.studio", "dev.zed.Zed",
        "com.sublimetext.4", "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce", "com.jetbrains.WebStorm", "com.jetbrains.goland", "com.jetbrains.CLion",
        "com.jetbrains.rider", "com.jetbrains.rustrover", "com.jetbrains.PhpStorm", "com.jetbrains.datagrip"]
    public var englishSource: String?
    public var russianSource: String?
    public init() {}

    public var immuneWords: Set<String> {
        var result = Set(protectedWords.map(Words.normalized))
        if learning { result.formUnion(rejectedWords.filter { $0.value >= 2 }.keys.map(Words.normalized)) }
        return result
    }

    // Words two undos made immune: the list the settings show and let the owner forget.
    public var learnedWords: [String] { rejectedWords.filter { $0.value >= 2 }.keys.sorted() }

    public mutating func forget(_ word: String) { rejectedWords[Words.normalized(word)] = nil }

    // `run`: what was typed, punctuation included; its word is what is learned.
    public mutating func recordUndo(_ run: String) {
        let word = Words.core(run)
        guard learning, Words.language(of: word) != nil else { return }
        let key = Words.normalized(word)
        guard rejectedWords.count < 2_500 || rejectedWords[key] != nil else { return }
        rejectedWords[key] = min(2, (rejectedWords[key] ?? 0) + 1)
    }

    public static let maximumBytes = 1_048_576
    public static func decode(_ data: Data, complete: Bool = false) throws -> (Profile, [String]) {
        guard data.count <= maximumBytes else { throw ProfileError.tooLarge }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = dict["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1 else { throw ProfileError.unsupported }
        if complete {
            let required: Set<String> = ["version", "enabled", "spelling", "learning", "undo", "protect",
                "protectedWords", "rejectedWords", "excludedApps"]
            guard required.isSubset(of: Set(dict.keys)),
                  Set(dict.keys).isSubset(of: required.union(["englishSource", "russianSource"])) else {
                throw ProfileError.unsupported
            }
        }
        var result = Profile(), warnings: [String] = []
        func boolean(_ key: String, _ fallback: Bool) -> Bool {
            guard let value = dict[key] else { return fallback }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                warnings.append(key); return fallback
            }
            return number.boolValue
        }
        result.enabled = boolean("enabled", true)
        if !["enabled", "undo", "protect", "excludedApps"].allSatisfy({ dict[$0] != nil }) {
            result.enabled = false
        }
        result.spelling = boolean("spelling", true)
        result.learning = boolean("learning", false)
        func shortcut(_ key: String, _ fallback: Shortcut) -> Shortcut {
            guard let object = dict[key] else { return fallback }
            guard JSONSerialization.isValidJSONObject(object),
                  let bytes = try? JSONSerialization.data(withJSONObject: object),
                  let value = try? JSONDecoder().decode(Shortcut.self, from: bytes), value.valid else {
                warnings.append(key); return fallback
            }
            return value
        }
        result.undo = shortcut("undo", .undo)
        result.protect = shortcut("protect", .protect)
        if result.undo.overlaps(result.protect) {
            result.undo = .undo; result.protect = .protect; warnings.append("shortcuts")
        }
        if let words = dict["protectedWords"] as? [String], words.count <= 10_000 {
            result.protectedWords = Array(Set(words.filter { Words.language(of: $0) != nil }.map(Words.normalized))).sorted()
            if result.protectedWords.count != Set(words.map(Words.normalized)).count { warnings.append("protectedWords") }
        } else if dict["protectedWords"] != nil { warnings.append("protectedWords") }
        if let learned = dict["rejectedWords"] as? [String: Int], learned.count <= 2_500 {
            for (word, count) in learned where Words.language(of: word) != nil && (1...2).contains(count) {
                result.rejectedWords[Words.normalized(word)] = count
            }
            if result.rejectedWords.count != learned.count { warnings.append("rejectedWords") }
        } else if dict["rejectedWords"] != nil { warnings.append("rejectedWords") }
        if let apps = dict["excludedApps"] as? [String], apps.count <= 200 {
            result.excludedApps = Array(Set(apps.filter { validIdentifier($0) })).sorted()
            if result.excludedApps.count != Set(apps).count { warnings.append("excludedApps") }
        } else if dict["excludedApps"] != nil { warnings.append("excludedApps") }
        for key in ["englishSource", "russianSource"] {
            if let id = dict[key] as? String, validIdentifier(id) {
                if key == "englishSource" { result.englishSource = id } else { result.russianSource = id }
            } else if dict[key] != nil { warnings.append(key) }
        }
        return (result, warnings)
    }

    public static func validIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 256 && text.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0)
        }
    }
}

public enum ProfileError: LocalizedError {
    case unsupported, tooLarge
    // Looked up in the app's Localizable.strings (Bundle.main) at run time.
    public var errorDescription: String? {
        switch self {
        case .unsupported: return NSLocalizedString("profile.error.unsupported", comment: "")
        case .tooLarge: return NSLocalizedString("profile.error.tooLarge", comment: "")
        }
    }
}
