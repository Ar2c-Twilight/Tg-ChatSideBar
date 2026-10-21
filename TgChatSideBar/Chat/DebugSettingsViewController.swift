//
//  DebugSettingsViewController.swift
//  TgChatSideBar
//

import UIKit

/// 右栏的第一页：不放聊天气泡，放调试开关。
///
/// 它和 `ChatViewController` 是**并列的两个 `ChatPage`**，不是后者的一个分支——
/// 内容完全不同，共用的只有顶上那条标题栏和「要有个真的滚动视图」这个约束
/// （手势共存要靠它验证，开关页同样得满足）。
final class DebugSettingsViewController: UIViewController, ChatPage {

    let chat: Chat

    private let settings: DebugSettings
    private let header = ChatPageHeaderView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private struct Row {
        let title: String
        let detail: String
        let isOn: () -> Bool
        let setter: (Bool) -> Void
    }

    private var rows: [Row] = []

    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard contentInsets != oldValue else { return }
            view.setNeedsLayout()
        }
    }

    init(chat: Chat, settings: DebugSettings) {
        self.chat = chat
        self.settings = settings
        super.init(nibName: nil, bundle: nil)

        rows = [
            Row(title: "实时读数",
                detail: "底部那条 progress / 动量 / 预告",
                isOn: { [settings] in settings.showsReadout },
                setter: { [settings] in settings.showsReadout = $0 }),
            Row(title: "容许窗口",
                detail: "SGB 进行中的红框与吸附点红线",
                isOn: { [settings] in settings.showsThresholdOverlay },
                setter: { [settings] in settings.showsThresholdOverlay = $0 }),
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .secondarySystemBackground

        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.register(ToggleCell.self, forCellReuseIdentifier: ToggleCell.reuseIdentifier)
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

extension DebugSettingsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ToggleCell.reuseIdentifier,
                                                 for: indexPath) as! ToggleCell
        let row = rows[indexPath.row]
        cell.configure(title: row.title, detail: row.detail, isOn: row.isOn(), onChange: row.setter)
        return cell
    }
}

/// 一行：标题 + 一句说明 + 一个开关。
private final class ToggleCell: UITableViewCell {

    static let reuseIdentifier = "ToggleCell"

    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        detailTextLabel?.numberOfLines = 0
        detailTextLabel?.textColor = .secondaryLabel
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        accessoryView = toggle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    func configure(title: String, detail: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        textLabel?.text = title
        detailTextLabel?.text = detail
        toggle.isOn = isOn
        self.onChange = onChange
    }

    @objc private func toggled() {
        onChange?(toggle.isOn)
    }
}
