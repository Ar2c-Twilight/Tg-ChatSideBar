//
//  ChatListViewController.swift
//  TgChatSideBar
//

import UIKit

/// 左栏。就是个普通 `UITableView`——有意思的活在 cell 的手工布局里，不在这儿。
final class ChatListViewController: UIViewController {

    var onSelect: ((Chat) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)

    /// 全出血直角的选中高亮。插在表的最底层，所以 cell 的内容画在它上面
    /// （cell 的背景是透明的）；它是表的子视图，于是跟着内容一起滚动。
    private let highlightView = UIView()
    private let titleLabel = UILabel()
    private let chats = Chat.samples

    /// 高亮框停在第几行——**连续值**，不是索引。`nil` 表示没有选中任何 chat
    /// （`.list` 全屏时就是这样），框隐藏。
    ///
    /// 做成连续值是为了纵向手势：手指纵向拖的时候框要在行与行之间平滑滑动，
    /// 停在 2.5 就意味着它正骑在第 2 行和第 3 行中间。这也是为什么它是覆盖在
    /// 表上的一个独立视图，而不再是每个 cell 自己的子视图——跨行滑动的东西不能
    /// 属于任何一行。
    var highlightRow: CGFloat? {
        didSet {
            guard highlightRow != oldValue else { return }
            layoutHighlight()
            updateSeparators()
        }
    }

    /// 侧栏的 `progress`。容器每帧下发，直接交给可见的 cell——这是**表现**不是
    /// 数据，所以绝不能碰 reload。
    var progress: CGFloat = 1 {
        didSet {
            guard progress != oldValue else { return }
            for case let cell as ChatListCell in tableView.visibleCells {
                cell.progress = progress
            }
        }
    }

    /// 行有多「像 peek」，0…1。和 `progress` 同一条投递路径：直接给可见 cell，
    /// 不走 reload。
    var peekBlend: CGFloat = 0 {
        didSet {
            guard peekBlend != oldValue else { return }
            for case let cell as ChatListCell in tableView.visibleCells {
                cell.peekBlend = peekBlend
            }
        }
    }

    /// 从*容器的*安全区捕获的内边距，而不是这个视图自己的。chat 那一栏会横向滑出
    /// 屏幕边缘，所以它自己的安全区每帧都在变；直接读的话内容会跟着手势一起抖。
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard contentInsets != oldValue else { return }
            view.setNeedsLayout()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.clipsToBounds = true

        titleLabel.text = "Chats"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        view.addSubview(titleLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        // 固定行高：这样宽度变化时 UITableView 不会重新测量行高，一次拖动只需要
        // 对那几个可见 cell 各跑一次 `layoutSubviews`，很便宜。
        tableView.rowHeight = SidebarMetrics.cellHeight
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        // 手工设内边距，理由同上面的 `contentInsets`。
        tableView.contentInsetAdjustmentBehavior = .never
        view.addSubview(tableView)

        highlightView.backgroundColor = .tertiarySystemFill
        highlightView.isUserInteractionEnabled = false
        tableView.insertSubview(highlightView, at: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bounds = view.bounds
        let titleHeight: CGFloat = 40
        titleLabel.frame = CGRect(x: SidebarMetrics.cellLeftInset,
                                  y: contentInsets.top + 4,
                                  width: Swift.max(0, bounds.width - SidebarMetrics.cellLeftInset * 2),
                                  height: titleHeight)
        let tableTop = contentInsets.top + titleHeight + 8
        tableView.frame = CGRect(x: 0, y: tableTop,
                                 width: bounds.width,
                                 height: Swift.max(0, bounds.height - tableTop))
        tableView.contentInset.bottom = contentInsets.bottom
        tableView.verticalScrollIndicatorInsets.bottom = contentInsets.bottom
        layoutHighlight()
    }

    private func layoutHighlight() {
        guard let highlightRow else {
            highlightView.isHidden = true
            return
        }
        highlightView.isHidden = false
        let height = SidebarMetrics.cellHeight
        highlightView.frame = CGRect(x: 0,
                                     y: highlightRow * height,
                                     width: tableView.bounds.width,
                                     height: height)
    }

    /// 直接遍历可见 cell 而不是 reload，和 TG 一个路子
    /// （`ChatListNode.updateSelectedChatLocation` → `forEachItemNode`）：选中态是
    /// 表现不是数据，它没有理由触发一次列表 diff。
    private func updateSeparators() {
        for case let cell as ChatListCell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            cell.hidesBottomSeparator = hidesSeparator(below: indexPath.row)
        }
    }

    /// 高亮框是全出血直角的，压在它上下两条边上的细线会正好横在它身上，所以要藏掉。
    ///
    /// 用框的实际跨度算，而不是「选中行和它上面那行」——框现在可以停在行与行之间，
    /// 那时候它同时压着两行的边界。框占据 `[highlightRow, highlightRow + 1]` 这段
    /// （单位是行），第 `row` 行底下那条线在 `row + 1` 处。
    private func hidesSeparator(below row: Int) -> Bool {
        guard let highlightRow else { return false }
        let boundary = CGFloat(row + 1)
        return boundary >= highlightRow && boundary <= highlightRow + 1
    }
}

extension ChatListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListCell.reuseIdentifier,
                                                 for: indexPath) as! ChatListCell
        cell.configure(with: chats[indexPath.row])
        cell.hidesBottomSeparator = hidesSeparator(below: indexPath.row)
        cell.progress = progress
        cell.peekBlend = peekBlend
        return cell
    }
}

extension ChatListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(chats[indexPath.row])
    }
}
