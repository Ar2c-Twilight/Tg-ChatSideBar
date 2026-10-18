//
//  ChatListCell.swift
//  TgChatSideBar
//

import UIKit

/// 一行聊天列表。
///
/// 这一行**永远按整屏宽度布局**，chat 页滑上来就是单纯地盖住它——它从不重排、也
/// 不会被挤压去适应露出来的那条。这正是整个视觉想法：列表是一张躺在下面的页面，
/// 不是一个会变宽的列。跑到 chat 页底下的文字就是被遮住了，和被任何别的不透明
/// 视图遮住没有区别。
///
/// frame 是手写的，但**这不是一个有原则的选择**：这一行的几何完全静态（头像钉在
/// 左内边距、文字从固定的 x 起算），随状态变化的只有 `transform` 和 `alpha`，两者
/// 都不触发布局。换成 Auto Layout 完全可行，也不会有任何每帧开销。
///
/// （早先那一版 cell 会随列宽重排文字，那时手写才是必须的；设计废弃后理由就不成立了。）
final class ChatListCell: UITableViewCell {

    static let reuseIdentifier = "ChatListCell"

    private let avatarView = UIView()
    private let initialLabel = UILabel()
    private let nameLabel = UILabel()
    private let messageLabel = UILabel()
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none
        contentView.clipsToBounds = true

        avatarView.layer.cornerRadius = SidebarMetrics.avatarSize / 2
        avatarView.clipsToBounds = true
        contentView.addSubview(avatarView)

        initialLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center
        avatarView.addSubview(initialLabel)

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        contentView.addSubview(nameLabel)

        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .secondaryLabel
        contentView.addSubview(messageLabel)

        separator.backgroundColor = .separator
        contentView.addSubview(separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    /// 高亮框压着的那两条边上的 separator 要藏掉，否则会有细线横在框上。由列表
    /// 决定而不是在这里推导：高亮框现在是独立于 cell 的一个覆盖视图，cell 既看不见
    /// 它也看不见自己的邻居。
    var hidesBottomSeparator: Bool = false {
        didSet {
            guard hidesBottomSeparator != oldValue else { return }
            separator.isHidden = hidesBottomSeparator
        }
    }

    /// 侧栏的 `progress`：0 = chat 全屏（列表完全退到后面），1 = 列表全屏。
    var progress: CGFloat = 1 {
        didSet {
            guard progress != oldValue else { return }
            applyAppearance()
        }
    }

    /// 这一行有多「像 peek」，0…1。
    ///
    /// 它是第二个因子而不是 `progress` 的某个取值，因为 peek 把两个属性往*相反*
    /// 方向拉：头像回到满大小，文字一路拉到零。一个标量表达不了这个——
    /// `scale = 1` 只在 `progress = 1` 处出现，而那里 opacity 被钉死在 1。
    var peekBlend: CGFloat = 0 {
        didSet {
            guard peekBlend != oldValue else { return }
            applyAppearance()
        }
    }

    func configure(with chat: Chat) {
        avatarView.backgroundColor = chat.tint
        initialLabel.text = String(chat.name.prefix(1))
        nameLabel.text = chat.name
        messageLabel.text = chat.lastMessage
        setNeedsLayout()
    }

    // MARK: - 外观：两层插值

    // 两个因子各管一层，顺序是固定的：
    //
    //   第一层（progress）  列表被 chat 盖了多少 —— 盖得越多越往后退
    //   第二层（peekBlend） peek 覆盖 —— 把第一层的结果拉向 peek 的固定值
    //
    // 注意两个属性在第二层被拉往**相反**方向：头像回到满大小，文字一路到零。
    // 这正是一个标量表达不了、必须有两个因子的原因。

    /// 第一层：只看「被盖了多少」时头像该多大。
    private var buriedAvatarScale: CGFloat {
        lerp(SidebarMetrics.recededAvatarScale, 1, progress)
    }

    /// 第二层：再让 peekBlend 把它拉回满大小。
    private var avatarScale: CGFloat {
        lerp(buriedAvatarScale, SidebarMetrics.peekAvatarScale, peekBlend)
    }

    /// 第一层：只看「被盖了多少」时文字该多透。
    private var buriedTextOpacity: CGFloat {
        lerp(SidebarMetrics.recededTextOpacity, 1, progress)
    }

    /// 第二层：再让 peekBlend 把它拉到全隐。
    private var textOpacity: CGFloat {
        lerp(buriedTextOpacity, SidebarMetrics.peekTextOpacity, peekBlend)
    }

    /// 只写 `transform` 和 `alpha`——两者都不会让布局失效，所以这是拖动时每帧要做
    /// 的全部工作，`layoutSubviews` 不需要跟着跑。
    private func applyAppearance() {
        avatarView.transform = CGAffineTransform(scaleX: avatarScale, y: avatarScale)
        nameLabel.alpha = textOpacity
        messageLabel.alpha = textOpacity
    }

    // MARK: - 布局

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = contentView.bounds
        let inset = SidebarMetrics.cellLeftInset
        let avatar = SidebarMetrics.avatarSize


        // 先把 transform 置回 identity 再设 frame——带着 transform 赋 frame 的行为
        // 是未定义的。设完由 `applyAppearance()` 在末尾重新加上缩放。
        avatarView.transform = .identity
        avatarView.frame = CGRect(x: inset,
                                  y: (bounds.height - avatar) / 2,
                                  width: avatar,
                                  height: avatar)
        initialLabel.frame = avatarView.bounds

        let textLeft = inset + avatar + SidebarMetrics.cellTextGap
        let textWidth = Swift.max(0, bounds.width - textLeft - inset)

        nameLabel.frame = CGRect(x: textLeft, y: bounds.midY - 20,
                                 width: textWidth, height: 20)
        messageLabel.frame = CGRect(x: textLeft, y: bounds.midY + 2,
                                    width: textWidth, height: 18)

        let hairline = 1 / traitCollection.displayScale
        separator.frame = CGRect(x: textLeft,
                                 y: bounds.height - hairline,
                                 width: bounds.width - textLeft,
                                 height: hairline)

        applyAppearance()
    }
}
