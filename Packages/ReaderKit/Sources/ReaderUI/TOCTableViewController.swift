import ReaderCore
import UIKit

/// Table view controller for displaying the table of contents
/// Automatically scrolls to the current chapter on appearance
final class TOCTableViewController: UITableViewController {
    private let tocItems: [TOCItem]
    private let currentSpineIndex: Int
    private let onSelectChapter: (TOCItem) -> Void

    init(tocItems: [TOCItem], currentSpineIndex: Int, onSelectChapter: @escaping (TOCItem) -> Void) {
        self.tocItems = tocItems
        self.currentSpineIndex = currentSpineIndex
        self.onSelectChapter = onSelectChapter
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TOCCell")
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        // Set preferred content size for popover
        let rowHeight: CGFloat = 44
        let maxVisibleRows: CGFloat = 12
        let contentHeight = min(CGFloat(tocItems.count), maxVisibleRows) * rowHeight
        preferredContentSize = CGSize(width: 320, height: contentHeight)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Find and scroll to current chapter
        if let currentIndex = tocItems.firstIndex(where: { $0.sectionIndex == currentSpineIndex }) {
            let indexPath = IndexPath(row: currentIndex, section: 0)
            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        }
    }

    // MARK: - UITableViewDataSource

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        tocItems.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TOCCell", for: indexPath)
        let item = tocItems[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.label
        cell.contentConfiguration = config

        // Checkmark for current chapter
        cell.accessoryType = item.sectionIndex == currentSpineIndex ? .checkmark : .none

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = tocItems[indexPath.row]
        dismiss(animated: true) { [onSelectChapter] in
            onSelectChapter(item)
        }
    }
}
