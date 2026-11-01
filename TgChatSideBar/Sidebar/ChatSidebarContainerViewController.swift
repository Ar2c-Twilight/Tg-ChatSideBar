//
//  ChatSidebarContainerViewController.swift
//  TgChatSideBar
//

import UIKit

/// 整个东西。持有列表、持有当前 chat，并用**一个 `progress` 标量**把两者排布出来。
///
/// 刻意**没有导航栈**。只有两页的时候，「push」和「pop」不过是 `progress` 动到 0
/// 或 1；而丢掉栈正是 `.peek` 得以成立的前提：UIKit 自带的交互式过渡是二元的
/// （`finish()` / `cancel()`），根本没有「停在半路、两边都还能交互」这个概念。
///
/// ## 两个连续量
///
/// 屏幕上的一切由且仅由这两个数派生：
///
/// - `progress` —— 手势完成度 / x 轴偏移，0 = chat 全屏，1 = 列表全屏。
///   拖动时归手指，松手后归 `spring`。
/// - `peekBlend` —— 「现在有多像 peek」，0…1，由一条自己的弹簧驱动。
///
/// 为什么需要第二个：**「是否预告 `.peek`」不是 `progress` 的函数。** 同一个
/// `progress` 下，慢慢拖（动量小）会预告 `.peek`，快甩过去（动量大）会预告
/// `.list`，两者外观不同。而且从「由 progress 驱动」切换到「停在 peek 的固定值」
/// 需要平滑过渡，不能跳变。`peekBlend` 就是承载这两件事的量。
final class ChatSidebarContainerViewController: UIViewController {

    /// 0 = chat 全屏，1 = 列表全屏。屏幕上每一帧的唯一真相来源。
    private(set) var progress: CGFloat = 0 {
        didSet {
            guard progress != oldValue else { return }
            relayout()
        }
    }

    private let listViewController = ChatListViewController()
    private var chatViewController: (ChatViewController)?

    /// 右栏是一个*槽位*，不是某个 view controller。`layout(for:)` 只负责摆这个
    /// 视图、从不往里看——这正是切 chat 的交叉淡入能独立于吸附动画运行的原因，
    /// 淡入期间这里会同时挂着两个 chat 页。
    private let chatContainerView = UIView()
    private let listContainerView = UIView()
    private let dimView = UIView()
    private let readout = DebugReadout()

    /// 调试开关页和容器共享这一个实例：页面改它，这边听 `onChange` 去应用。

    /// 手势希望覆盖层显示吗。真正显不显示还要再 `&&` 上开关——这两件事得分开记，
    /// 否则拖动途中拨开关就会算错。
    private var wantsThresholdOverlay = false

    /// 调试覆盖层：松手会落到 `.peek` 的那段 `progress` 区间，拖动期间盖在所有
    /// 东西上面。让这个窗口变成可以瞄准的东西，而不是靠一个数字脑补出来的。
    private let peekWindowOverlay = UIView()
    private let snapLine = UIView()

    /// 只有一个实例，装在根视图上，所以**任意位置**的横向拖动都能驱动它。它的
    /// 优先级压过一切：所有别的 pan 都被要求等它先失败；而且因为它会取消视图里
    /// 的触摸，它一旦 begin，底下的滚动视图就在手指底下被切断。
    private let sgb = SGBGestureRecognizer(target: nil, action: nil)

    /// 点一下停靠着的 chat 页就把它放回去——而且和纵向拖动不同，它**消费**触摸，
    /// 所以这一下点击不会顺带按到底下的东西。
    private let peekTap = UITapGestureRecognizer(target: nil, action: nil)

    /// 在 `.peek` 下观察停靠的 chat 页，不消费任何东西。
    private let peekSniffer = PeekTouchSniffer(target: nil, action: nil)

    private let spring = SpringScalar()

    /// 「现在有多像 peek」，0…1。0 = 列表还是「背后那一页」，带着视差滞后着；
    /// 1 = 已经就位。**实时跟踪待定落点**，一次手势里可以来回翻多次。
    ///
    /// 它同时驱动三样东西：列表的视差偏移、cell 里头像的 scale、文字的 opacity。
    /// 共用同一个量，所以这三样永远不会对「现在是不是 peek」产生分歧。
    private let peekBlend = SpringScalar()
    private let tracker = MotionTracker()
    /// 进入 peek 预告时的那一下。语义是「这儿可以停」，所以挂在预告成立的瞬间。
    private let peekFeedback = UIImpactFeedbackGenerator(style: .rigid)

    /// 每跨过一格的「咔哒」。用 selection 而不是 impact——这正是系统 picker 换一档
    /// 时用的那一下，语义对得上。（模拟器上没有触觉，真机才感觉得到。）
    private let stepFeedback = UISelectionFeedbackGenerator()

    /// 侧栏上一次停在哪儿。手势的可用性看这个而不是实时的 `progress`，这样正在
    /// 驱动拖动的那个识别器在整段拖动里都保持启用。
    private var restingDetent: SidebarDetent = .chat {
        didSet { updateGestureAvailability() }
    }

    /// 当前这次拖动开始时的 `progress`。拖动按*相对位移*跟踪，而不是按手指的
    /// 绝对位置，所以 `.began` 那一下不会跳——页面边缘保持它被抓住时相对手指的
    /// 那个偏移。（绝对位置那版试过，跳变不值得。）
    private var dragStartProgress: CGFloat = 0

    /// 正在飞的那次交叉淡入：动画器加上它正在退场的那一页。留着是为了第二次
    /// 点行时能把它立刻落地，而不是在上面再叠一层淡入——否则连点会堆出一摞 chat 页。
    /// 上一次切换还没收尾时，被它留在屏上的那一页。
    private var pendingSwitchOutgoing: (ChatViewController)?

    /// 纵向接管已经发生：横向分量从此被忽略，档位锁在 `.peek`。
    private var isVerticalLocked = false

    /// 纵向意图积累了多少：`|translationY| / verticalLockThreshold`，夹在 0…1。
    /// 存下来是因为分裂进度还要乘上 `peekBlend`，而那个是弹簧驱动的、走另一个时钟。
    private var verticalIntentRatio: CGFloat = 0

    /// 高亮框当前要去的那一**整数**行。段落感就在这儿：它只在跨过半行的那一刻变，
    /// 弹簧负责把框送过去。右栏的预览切换也挂在它变化的那一刻，所以框起步和内容
    /// 更换是同一个瞬间。
    private var highlightTargetRow: CGFloat = 0

    /// 这一次切换是往下还是往上，决定两页各自从哪一侧进出。
    private var switchDirectionIsDownwards = true
    /// 作废掉还没收尾的上一次切换（连续换行时会出现）。
    private var pendingSwitchToken: UUID?
    /// 最近一次采样到的纵向速度，提交判据用。
    /// 纵向接管期间逐帧采样手指位置，自己差分出速度。
    ///
    /// `recognizer.velocity(in:)` 在手指**停住**时不会更新——它会一直报上一次算出来的
    /// 值，而「停住」恰恰是我们唯一要检测的事件。`.changed` 更是只在手指**动**的时候
    /// 才触发，所以拿事件驱动这个判据，最关键的那一帧永远不会到。
    /// 最近一帧采样出来的纵向速度，提交判据用。
    private var verticalCommitVelocity: CGFloat = 0
    private var verticalLockLink: CADisplayLink?
    private var verticalLockLastPoint: CGPoint?
    private var verticalLockLastTimestamp: CFTimeInterval = 0

    /// 高亮框上边那条线停在第几行（连续值）。
    private let highlightTopSpring = SpringScalar()

    /// 下边那条。和上边各自独立——**前进方向那条更硬**，于是移动时框被拉长、停下时
    /// 弹回来。果冻感就是这么来的，不是一段额外的动画。
    private let highlightBottomSpring = SpringScalar()

    /// 左右两条边，单位 pt（容器坐标）。目标由分裂进度给，所以收窄成正方形那一下
    /// 也是弹着收的——块会先扁过头再回来。
    private let highlightLeftSpring = SpringScalar()
    private let highlightRightSpring = SpringScalar()

    /// 「立体感」的淡入淡出：外投影、内侧白高光、底部渐变一起来、一起走，同时它本身
    /// 的填充淡出。配得很硬、不过冲——这是一次材质切换，不该晃。
    private let reliefSpring = SpringScalar()

    /// 松手判定上一次运行时的答案。作为滞回状态回喂给它：一旦预告成了 `.peek`，
    /// 要把它劝退所需的动作就比当初劝进来时更大。
    private var isPeekPending = false

    /// `peekBlend` 当前的目标值。只在翻转时改，不是每帧写。
    private var parallaxTarget: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        addChild(listViewController)
        listContainerView.clipsToBounds = true
        listContainerView.addSubview(listViewController.view)
        view.addSubview(listContainerView)
        listViewController.didMove(toParent: self)

        listViewController.onSelect = { [weak self] chat in
            self?.select(chat: chat)
        }

        // chat 盖住列表期间压在列表上的黑色遮罩。TG 的值。
        dimView.backgroundColor = .black
        dimView.isUserInteractionEnabled = false
        view.addSubview(dimView)

        chatContainerView.clipsToBounds = true
        view.addSubview(chatContainerView)

        // 位移窗口。动量的滞回不是屏幕上的区域，画不出来——看读数条。
        peekWindowOverlay.backgroundColor = UIColor.systemRed.withAlphaComponent(0.18)
        peekWindowOverlay.isUserInteractionEnabled = false
        peekWindowOverlay.isHidden = true
        view.addSubview(peekWindowOverlay)

        snapLine.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        snapLine.isUserInteractionEnabled = false
        snapLine.isHidden = true
        view.addSubview(snapLine)

        view.addSubview(readout)

        sgb.addTarget(self, action: #selector(handleSGB(_:)))
        view.addGestureRecognizer(sgb)

        peekTap.addTarget(self, action: #selector(handlePeekTap))
        chatContainerView.addGestureRecognizer(peekTap)

        // 刻意在所有状态下都保持启用。它不消费任何东西，空转不花钱；而且永远不切
        // `isEnabled` 就意味着它不会在正看着一个触摸的途中被取消掉。
        peekSniffer.onVerticalSwipeStarted = { [weak self] in self?.collapseFromPeek() }
        chatContainerView.addGestureRecognizer(peekSniffer)

        spring.onChange = { [weak self] value in
            self?.progress = value
        }
        spring.onSettle = { [weak self] in
            self?.didSettle()
        }

        peekBlend.stiffness = SidebarMetrics.peekBlendStiffness
        peekBlend.dampingRatio = SidebarMetrics.peekBlendDamping
        peekBlend.onChange = { [weak self] _ in
            guard let self else { return }
            self.relayout()
            // 分裂进度是它和纵向意图的乘积，所以它一动就得重算——否则这一帧用的是
            // 上一次触摸事件时算的旧值。和倾斜那边是同一类问题。
            self.updateHighlightSplit()
        }

        for spring in [highlightTopSpring, highlightBottomSpring] {
            spring.dampingRatio = SidebarMetrics.edgeDamping
            spring.onChange = { [weak self] _ in
                guard let self else { return }
                // 纵向一动，「落后多少」就变了，横向的目标得跟着重算。
                self.updateSideTargets()
                self.pushLeadingEdges()
            }
        }
        for spring in [highlightLeftSpring, highlightRightSpring] {
            spring.stiffness = SidebarMetrics.sideStiffness
            spring.dampingRatio = SidebarMetrics.sideDamping
            spring.onChange = { [weak self] _ in self?.pushLeadingEdges() }
        }
        // 初值：没分裂时就是整列宽。
        highlightLeftSpring.track(0)
        highlightRightSpring.track(SidebarMetrics.peekColumnWidth)

        reliefSpring.stiffness = SidebarMetrics.reliefStiffness
        reliefSpring.dampingRatio = SidebarMetrics.reliefDamping
        reliefSpring.onChange = { [weak self] value in
            self?.listViewController.highlightRelief = value
        }

        applyDebugSettings()

        setChat(Chat.samples[0], crossFade: false)
        moveHighlight(toRow: Chat.samples[0].id)
        updateGestureAvailability()
        updateReadout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout(for: progress)

        let insets = view.safeAreaInsets
        let readoutHeight: CGFloat = 40
        readout.frame = CGRect(x: 12,
                               y: view.bounds.height - insets.bottom - readoutHeight - 8,
                               width: view.bounds.width - 24,
                               height: readoutHeight)
    }

    // MARK: - Layout

    /// 屏幕上的每一帧，作为 `progress` 的纯函数算出来。
    ///
    /// 视觉常数取自 TG 的 `NavigationTransitionCoordinator.updateProgress`。
    private func layout(for progress: CGFloat) {
        let bounds = view.bounds
        guard bounds.width > 0 else { return }

        // chat 页和手指 1:1 平移，从不缩放——「跟手」就是这个意思，而且缩放会让
        // 文字重排。
        let chatX = (progress * bounds.width).rounded()
        chatContainerView.frame = CGRect(x: chatX, y: 0, width: bounds.width, height: bounds.height)
        for subview in chatContainerView.subviews {
            subview.frame = chatContainerView.bounds
        }

        // 列表是一张躺在下面的整屏宽页面，而不是一个会变宽的列。它也不裁切到
        // 露出的那条——chat 页不透明、自己会盖住；不裁切的好处是 chat 页的圆角
        // 缺口里露出的是真的列表内容，而不是一块光秃秃的背景。
        listContainerView.frame = bounds

        // `peekBlend` 唯一动的就是这一页滞后多少：它为 0 时偏移跟着 `progress`
        // 走（和 TG 一样），为 1 时偏移归零。
        let laggingX = -(1 - progress) * SidebarMetrics.parallaxRatio * bounds.width
        let parallaxX = lerp(laggingX, 0, peekBlend.value)
        listViewController.view.frame = CGRect(x: parallaxX, y: 0,
                                               width: bounds.width, height: bounds.height)

        dimView.frame = bounds
        dimView.alpha = (1 - progress) * SidebarMetrics.dimAlpha

        let window = SidebarMetrics.peekWindow
        peekWindowOverlay.frame = CGRect(x: window.lowerBound * bounds.width, y: 0,
                                         width: (window.upperBound - window.lowerBound) * bounds.width,
                                         height: bounds.height)
        snapLine.frame = CGRect(x: SidebarDetent.peek.progress(width: bounds.width) * bounds.width - 1, y: 0,
                                width: 2, height: bounds.height)

        // 两个因子都往下传。`progress` 是深度线索——chat 盖得越多，列表坐得越靠后；
        // `peekBlend` 是 peek 覆盖。后者和视差用的是同一个量，所以外观和视差永远
        // 不会对「peek 是不是待定落点」有分歧。
        listViewController.progress = progress
        listViewController.peekBlend = peekBlend.value

        let insets = view.safeAreaInsets
        listViewController.contentInsets = insets
        chatViewController?.contentInsets = insets
    }

    // MARK: - Gesture

    @objc private func handleSGB(_ recognizer: SGBGestureRecognizer) {
        let width = view.bounds.width
        guard width > 0 else { return }

        switch recognizer.state {
        case .began:
            // 半路接管飞行中的弹簧，正是它要手写积分的全部理由：把它手里那个数
            // 拿过来、从那儿接着走，不会弹回到拖动「本该」开始的地方。
            dragStartProgress = spring.isAnimating ? spring.stop().value : progress
            // 从 `.peek` 起手意味着 peek 本来就是待定落点——初始化成 false 会让
            // 第一帧预告 `.chat`，手指还没动呢视差就被拽出去了。
            isPeekPending = restingDetent == .peek
            isVerticalLocked = false
            verticalIntentRatio = 0
            listViewController.highlightSplit = 0
            reliefSpring.retarget(to: 0)
            stepFeedback.prepare()
            tracker.reset()
            peekFeedback.prepare()
            setThresholdOverlayVisible(true)

        case .changed:
            let translation = recognizer.translation(in: view)

            if isVerticalLocked {
                // 不在这里推送：链接每帧都在采样，包括手指不动的那些帧。
                break
                updateReadout()
                return
            }

            spring.track((dragStartProgress + translation.x / width).clamped(to: 0...1))
            let velocity = recognizer.velocity(in: view)
            tracker.update(velocity: velocity)
            predictLanding(velocityX: velocity.x)   // 顺便推动 peekBlend
            verticalIntentRatio = (abs(translation.y) / SidebarMetrics.verticalLockThreshold)
                .clamped(to: 0...1)
            updateHighlightSplit()
            updatePreLockLean(translationY: translation.y)
            checkVerticalLock(translationY: translation.y,
                              velocityY: velocity.y,
                              location: recognizer.location(in: view))
            updateReadout()

        case .ended, .cancelled, .failed:
            setThresholdOverlayVisible(false)
            stopVerticalLockLink()
            // 手指走了，倾斜和分裂都没有依据了。锁定与否都一样。
            listViewController.highlightLean = 0
            verticalIntentRatio = 0
            listViewController.highlightSplit = 0
            reliefSpring.retarget(to: 0)

            if isVerticalLocked {
                // 把容器挪到最终那一行。左边那块的位置是用**绝对行号**算的，所以
                // 这一下完全不会动它；动的只有右边那块，而它在 `.peek` 下被 chat 页
                // 盖着，看不见。整个纵向手势期间右边那块一帧都没动过，正是为此。
                listViewController.highlightRow = highlightTargetRow
                // 横向那一侧早就结束了，不跑落点判定。高亮框也不用吸附——它的目标
                // 一直就是整数行，弹簧自己会走完。
                //
                // 纵向手势一结束就收回全屏，**不管最后停在哪一行**。曾经有个例外：
                // 绕一圈又落回出发那个 chat 时留在 `.peek` 让用户接着挑。已去掉——
                // 「松手就进去」是一条规则，而那个例外让同一个动作有时进去有时不进去，
                // 用户得先回想自己从哪一行出发的才能预测结果。
                settle(to: .chat, velocityX: 0)
                return
            }


            let velocityX = recognizer.velocity(in: view).x
            // 和视差一路展示的是同一个预告，所以列表之前许诺的就是实际发生的。
            let detent = predictLanding(velocityX: velocityX)
            settle(to: detent, velocityX: velocityX)

        default:
            break
        }
    }

    /// 把高亮框放到某一行。`Chat.id` 恰好就是它在 `Chat.samples` 里的下标。
    private func moveHighlight(toRow row: Int) {
        let target = CGFloat(row)
        highlightTargetRow = target
        highlightTopSpring.retarget(to: target)
        highlightTopSpring.track(target)
        highlightBottomSpring.retarget(to: target + 1)
        highlightBottomSpring.track(target + 1)
        listViewController.highlightRow = target
    }

    /// 纵向位移够大、**而且 `.peek` 已经被预告** —— 夺走手势。
    ///
    /// 门槛用的是预告本身（`isPeekPending`）而不只是位移窗口，所以它比「落在窗口
    /// 里」严格：动量也得已经降下来。好处是时机和视觉对齐——预告成立时 `peekBlend`
    /// 已经把侧栏推成「完全在场」的样子（视差归位、文字隐去、头像满大小），**侧栏
    /// 看起来可以挑行了，纵向才真的能挑行**。
    private func checkVerticalLock(translationY: CGFloat, velocityY: CGFloat, location: CGPoint) {
        guard !isVerticalLocked,
              isPeekPending,
              abs(translationY) > SidebarMetrics.verticalLockThreshold
        else { return }

        isVerticalLocked = true
        startVerticalLockLink()
        reliefSpring.retarget(to: 1)

        // 把分裂钉到「满」。手速快的时候锁定可能在过渡还没走完时就发生了：
        // `highlightSplit = verticalIntentRatio × peekBlend`，而 `peekBlend` 是弹簧
        // 驱动的，预告刚成立就立刻纵向甩的话它可能才到 0.3，于是左边那块会半收不收
        // 地冻在那儿一整个手势。
        //
        // 不是硬写成 1，而是把**意图**钉成 1，剩下的交给 `peekBlend`——它在下面
        // `setParallaxSettled(true)` 之后本来就要弹到 1，于是分裂跟着它平滑补完，
        // 不需要额外的动画，也不会在锁定那一帧跳一下。
        verticalIntentRatio = 1

        // 交接。锁定前框的视觉位置里含着一段 lean（只加在左边那块的 frame 上），
        // 而锁定后位置改由两根弹簧表达——直接把 lean 清零，框会瞬间弹回档位认为的
        // 地方，就是那一下跳帧。
        //
        // 所以先把 lean 折算成行、连同手指当下的纵向速度一起灌进两根弹簧：**让弹簧
        // 从「眼睛看到的位置」带着「眼睛看到的速度」接着跑**，而不是从「档位认为的
        // 位置」静止重启。位置和速度都接上了，交接就看不出来。
        let rowHeight = SidebarMetrics.cellHeight
        let leanInRows = listViewController.highlightLean / rowHeight
        let leanVelocityInRows = velocityY * SidebarMetrics.rowLeanFactor / rowHeight
        highlightTopSpring.takeOver(value: highlightTopSpring.value + leanInRows,
                                    velocity: leanVelocityInRows)
        highlightBottomSpring.takeOver(value: highlightBottomSpring.value + leanInRows,
                                       velocity: leanVelocityInRows)
        listViewController.highlightLean = 0

        // 横向就此定案：锁死在 `.peek`，外观也一并锁住（`peekBlend` 到 1），
        // 这样接下来纵向滑的时候侧栏是「完全在场」的样子。
        restingDetent = .peek
        isPeekPending = true
        setParallaxSettled(true)
        spring.animate(to: SidebarDetent.peek.progress(width: view.bounds.width), initialVelocity: 0)

    }

    /// 接管之后，手指的绝对位置经过一层映射变成弹簧的目标。
    ///
    /// ```
    /// rowIndex = round((y - 行高/2) / 行高)          ← 手指压在哪一行
    /// lean     = (y - 该行中心) / 行高 × 0.2         ← 偏离中心多少，单位「行」
    /// target   = rowIndex + lean
    /// ```
    ///
    /// 倾斜被**揉进目标**里，不再是叠在框上的一层独立位移——于是「框该在哪」只有
    /// 一个来源，弹簧的滞后顺带把段落感也带出来了：target 在跨行时阶跃一大截
    /// （约 0.8 行），弹簧追过去就是那一下「咔哒」。
    ///
    /// 上下两条边的目标差一整行，但**哪条更硬取决于往哪边走**：前进那条先到、
    /// 后面那条还在路上，框就被拉长了。
    private func startVerticalLockLink() {
        verticalLockLastPoint = sgb.location(in: view)
        verticalLockLastTimestamp = CACurrentMediaTime()
        stopVerticalLockLink()
        let link = CADisplayLink(target: self, selector: #selector(verticalLockTick))
        link.add(to: .main, forMode: .common)
        verticalLockLink = link
    }

    private func stopVerticalLockLink() {
        verticalLockLink?.invalidate()
        verticalLockLink = nil
        verticalLockLastPoint = nil
    }

    @objc private func verticalLockTick() {
        guard isVerticalLocked else { return }
        let point = sgb.location(in: view)
        let now = CACurrentMediaTime()

        var velocityY: CGFloat = 0
        if let last = verticalLockLastPoint {
            let elapsed = now - verticalLockLastTimestamp
            if elapsed > 0 {
                velocityY = (point.y - last.y) / CGFloat(elapsed)
            }
        }
        verticalLockLastPoint = point
        verticalLockLastTimestamp = now

        trackVertical(at: point, velocityY: velocityY)
    }

    private func trackVertical(at location: CGPoint, velocityY: CGFloat) {
        verticalCommitVelocity = velocityY
        let rowHeight = SidebarMetrics.cellHeight
        let maximum = CGFloat(Chat.samples.count - 1)

        let y = listViewController.contentY(of: location, from: view)
        let rowIndex = (((y - rowHeight / 2) / rowHeight).rounded()).clamped(to: 0...maximum)
        let rowCenter = rowIndex * rowHeight + rowHeight / 2
        let lean = (y - rowCenter) / rowHeight * SidebarMetrics.rowLeanFactor
        let target = rowIndex + lean

        // 往下走时下边是前进边，往上走时上边是前进边。
        let movingDown = target >= highlightTopSpring.value
        highlightTopSpring.stiffness = movingDown ? SidebarMetrics.edgeStiffnessFollowing
                                                  : SidebarMetrics.edgeStiffnessLeading
        highlightBottomSpring.stiffness = movingDown ? SidebarMetrics.edgeStiffnessLeading
                                                     : SidebarMetrics.edgeStiffnessFollowing
        highlightTopSpring.retarget(to: target)
        highlightBottomSpring.retarget(to: target + 1)

        // 右栏只跟整数行换，不跟连续的 target 换。
        guard rowIndex != highlightTargetRow else { return }

        // 而且只在手指**停下来**的时候换，不在扫过的时候换。用速度不用加速度：
        // 匀速扫过的手指加速度为零，会被读成「稳了」——而那正是要滤掉的那些行。
        guard abs(verticalCommitVelocity) < SidebarMetrics.peekDragCommitVelocity else { return }

        // 方向要在更新 `highlightTargetRow` **之前**算。写在后面的话比较的是
        // 「新行和它自己」，恒为真，于是每一次切换都往同一个方向走。
        let downwards = rowIndex > highlightTargetRow
        highlightTargetRow = rowIndex
        previewChat(atRow: Int(rowIndex), downwards: downwards)
    }

    /// 把两根弹簧的当前值合成一个跨度交给列表。
    /// 把四根弹簧的当前值合成左边那块的四条边交给列表。**只碰左边那块**——容器
    /// （从而右边那块）由 `highlightRow` 单独管，拖动期间一动不动。
    private func pushLeadingEdges() {
        listViewController.leadingEdges = LeadingEdges(top: highlightTopSpring.value,
                                                        bottom: highlightBottomSpring.value,
                                                        left: highlightLeftSpring.value,
                                                        right: highlightRightSpring.value)
    }

    /// 高亮框「裂开」的进度 = 纵向意图 × peek 的成色。
    ///
    /// 乘上 `peekBlend` 而不是写一个 `if isPeekPending` 的硬门槛，是因为**分裂是
    /// 接管的预告，它的出现条件必须和接管本身一致**。用乘法还白拿了两样东西：预告
    /// 刚成立时 `peekBlend` 从 0 弹上来、分裂跟着淡入；预告被撤销时它弹回 0、分裂
    /// 跟着收回去。
    ///
    /// 接管之后 `verticalIntentRatio` 被钉死在 1，所以它**不再随手指呼吸**——「正在
    /// 逼近一个不可逆的门槛」这件事，跨过门槛之后就没有可言了。但它仍然跟着
    /// `peekBlend` 走，于是那段还没走完的过渡会被补完（见 `checkVerticalLock`）。
    private func updateHighlightSplit() {
        listViewController.highlightSplit = verticalIntentRatio * peekBlend.value
        updateSideTargets()
    }

    /// 横向两条边的目标 = 分裂收窄（基线）± 纵向落后量换来的挤压。
    ///
    /// 挤压那一项是「变扁」的全部来源：块离纵向目标越远（正在飞）收得越窄，追上了
    /// 就恢复。只靠分裂收窄是不够的——锁定之后分裂恒为 1，那一项是个常数。
    private func updateSideTargets() {
        let column = SidebarMetrics.peekColumnWidth
        let shrink = lerp(0, column - SidebarMetrics.cellHeight,
                          listViewController.highlightSplit)
        let lag = abs(highlightTopSpring.target - highlightTopSpring.value)
        let squash = Swift.min(lag, 1) * SidebarMetrics.sideSquash
        let base = shrink / 2
        highlightLeftSpring.retarget(to: base + squash)
        highlightRightSpring.retarget(to: column - base - squash)
    }

    /// 接管之前，左边那块跟着纵向位移让一点，pt。
    ///
    /// 这一段没有可以揉进去的弹簧目标（框还钉在选中行上），所以偏移只能直接加在
    /// frame 上。接管之后它归零，倾斜改由弹簧目标承担。
    private func updatePreLockLean(translationY: CGFloat) {
        guard !isVerticalLocked else { return }
        listViewController.highlightLean = translationY * SidebarMetrics.rowLeanFactor
    }

    /// 右栏预览第 `index` 行的 chat——不等松手。
    ///
    /// 行号已经由 `trackVertical` 算好夹好了，这里不再取整也不再夹一遍。
    private func previewChat(atRow index: Int, downwards: Bool) {
        let chat = Chat.samples[index]
        guard chat.id != chatViewController?.chat.id else { return }
        switchDirectionIsDownwards = downwards
        setChat(chat, crossFade: true)
        // 跨过一格的「咔哒」。跟着换行走而不是跟着弹簧走，所以它和右栏换内容是
        // 同一个瞬间。（模拟器上没有触觉，真机才感觉得到。）
        stepFeedback.selectionChanged()
    }

    /// 现在松手会落到哪儿——顺便把 `peekBlend` 指向那个结果。
    ///
    /// 实时预告和真正的松手走**同一个函数**，所以列表一路在预告的东西，就是松手
    /// 真正会发生的事，不可能不一致。
    @discardableResult
    private func predictLanding(velocityX: CGFloat) -> SidebarDetent {
        let width = view.bounds.width
        guard width > 0 else { return .chat }
        let landing = SidebarRelease.detent(progress: progress,
                                            velocityX: velocityX,
                                            width: width,
                                            decelerationRate: tracker.decelerationRate,
                                            isPeekPending: isPeekPending)

        // 预告刚刚成立——「这儿可以停」。触觉挂在这个**跃迁**上，而不是单独再写一套
        // 「动量骤降」的检测：那套曾经存在过（峰值速度 ≥ 300 且当前 ≤ 80），判据和
        // 这里不完全一致，于是会出现「视差已经归位了但没震」或者反过来的情况。并进来
        // 之后，用户感觉到的那一下和屏幕上看到的那一下必然同源。
        //
        // 滞回保证了它不会在边界上连着响：要撤销预告得跑出更宽的那个动量阈值。
        let wasPeekPending = isPeekPending
        isPeekPending = landing == .peek
        if isPeekPending, !wasPeekPending {
            peekFeedback.impactOccurred()
        }

        setParallaxSettled(isPeekPending)
        return landing
    }

    private func setParallaxSettled(_ settled: Bool) {
        let target: CGFloat = settled ? 1 : 0
        guard target != parallaxTarget else { return }
        parallaxTarget = target
        // 改向而不是重启，这样来回翻转时会保留已有的速度，而不是每翻一次顿一下。
        peekBlend.retarget(to: target)
    }

    @objc private func handlePeekTap() {
        collapseFromPeek()
    }

    /// 因为停靠的 chat 页上发生了点什么，所以退出 `.peek`。
    ///
    /// 非交互式：纵向拖动那条路径里，手指的位移归 chat 自己（它在滚动），没有东西
    /// 可跟，所以就是一发普通弹簧。横向拖动根本不会走到这里——那是 SGB 的，而且
    /// 从 `.peek` 出发它可以落到三个档位中的任意一个。
    private func collapseFromPeek() {
        guard restingDetent == .peek else { return }
        settle(to: .chat, velocityX: 0)
    }

    private func settle(to detent: SidebarDetent, velocityX: CGFloat) {
        let width = view.bounds.width
        restingDetent = detent
        isPeekPending = detent == .peek
        setParallaxSettled(isPeekPending)
        spring.animate(to: detent.progress(width: width),
                       initialVelocity: width > 0 ? velocityX / width : 0)
        updateReadout()
    }

    private func didSettle() {
        if restingDetent == .list {
            // `.list` 意味着*没有任何 chat 被选中*——这正是为什么没有「把它拉回来」
            // 的手势（没有东西可拉）。放在这里而不是手势提交时清掉，整个拖动过程中
            // 它都还活着，所以半路反悔仍然有东西可回去。
            setChat(nil, crossFade: false)
        }
        updateGestureAvailability()
        updateReadout()
    }

    private func setThresholdOverlayVisible(_ visible: Bool) {
        wantsThresholdOverlay = visible
        applyThresholdOverlayVisibility()
    }

    private func applyThresholdOverlayVisibility() {
        let shown = wantsThresholdOverlay && DebugSettings.showsThresholdOverlay
        peekWindowOverlay.isHidden = !shown
        snapLine.isHidden = !shown
    }

    private func applyDebugSettings() {
        readout.isHidden = !DebugSettings.showsReadout
        applyThresholdOverlayVisibility()
    }

    private func relayout() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    /// 除了 `.list`（那里没有 chat 可返回）之外 SGB 处处有效。向左只在 `.peek`
    /// 下算数，因为 `.chat` 下 progress 已经在最小值，向左滑该留给内容。
    ///
    /// 点击恢复只在 `.peek` 下启用。嗅探器刻意不在这个列表里：它不消费任何东西，
    /// 所以一直开着不花钱，而且永远不会在观察触摸的途中被取消掉。
    private func updateGestureAvailability() {
        sgb.isEnabled = restingDetent != .list
        sgb.permitsLeftward = restingDetent == .peek
        peekTap.isEnabled = restingDetent == .peek
    }

    // MARK: - Chat selection

    /// 「显示这个 chat」的唯一入口，peek 那一列和全屏列表都走它。
    private func select(chat: Chat) {
        // 点已经选中的那行意思是「把它放回去就行」，不重建也不淡入。
        guard chat.id != chatViewController?.chat.id else {
            // 点的是已经在显示的那一行：只把它放回去。
            settle(to: .chat, velocityX: 0)
            return
        }
        // 从 `.peek` 过来是原地换内容，所以做交叉淡入。从 `.list` 过来没有「旧的」
        // 可以淡*出*——`progress` 从 1 跑到 0 本身就会让新页从右边滑进来，这是另一套
        // 视觉语言，而且对一个空槽位来说是对的那套。
        // 点选也有方向：点下面的行，新内容就从下面进来。
        if let current = chatViewController?.chat {
            switchDirectionIsDownwards = chat.id > current.id
        }
        setChat(chat, crossFade: chatViewController != nil)
        moveHighlight(toRow: chat.id)
        settle(to: .chat, velocityX: 0)
    }

    /// 换掉右栏槽位里显示的东西。
    ///
    /// 交叉淡入必须和收回*同时*进行，而且先完成：淡得比收回慢的话，会出现页面
    /// 已经全屏了内容还在变，那比完全不做动画还显眼。
    private func setChat(_ chat: Chat?, crossFade: Bool) {
        // 绝不叠加淡入。第二次点击会把第一次立刻落地。
        finishPendingCrossFade()

        let outgoing = chatViewController

        guard let chat else {
            retire(outgoing)
            chatViewController = nil
            listViewController.highlightRow = nil
            listViewController.leadingEdges = nil
            return
        }

        let controller = makePage(for: chat)
        addChild(controller)
        controller.view.frame = chatContainerView.bounds
        controller.contentInsets = view.safeAreaInsets
        chatContainerView.addSubview(controller.view)
        controller.didMove(toParent: self)
        chatViewController = controller

        guard crossFade, let outgoing else {
            retire(outgoing)
            return
        }

        animateChatSwitch(from: outgoing, to: controller, downwards: switchDirectionIsDownwards)
    }

    /// 两块气泡**并行**平移，像一条胶片一起走；离场的那块同时缩小糊掉，进场的反之。
    ///
    /// 并行而不是先后：先后播放会让两块从不相邻，中间有一刻谁都不在位，读起来既不
    /// 像推也不像溶解。并行时任意一刻新块的前缘都贴着旧块的后缘，位移合起来恒等于
    /// 一个行程——这是「推」这个语言的根基。
    ///
    /// 只动气泡，页头和背景留在原地：换的是这一页的内容，不是换了一页。
    private func animateChatSwitch(from outgoing: ChatViewController, to incoming: ChatViewController, downwards: Bool) {
        let duration = SidebarMetrics.chatSwitchFadeDuration
        let travel = view.bounds.height * SidebarMetrics.chatSwitchTravel
        let offset = downwards ? travel : -travel
        let scale = SidebarMetrics.chatSwitchScale
        let radius = SidebarMetrics.chatSwitchBlurRadius
        let curve = SidebarMetrics.chatSwitchCurve
        let timing = CAMediaTimingFunction(controlPoints: curve.0, curve.1, curve.2, curve.3)

        // 旧页的气泡要搬到新页**之上**。新页是个完整的子控制器，它的背景会把旧页整个
        // 盖住，不搬的话离场动画一帧都看不见。旧页反正要退役，摘掉它的气泡没有副作用。
        let departing = outgoing.switchContentView
        departing.frame = chatContainerView.convert(departing.bounds, from: departing)
        chatContainerView.addSubview(departing)

        animateSwitchLayer(departing.layer, timing: timing, duration: duration,
                           position: (0, -offset), alpha: (1, 0), scale: (1, scale), blur: (0, radius))
        animateSwitchLayer(incoming.switchContentView.layer, timing: timing, duration: duration,
                           position: (offset, 0), alpha: (0, 1), scale: (scale, 1), blur: (radius, 0))

        let token = UUID()
        pendingSwitchToken = token
        pendingSwitchOutgoing = outgoing
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak departing] in
            guard let self, self.pendingSwitchToken == token else { return }
            self.pendingSwitchToken = nil
            self.pendingSwitchOutgoing = nil
            departing?.removeFromSuperview()
            // 留着一个闲置滤镜，这一层会永远待在离屏合成通道里。
            incoming.switchContentView.layer.filters = []
            self.retire(outgoing)
        }
    }

    private func animateSwitchLayer(_ layer: CALayer,
                                    timing: CAMediaTimingFunction,
                                    duration: TimeInterval,
                                    position: (CGFloat, CGFloat),
                                    alpha: (CGFloat, CGFloat),
                                    scale: (CGFloat, CGFloat),
                                    blur: (CGFloat, CGFloat)) {
        if blur.0 > 0 || blur.1 > 0 {
            layer.filters = BlurFilter.make(radius: blur.0).map { [$0] }
        }
        let specs: [(String, Any, Any, Bool)] = [
            ("position.y", position.0, position.1, true),
            ("opacity", alpha.0, alpha.1, false),
            ("transform.scale", scale.0, scale.1, false),
            ("filters.gaussianBlur.inputRadius", blur.0, blur.1, false)
        ]
        for (keyPath, from, to, additive) in specs {
            if keyPath.hasPrefix("filters"), layer.filters?.isEmpty ?? true { continue }
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timing
            animation.isAdditive = additive
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            layer.add(animation, forKey: additive ? nil : keyPath)
        }
    }

    /// 按 chat 的 `kind` 造对应的页。容器只认 `ChatPage`，所以加一种页面不需要动
    /// 这个文件里的其它任何地方。
    /// 右栏只有一种页面，所以这里不再是工厂，只是一句构造。
    ///
    /// 以前它要在「聊天」和「调试开关页」之间分叉，为此模型上有个 `Kind`、还开了
    /// 一个 `ChatPage` 协议。开关改成代码常量之后，那三层一起没了。
    private func makePage(for chat: Chat) -> ChatViewController {
        ChatViewController(chat: chat)
    }

    /// 把上一次还没收尾的切换立刻落地。
    ///
    /// 连续换行时必须有这一句，否则会堆出三四个 chat 页——这是真实的 bug 源，不是
    /// 防御性代码。
    private func finishPendingCrossFade() {
        pendingSwitchToken = nil
        guard let outgoing = pendingSwitchOutgoing else { return }
        pendingSwitchOutgoing = nil
        retire(outgoing)
    }

    private func retire(_ controller: (ChatViewController)?) {
        guard let controller, controller.parent != nil else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    // MARK: - Readout

    private func updateReadout() {
        let width = view.bounds.width
        let momentum = SidebarRelease.momentum(velocityX: tracker.velocity.x,
                                               width: width,
                                               decelerationRate: tracker.decelerationRate)
        let limit = isPeekPending ? SidebarMetrics.momentumExitThreshold
                                  : SidebarMetrics.momentumEnterThreshold
        readout.setItems([
            DebugReadout.Item(title: "progress", value: String(format: "%.2f", progress)),
            DebugReadout.Item(title: "动量", value: String(format: "%.2f", momentum)),
            DebugReadout.Item(title: "阈值", value: String(format: "%.1f", limit)),
            DebugReadout.Item(title: "纵向锁",
                              value: isVerticalLocked ? String(format: "%.2f", highlightTopSpring.value) : "—"),
            DebugReadout.Item(title: "预告", value: isPeekPending ? "peek" : detentName),
        ])
    }

    private var detentName: String {
        switch restingDetent {
        case .chat: return "chat"
        case .peek: return "peek"
        case .list: return "list"
        }
    }
}
