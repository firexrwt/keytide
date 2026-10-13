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
        "0.1.4": [
            "ru": [
                "Отчёт для сообщения об ошибке теперь анонимный: приложения в нём под номерами, без времени и без длины набранных слов. Перед сохранением вы видите его целиком.",
                "Подробная диагностика сама выключается через 30 минут.",
            ],
            "en": [
                "The bug report is anonymous now: apps appear as numbers, with no times and no lengths of typed words. You see all of it before saving.",
                "Detailed diagnostics turn themselves off after 30 minutes.",
            ],
        ],
        "0.1.5": [
            "ru": [
                "Значок в строке меню тускнеет, когда Keytide не исправляет: на паузе, без доступа, после сбоя или без нужной раскладки.",
                "Добавили или убрали раскладку в настройках системы - Keytide заметит это сам, без перезапуска.",
                "Option отменяет исправление только в первые 10 секунд после него: случайное нажатие позже ничего не вернёт.",
                "Прокрутка больше не проходит через Keytide.",
            ],
            "en": [
                "The menu bar icon dims while Keytide is not correcting: paused, without access, after a failure or without a layout it needs.",
                "Add or remove a layout in System Settings and Keytide notices it by itself, no restart needed.",
                "Option undoes a correction only within 10 seconds of it: a stray press later brings nothing back.",
                "Scrolling no longer passes through Keytide.",
            ],
        ],
        "0.1.6": [
            "ru": [
                "Исправляются слова с буквами, которые стоят на клавишах знаков препинания: «Юлить», «Эхом», «нож», «люблю», набранные не в той раскладке.",
                "Знаки после слова переводятся вместе с ним: «привет.» и «привет,» не в той раскладке становятся «привет.» и «привет,», а «нож» больше не превращается в «но;».",
                "В Заметках и TextEdit исправляются и слова, которые начинаются с кавычки-буквы «э».",
            ],
            "en": [
                "Words with letters on punctuation keys are corrected: Юлить, Эхом, нож, люблю typed in the wrong layout.",
                "Punctuation after a word is converted with it: привет. and привет, typed in the wrong layout come out right, and нож no longer turns into но;.",
                "In Notes and TextEdit, words starting with э (the quote key) are corrected too.",
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
