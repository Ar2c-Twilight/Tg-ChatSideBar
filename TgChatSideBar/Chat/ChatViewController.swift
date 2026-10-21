//
//  ChatViewController.swift
//  TgChatSideBar
//

import UIKit

/// 占位的 chat 页。
///
/// 它里面装的是一个**真的滚动视图**、塞满假气泡，而不是一张静态图——因为这个 demo
/// 里一半的手势工作就是 SGB 和纵向滚动如何共存，静态占位会让那类 bug 藏起来。
final class ChatViewController: UIViewController, ChatPage {

    let chat: Chat

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let header = ChatPageHeaderView()
    private let bubbles: [(text: String, isOutgoing: Bool)]

    /// 从容器的安全区捕获——见 `ChatListViewController` 里的说明。这一页会横向
    /// 平移，所以它自己的 `safeAreaInsets` 拿来布局是没用的。
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard contentInsets != oldValue else { return }
            view.setNeedsLayout()
        }
    }

    init(chat: Chat) {
        self.chat = chat
        // 每个 chat 确定性地生成，这样来回切看起来是同一段会话，而不是每次都是
        // 一堆新的随机噪声。
        var generator = SeededGenerator(seed: UInt64(chat.id &+ 1))
        self.bubbles = (0..<40).map { index in
            let length = Int.random(in: 1...4, using: &generator)
            let text = Array(repeating: "这是一条占位消息", count: length).joined(separator: "，")
            return (text, index % 3 == 0)
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .secondarySystemBackground

        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.register(BubbleCell.self, forCellReuseIdentifier: BubbleCell.reuseIdentifier)
        view.addSubview(tableView)

        header.configure(with: chat)
        view.addSubview(header)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bounds = view.bounds
        header.topInset = contentInsets.top
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: header.preferredHeight)

        tableView.frame = bounds
        tableView.contentInset = UIEdgeInsets(top: header.preferredHeight + 8, left: 0,
                                              bottom: contentInsets.bottom + 8, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: header.preferredHeight, left: 0,
                                                               bottom: contentInsets.bottom, right: 0)
    }
}

extension ChatViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        bubbles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: BubbleCell.reuseIdentifier,
                                                 for: indexPath) as! BubbleCell
        let bubble = bubbles[indexPath.row]
        cell.configure(text: bubble.text, isOutgoing: bubble.isOutgoing, tint: chat.tint)
        return cell
    }
}

/// `SystemRandomNumberGenerator` 不可复现，而占位文本需要对每个 chat 稳定，
/// 否则切来切去会一直重新洗牌。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
