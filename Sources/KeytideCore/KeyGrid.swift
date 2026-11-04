// Where the keys sit on a Mac keyboard, by virtual key code: a typo fix that changes or adds a letter must be a slip
// of the finger onto a key next to the right one, not any letter (`LayoutMap.slip`). Positions are physical, so they
// hold for every layout: the app learns which key types which character from the enabled layouts themselves.
enum KeyGrid {
    // ANSI rows top to bottom, each row's left edge in key widths (Tab is 1.5 wide, Caps Lock 1.75, Left Shift 2.25).
    private static let rows: [(edge: Double, keys: [UInt16])] = [
        (0, [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]),
        (1.5, [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42]),
        (1.75, [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39]),
        (2.25, [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]),
    ]

    private static let places: [UInt16: (row: Int, x: Double)] = {
        var result: [UInt16: (row: Int, x: Double)] = [:]
        for (row, line) in rows.enumerated() {
            for (column, key) in line.keys.enumerated() { result[key] = (row, line.edge + Double(column)) }
        }
        return result
    }()

    // ISO moves three keys: "§" (10) is the top-left one, "`" (50) sits between Left Shift (1.25 wide) and Z, and "\"
    // (42, "ё" in Apple Russian) ends the home row next to "'" ("э"). Letter keys stay where they are.
    private static let isoPlaces = places.merging([10: (0, 0), 50: (3, 1.25), 42: (2, 12.75)]) { $1 }

    // The US keys of "qwertyuiop[]asdfghjkl;'zxcvbnm,./`" in that order: the test maps only.
    static let qwertyOrder: [UInt16] = Array(rows[1].keys.dropLast() + rows[2].keys + rows[3].keys) + [50]

    // Touching keys: left or right in the same row, or overlapping in the row above or below (two keys each).
    static func adjacent(_ a: UInt16, _ b: UInt16, iso: Bool = false) -> Bool {
        let places = iso ? isoPlaces : Self.places
        guard a != b, let p = places[a], let q = places[b] else { return false }
        let distance = abs(p.x - q.x)
        return p.row == q.row ? distance == 1 : abs(p.row - q.row) == 1 && distance < 1
    }
}

extension LayoutMap {
    // `typed` is `intended` with one slip (owner decision 2026-11-04): a key next to the right one instead of it, a key
    // next to or the same as the right one pressed with it, a key missed, or two keys swapped. A character the layout
    // types with no known key, or no layout at all, is no slip: the fix is refused.
    public func slip(_ typed: String, from intended: String, in language: Language) -> Bool {
        guard Words.oneEditApart(typed, intended), let keys = keys[language] else { return false }
        let a = Array(Words.normalized(typed)), b = Array(Words.normalized(intended))
        func near(_ x: Character, _ y: Character) -> Bool {
            guard let p = keys[x], let q = keys[y] else { return false }
            return KeyGrid.adjacent(p, q, iso: isoKeyboard)
        }
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        if a.count < b.count { return true }
        // Same length: one key swapped for another at `i`, or the keys at `i` and `i + 1` swapped.
        if a.count == b.count { return a[(i + 1)...] == b[(i + 1)...] ? near(a[i], b[i]) : true }
        // One key too many at `i` (the end of a run of one key, if any): beside the intended key before or after it.
        let around = [i > 0 ? b[i - 1] : nil, i < b.count ? b[i] : nil].compactMap { $0 }
        return around.contains { $0 == a[i] || near(a[i], $0) }
    }
}
