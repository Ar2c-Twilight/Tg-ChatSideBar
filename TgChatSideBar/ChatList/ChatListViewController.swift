//
//  ChatListViewController.swift
//  TgChatSideBar
//

import UIKit

/// 左栏。就是个普通 `UITableView`——有意思的活在 cell 的手工布局里，不在这儿。
final class ChatListViewController: UIViewController {

    var onSelect: ((Chat) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)

    /// 选中高亮。它本身只是个**定位用的容器**（透明），真正画出来的是下面两块。
    /// 插在表的最底层，所以 cell 的内容画在它上面（cell 的背景是透明的）；它是表的
    /// 子视图，于是跟着内容一起滚动。
    private let highlightView = UIView()

    /// 高亮框左边那块：`[0, peekColumnWidth]`，也就是 peek 下会露出来的那一列。
    private let highlightLeading = UIView()

    /// 左边那块的外投影，烘成位图靠九宫格拉伸——运行时零模糊开销。单独一层是因为
    /// 它要画到 bounds 外面去。
    private let leadingShadow = OuterShadowLayer()

    /// 「叠加」高光：一层白，混合模式取 overlay，用来把底下的内容提亮。
    ///
    /// **单独一层，不能把 `compositingFilter` 设在 `highlightLeading.layer` 上**——
    /// 合成滤镜会作用于整棵子树，把投影也算进去，于是投影会变成提亮而不是压暗。
    ///
    /// ⚠️ 混合模式的名字用的是 CAFilter 那套字符串常量，没有正式文档。前两次试滤色
    /// 和减淡，看症状都是**滤镜根本没生效**（屏幕上就是裸的填充色）。所以这一层特意
    /// 用白色 + 三分之一左右的 opacity：**生效**的话是一层提亮；**没生效**的话你会看到
    /// 一块明显的半透明白方块——一眼就能分辨，不用猜。
    private let leadingOverlay = CALayer()

    /// 右边那块：`[peekColumnWidth, 整宽]`，peek 下会被 chat 页盖住的那一段。
    ///
    /// 拆成两块是为了「分裂」那个动画——不裂的时候两块严丝合缝地贴在一起，和一整条
    /// 实心块没有区别。
    private let highlightTrailing = UIView()
    private let titleLabel = UILabel()
    private let chats = Chat.samples

    /// **容器**停在第几行。`nil` 表示没有选中任何 chat（`.list` 全屏时就是这样），
    /// 整个高亮框隐藏。
    ///
    /// 它只在换行、点选、手势结束重置这些离散时刻变——**右边那块的 y 完全由它决定，
    /// 所以它不动，右边那块就一帧都不会动**。纵向拖动期间它是钉住的。
    var highlightRow: CGFloat? {
        didSet {
            guard highlightRow != oldValue else { return }
            layoutHighlight()
            updateSeparators()
        }
    }

    /// **左边那块**的四条边，每条由一根独立的弹簧驱动。
    ///
    /// 纵向是**绝对行号**而不是相对容器的偏移，所以容器挪位置不会让它跟着动：画的
    /// 时候减一下容器行号就行。手势结束时重置容器正是靠这个性质才不留痕迹。
    var leadingEdges: LeadingEdges? {
        didSet {
            guard leadingEdges != oldValue else { return }
            layoutHighlight()
            updateSeparators()
        }
    }

    /// **接管之前**叠在左边那块上的 y 偏移，pt。正值往下。
    ///
    /// 只在这一段存在：那时框还钉在选中行上、没有可以揉进去的弹簧目标，所以偏移
    /// 只能直接加在 frame 上。接管之后它恒为 0，倾斜改由弹簧目标承担。
    var highlightLean: CGFloat = 0 {
        didSet {
            guard highlightLean != oldValue else { return }
            layoutHighlight()
        }
    }

    /// 「立体感」的进度，0…1。0 = 一块平的半透明色块（和接管之前一样），1 = 一块带外
    /// 投影和内侧白高光的「有厚度」卡片，而它本身的填充淡到全透明。
    ///
    /// 三样东西由这一个量统一驱动，所以它们必然同步；而且**每帧重算**而不是各自跑
    /// 动画——块一直在被弹簧形变，CA 动画会和逐帧重设的 frame 打架。
    var highlightRelief: CGFloat = 0 {
        didSet {
            guard highlightRelief != oldValue else { return }
            applyRelief()
        }
    }

    /// 「分裂」的进度，0…1。0 = 两块严丝合缝的直角实心块（和没拆之前一模一样），
    /// 1 = 两块缩小、带圆角、中间裂开一道缝。纯视觉，不参与任何判定。
    var highlightSplit: CGFloat = 0 {
        didSet {
            guard highlightSplit != oldValue else { return }
            layoutHighlight()
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

        highlightView.isUserInteractionEnabled = false
        for part in [highlightLeading, highlightTrailing] {
            part.backgroundColor = .tertiarySystemFill
            part.layer.cornerCurve = .continuous
            highlightView.addSubview(part)
        }

        // 顺序：投影在最底下。它被裁得只剩 bounds 之外，所以其实和上面几层不重叠，
        // 但逻辑上它就该在后面。`highlightLeading` 没有 clipsToBounds，所以这一层
        // 画到 bounds 外面不会被父层裁掉。
        highlightLeading.layer.addSublayer(leadingShadow)

        leadingOverlay.compositingFilter = "overlayBlendMode"
        leadingOverlay.backgroundColor = UIColor.white.cgColor
        leadingOverlay.opacity = 0.5
        leadingOverlay.cornerCurve = .continuous
        // 提亮层必须和 cell **同级**，不能埋进 `highlightLeading` 里。
        //
        // `compositingFilter` 只和**同一个父层里已经画下的内容**混合，不是和整个窗口
        // 的背景混合。埋进 `highlightLeading` 时它的父层缓冲区基本是空的（那块的填充
        // 正在淡出），于是混合退化成直接输出填充色——屏幕上就是一块惨白。
        //
        // 挂到 `tableView.layer` 上，父层缓冲区里就有 cell 了（cell 在它之前画），
        // 混合才有东西可混。代价是它的 frame 落在**内容坐标**里，得自己换算。
        tableView.layer.addSublayer(leadingOverlay)
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

    /// 把 `highlightRelief` 摊到三样东西上。
    private func applyRelief() {
        let t = highlightRelief
        let fill = UIColor.tertiarySystemFill
        CATransaction.withoutAnimations {
            // 它本身的填充淡出——淡的是**填充色的 alpha**，不是 `view.alpha`：后者会把
            // 投影和两层 sublayer 一起带走，那就什么都不剩了。
            highlightLeading.backgroundColor = fill.withAlphaComponent(fill.cgColor.alpha * (1 - t))
            // 影子现在是一张图，所以淡入淡出的是这一层自己的 opacity，而不是
            // `shadowOpacity`——这一层根本没有实时投影了。
            leadingShadow.opacity = Float(SidebarMetrics.reliefShadowOpacity * t)
            leadingOverlay.opacity = Float(SidebarMetrics.reliefOverlayStrength * t)
        }
    }

    /// 把任意坐标空间里的一个点，换算成表的**内容坐标** y。
    ///
    /// 容器算倾斜量要用它：倾斜 = 手指和高亮框之间的距离，而框的位置容器自己知道
    /// （就是弹簧的值），这里只补上「手指在内容坐标里是多少」这一半。
    func contentY(of point: CGPoint, from space: UICoordinateSpace) -> CGFloat {
        tableView.convert(point, from: space).y
    }

    /// 某个点落在第几行。点可以来自任何坐标空间（手势通常给的是容器的）。
    ///
    /// 换算到 `tableView` 自己的坐标系就自动把滚动偏移算进去了——`UIScrollView` 的
    /// `bounds.origin` 就是 `contentOffset`，`convert(_:from:)` 会处理它。所以这里
    /// 拿到的是**内容坐标**，列表滚过之后依然对得上行。
    ///
    /// 首尾越界只做夹住（这本来就是个快捷手势，真要翻页不如直接返回上一级）。
    func rowIndex(at point: CGPoint, from space: UICoordinateSpace) -> Int {
        let inContent = tableView.convert(point, from: space)
        let raw = Int((inContent.y / SidebarMetrics.cellHeight).rounded(.down))
        return Swift.min(Swift.max(raw, 0), chats.count - 1)
    }

    private func layoutHighlight() {
        guard let highlightRow else {
            highlightView.isHidden = true
            return
        }
        highlightView.isHidden = false

        let rowHeight = SidebarMetrics.cellHeight
        let column = SidebarMetrics.peekColumnWidth

        // 容器恒为一行高，钉在 `highlightRow` 上。
        highlightView.frame = CGRect(x: 0, y: highlightRow * rowHeight,
                                     width: tableView.bounds.width, height: rowHeight)

        // 右边那块：容器坐标里的 (column, 0)，一行高。**没有任何东西会改它。**
        highlightTrailing.frame = CGRect(x: column, y: 0,
                                         width: Swift.max(0, highlightView.bounds.width - column),
                                         height: rowHeight)

        // 左边那块：四条边全部来自弹簧。纵向减去容器行号换算成相对位置，所以它可以
        // 飞到容器外面去（容器不裁切）；横向本来就是容器坐标。
        let edges = leadingEdges ?? LeadingEdges(top: highlightRow, bottom: highlightRow + 1,
                                                  left: 0, right: column)
        highlightLeading.frame = CGRect(x: edges.left,
                                        y: (edges.top - highlightRow) * rowHeight + highlightLean,
                                        width: Swift.max(0, edges.right - edges.left),
                                        height: Swift.max(0, (edges.bottom - edges.top) * rowHeight))

        let radius = lerp(0, SidebarMetrics.splitCornerRadius, highlightSplit)
        highlightLeading.layer.cornerRadius = radius
        highlightTrailing.layer.cornerRadius = radius

        // 手写的 sublayer 每次赋值都会隐式动画 0.25 秒，而这些每帧都在重设——必须关掉，
        // 否则它们永远慢半拍、而且每帧打断上一次动画，看起来是糊的。
        CATransaction.withoutAnimations {
            let box = highlightLeading.bounds
            leadingShadow.layout(around: box, cornerRadius: radius,
                                 scale: traitCollection.displayScale)
            // 它不在容器里，所以要把左边那块的 frame 换算到表的内容坐标。
            leadingOverlay.frame = highlightLeading.frame
                .offsetBy(dx: highlightView.frame.minX, dy: highlightView.frame.minY)
            leadingOverlay.cornerRadius = radius
        }
        applyRelief()
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
    /// 用框的实际跨度算，而不是「选中行和它上面那行」——框可以停在行与行之间、
    /// 还会被拉长，那时它同时压着好几条边界。第 `row` 行底下那条线在 `row + 1` 处。
    private func hidesSeparator(below row: Int) -> Bool {
        guard let highlightRow else { return false }
        let boundary = CGFloat(row + 1)
        // 两块各自压着不同的行：右边那块钉在容器上，左边那块跟着弹簧跑。
        let underTrailing = boundary >= highlightRow && boundary <= highlightRow + 1
        let top = leadingEdges?.top ?? highlightRow
        let bottom = leadingEdges?.bottom ?? highlightRow + 1
        let underLeading = boundary >= top && boundary <= bottom
        return underTrailing || underLeading
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
