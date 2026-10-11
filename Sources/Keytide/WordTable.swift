import AppKit

// A one-column word list with its own data source. The words are read once per reload, not per row.
final class WordTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scroll = NSScrollView()
    private let table = NSTableView()
    private let source: () -> [String]
    private var words: [String] = []

    init(label: String, height: CGFloat, words source: @escaping () -> [String]) {
        self.source = source
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word")); column.title = label
        table.addTableColumn(column); table.headerView = nil; table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel(label)
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    var selected: String? { words.indices.contains(table.selectedRow) ? words[table.selectedRow] : nil }
    func reload() { words = source(); table.reloadData() }

    func numberOfRows(in tableView: NSTableView) -> Int { words.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        words.indices.contains(row) ? NSTextField(labelWithString: words[row]) : nil
    }
}
