//
//  ChatPageHeaderView.swift
//  TgChatSideBar
//

import UIKit

/// 右栏每一页顶上那条标题栏：圆头像 + 名字。
///
/// 抽出来是因为聊天页和调试开关页共用它——两个页面的内容完全不同，但「这是右栏的
/// 某一页」这个外观应该一致。各写一份的话迟早会漂。
final class ChatPageHeaderView: UIView {

    static let contentHeight: CGFloat = 44

    private let avatarView = UIView()
    private let titleLabel = UILabel()

    /// 从容器捕获的安全区上缘。标题栏要把它让出来，但这一页会横向平移，所以不能读
    /// 自己的 `safeAreaInsets`。
    var topInset: CGFloat = 0 {
        didSet {
            guard topInset != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// 整条栏该多高（含让出的安全区）。
    var preferredHeight: CGFloat { topInset + ChatPageHeaderView.contentHeight }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .systemBackground

        avatarView.layer.cornerRadius = 15   // 30 的一半：圆形
        addSubview(avatarView)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    func configure(with chat: Chat) {
        avatarView.backgroundColor = chat.tint
        titleLabel.text = chat.name
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.frame = CGRect(x: 16, y: topInset + 7, width: 30, height: 30)
        titleLabel.frame = CGRect(x: 56, y: topInset + 10,
                                  width: Swift.max(0, bounds.width - 72), height: 24)
    }
}
