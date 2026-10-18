//
//  DebugReadout.swift
//  TgChatSideBar
//

import UIKit

/// 底部一条实时数字。这个 demo 的全部意义在于手感，而手感是靠一边动手指一边
/// 盯着数字调出来的——所以这是正经的组成部分，不是事后补的。
final class DebugReadout: UIView {

    struct Item {
        let title: String
        let value: String
    }

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        // 绝不吃触摸：它浮在 chat 页上面，而整个 demo 讲的就是哪个手势能到哪儿。
        isUserInteractionEnabled = false

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    func setItems(_ items: [Item]) {
        // 只在列数变化时重建；数值本身在手指按着的时候每帧都要重写。
        if stack.arrangedSubviews.count != items.count {
            for view in stack.arrangedSubviews {
                view.removeFromSuperview()
            }
            for _ in items {
                stack.addArrangedSubview(ColumnView())
            }
        }
        for (view, item) in zip(stack.arrangedSubviews, items) {
            (view as? ColumnView)?.apply(item)
        }
    }

    /// 一列：标题在上、数值在下。用等宽数字，否则数字一变宽度就变，整条读数
    /// 每帧都在抖。
    private final class ColumnView: UIView {

        private let titleLabel = UILabel()
        private let valueLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)

            titleLabel.font = .systemFont(ofSize: 9, weight: .medium)
            titleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
            titleLabel.textAlignment = .center

            valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            valueLabel.textColor = .white
            valueLabel.textAlignment = .center

            let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
            stack.axis = .vertical
            stack.spacing = 1
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) 未实现——本工程不使用 storyboard")
        }

        func apply(_ item: Item) {
            if titleLabel.text != item.title { titleLabel.text = item.title }
            if valueLabel.text != item.value { valueLabel.text = item.value }
        }
    }
}
