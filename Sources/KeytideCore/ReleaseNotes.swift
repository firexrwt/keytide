// What changed in each version, in plain words, shown once after an update. Every release adds its entry here;
// ReleaseNotesTests fails the release CI when the shipped version has none. ASCII hyphen only.
public enum ReleaseNotes {
    static let notes: [String: [String]] = [
        "0.1.2": [
            "Исправляется слово целиком, даже если вы дописываете его посреди текста. Обрывки слов больше не попадают в выученные.",
            "Keytide читает поле ввода в Raycast, а также в Claude и других приложениях на Electron, поэтому исправляет точнее.",
            "Английские сокращения, набранные в русской раскладке, теперь исправляются: let's, don't, I'm.",
            "После каждого обновления это окно рассказывает, что изменилось.",
        ],
    ]

    public static func lines(for version: String) -> [String]? { notes[version] }
}
