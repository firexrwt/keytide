// What changed in each version, in plain words, in English and Russian, shown once after an update. Every release
// adds its entry here; ReleaseNotesTests fails the release CI when the shipped version lacks either language.
// ASCII hyphen only.
public enum ReleaseNotes {
    static let notes: [String: [String: [String]]] = [
        "0.1.2": [
            "ru": [
                "Исправляется слово целиком, даже если вы дописываете его посреди текста. Обрывки слов больше не попадают в выученные.",
                "Keytide читает поле ввода в Raycast, а также в Claude и других приложениях на Electron, поэтому исправляет точнее.",
                "Английские сокращения, набранные в русской раскладке, теперь исправляются: let's, don't, I'm.",
                "После каждого обновления это окно рассказывает, что изменилось.",
            ],
            "en": [
                "A word is corrected whole, even when you finish it in the middle of a text. Word fragments are no longer learned.",
                "Keytide reads the input field in Raycast, Claude and other Electron apps, so it corrects more precisely.",
                "English contractions typed in the Russian layout are corrected now: let's, don't, I'm.",
                "After every update this window tells what changed.",
            ],
        ],
        "0.1.3": [
            "ru": [
                "Интерфейс на английском: Keytide говорит на языке вашей системы.",
                "Новая вкладка «О приложении»: версия, ссылки, диагностика и кнопка «Сообщить об ошибке», которая открывает готовую форму на GitHub. Её же открывает пункт «О Keytide» в меню.",
                "«Проверить обновления» теперь показывает окно: ваша версия актуальна или вышла новая, с кнопкой «Обновить».",
                "Настройки разложены по вкладкам.",
            ],
            "en": [
                "English interface: Keytide speaks the language of your system.",
                "New About tab: version, links, diagnostics and a Report a bug button that opens a ready form on GitHub. The About Keytide menu item opens it too.",
                "Check for Updates now shows a window: your version is current or a newer one is out, with an Update button.",
                "Settings are split into tabs.",
            ],
        ],
    ]

    // `language`: "ru" or "en"; anything else gets English.
    public static func lines(for version: String, language: String) -> [String]? {
        guard let entry = notes[version] else { return nil }
        return entry[language] ?? entry["en"]
    }

    static func languages(for version: String) -> [String] { notes[version].map { Array($0.keys) } ?? [] }
}
