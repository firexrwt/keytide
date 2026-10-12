import Foundation

// Interface strings come from Resources/<lang>.lproj/Localizable.strings; the language follows macOS (also the
// per-app language in System Settings). LocalizationTests checks both languages and every key used here.
// Arguments are strings only (%@): a number given to a %@ or a string to a %ld would crash at run time.
func tr(_ key: String, _ arguments: String...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

enum L10n {
    // "ru" or "en": the language the interface is shown in, for texts kept outside the strings files.
    static var language: String { Bundle.main.preferredLocalizations.first == "ru" ? "ru" : "en" }
}
