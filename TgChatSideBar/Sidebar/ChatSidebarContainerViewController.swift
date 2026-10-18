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
    private var chatViewController: ChatViewController?

    /// 右栏是一个*槽位*，不是某个 view controller。`layout(for:)` 只负责摆这个
    /// 视图、从不往里看——这正是切 chat 的交叉淡入能独立于吸附动画运行的原因，
    /// 淡入期间这里会同时挂着两个 chat 页。
    private let chatContainerView = UIView()
    private let listContainerView = UIView()
    private let dimView = UIView()
    private let shadowView = UIImageView()
    private let readout = DebugReadout()

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
    private let armFeedback = UIImpactFeedbackGenerator(style: .rigid)

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
    private var pendingCrossFade: (animator: UIViewPropertyAnimator, outgoing: ChatViewController)?

    /// 一次拖动只 arm 一次：触觉只响一下。
    private var hasArmedThisDrag = false

    /// 纵向接管已经发生：横向分量从此被忽略，档位锁在 `.peek`。
    private var isVerticalLocked = false

    /// 接管发生那一刻高亮框**停靠**在第几行（整数）。纵向行程**从手势起点**算、
    /// 不从锁定点重新起算，这样触发锁定用掉的那半行不会被丢掉——于是锁定和第一次
    /// 换行同时发生。
    private var highlightRowAtLock: CGFloat = 0

    /// 高亮框当前要去的那一**整数**行。段落感就在这儿：它只在跨过半行的那一刻变，
    /// 弹簧负责把框送过去。右栏的预览切换也挂在它变化的那一刻，所以框起步和内容
    /// 更换是同一个瞬间。
    private var highlightTargetRow: CGFloat = 0

    /// 手势开始时右栏是哪个 chat。纵向手势结束后要靠它判断「到底换没换」——换了就
    /// 收回全屏，绕一圈又回到原处就留在 `.peek`。
    private var chatIDAtDragStart: Chat.ID?

    /// 高亮框停在第几行（连续值）。拖动时按整数档跳，松手后弹到整数行。
    private let highlightSpring: SpringScalar = SpringScalar()

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

        shadowView.image = ChatSidebarContainerViewController.makeShadowImage()
        shadowView.isUserInteractionEnabled = false
        view.addSubview(shadowView)

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
            self?.relayout()
        }

        highlightSpring.stiffness = SidebarMetrics.highlightStiffness
        highlightSpring.dampingRatio = SidebarMetrics.highlightDamping
        highlightSpring.onChange = { [weak self] value in
            self?.listViewController.highlightRow = value
        }

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

        shadowView.frame = CGRect(x: chatX - SidebarMetrics.shadowWidth, y: 0,
                                  width: SidebarMetrics.shadowWidth, height: bounds.height)
        shadowView.alpha = (1 - progress) * SidebarMetrics.shadowAlpha

        let window = SidebarMetrics.peekWindow
        peekWindowOverlay.frame = CGRect(x: window.lowerBound * bounds.width, y: 0,
                                         width: (window.upperBound - window.lowerBound) * bounds.width,
                                         height: bounds.height)
        snapLine.frame = CGRect(x: SidebarDetent.peek.progress * bounds.width - 1, y: 0,
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
            hasArmedThisDrag = false
            isVerticalLocked = false
            chatIDAtDragStart = chatViewController?.chat.id
            stepFeedback.prepare()
            tracker.reset()
            armFeedback.prepare()
            setThresholdOverlayVisible(true)

        case .changed:
            let translation = recognizer.translation(in: view)

            if isVerticalLocked {
                trackVertical(translationY: translation.y)
                updateReadout()
                return
            }

            spring.track((dragStartProgress + translation.x / width).clamped(to: 0...1))
            let velocity = recognizer.velocity(in: view)
            tracker.update(velocity: velocity)
            checkArm()
            predictLanding(velocityX: velocity.x)   // 顺便推动 peekBlend
            checkVerticalLock(translationY: translation.y)
            updateReadout()

        case .ended, .cancelled, .failed:
            setThresholdOverlayVisible(false)

            if isVerticalLocked {
                // 横向那一侧早就结束了，不跑落点判定。高亮框也不用吸附——它的目标
                // 一直就是整数行，弹簧自己会走完。
                //
                // 纵向手势是用来「换一个 chat」的，所以换成了就收回全屏，任务完成。
                // 例外是绕了一圈又落回出发时那个 chat：那等于什么都没选，留在
                // `.peek` 让用户接着挑。
                if chatViewController?.chat.id != chatIDAtDragStart {
                    settle(to: .chat, velocityX: 0)
                }
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
        highlightSpring.track(target)
    }

    /// 纵向位移够大、而且页面正停在 peek 那段窗口里 —— 夺走手势。
    ///
    /// 窗口判据和 peek 预告用的是同一条（`peekWindow.contains(progress)`），所以
    /// 「看起来快要停在 peek 了」和「可以切去纵向」是同一个时机，用户不需要分别
    /// 建立两套直觉。
    private func checkVerticalLock(translationY: CGFloat) {
        guard !isVerticalLocked,
              SidebarMetrics.peekWindow.contains(progress),
              abs(translationY) > SidebarMetrics.verticalLockThreshold
        else { return }

        isVerticalLocked = true
        highlightRowAtLock = highlightTargetRow

        // 横向就此定案：锁死在 `.peek`，外观也一并锁住（`peekBlend` 到 1），
        // 这样接下来纵向滑的时候侧栏是「完全在场」的样子。
        restingDetent = .peek
        isPeekPending = true
        setParallaxSettled(true)
        spring.animate(to: SidebarDetent.peek.progress, initialVelocity: 0)

    }

    /// 接管之后，手势的纵向行程驱动高亮框——**一格一格地**，不是连续滑。
    ///
    /// 框不跟手，跟的是四舍五入之后的那个整数行：每跨过半个行高，目标就跳一格，
    /// 弹簧把框送过去。这就是段落感——判定本来就是按行发生的（右栏每行换一次
    /// 内容），这里只是把它在视觉上也表现出来。
    ///
    /// 对照一下 iOS 26 tabbar 上那个 lens：它是连续滑的，因为它滑动的过程中并不
    /// 真的切换 tab。我们这里相反，滑动途中右栏就在跳变预览，所以框也该跳。
    private func trackVertical(translationY: CGFloat) {
        let rows = translationY / SidebarMetrics.cellHeight
        let maximum = CGFloat(Chat.samples.count - 1)
        // 触到首尾两端的情况暂不处理（这本来就是个快捷手势，真要翻页不如直接返回
        // 上一级），所以这里只是夹住。
        let target = (highlightRowAtLock + rows).rounded().clamped(to: 0...maximum)

        guard target != highlightTargetRow else { return }
        highlightTargetRow = target
        // `retarget` 而不是 `animate`：快速连划好几格时要保留弹簧已有的速度，
        // 否则每跨一格都顿一下。
        highlightSpring.retarget(to: target)
        previewChat(atRow: target)
    }

    /// 高亮框滑到哪一行，右栏就预览哪一行——不等松手。
    ///
    /// 用 `rounded()`：框占一整行的高度，所以「它主要压在哪一行上」就是四舍五入。
    /// 于是每滑过一个行高，chat 就换一次。
    ///
    /// 段落感（把这个判定在视觉上也表现出来，让框一格一格地跳）暂时不做——框现在
    /// 是连续滑的，只有右栏在跳。
    private func previewChat(atRow row: CGFloat) {
        let maximum = CGFloat(Chat.samples.count - 1)
        let index = Int(row.rounded().clamped(to: 0...maximum))
        let chat = Chat.samples[index]
        guard chat.id != chatViewController?.chat.id else { return }
        setChat(chat, crossFade: true)
        // 跨过一格的「咔哒」。跟着换行走而不是跟着弹簧走，所以它和右栏换内容是
        // 同一个瞬间。（模拟器上没有触觉，真机才感觉得到。）
        stepFeedback.selectionChanged()
    }

    /// 「动量突然变小」的显式检测。
    ///
    /// 它不能被松手时的投影取代：投影只回答手指抬起那一刻*奔着哪儿去*，而这个必须
    /// 在**手指还按着的时候**触发——它的全部职责就是在用户下决心之前告诉他「这儿
    /// 可以停」。触发只是提示性的：之后松手判定照常跑，用户仍然可以继续甩到 `.list`。
    private func checkArm() {
        guard !hasArmedThisDrag else { return }
        guard SidebarRelease.shouldArm(progress: progress,
                                       peakSpeed: tracker.peakSpeed,
                                       currentSpeed: abs(tracker.velocity.x)) else { return }
        hasArmedThisDrag = true
        armFeedback.impactOccurred()
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
        isPeekPending = landing == .peek
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
        spring.animate(to: detent.progress,
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
        peekWindowOverlay.isHidden = !visible
        snapLine.isHidden = !visible
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
            return
        }

        let controller = ChatViewController(chat: chat)
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

        // 只有新进来的那页做动画。两个都淡会让它们短暂地互相透出，在不透明背景上
        // 读起来是一道灰闪，而不是一次过渡。
        controller.view.alpha = 0
        let animator = UIViewPropertyAnimator(duration: SidebarMetrics.chatCrossFadeDuration,
                                              curve: .easeOut) {
            controller.view.alpha = 1
        }
        animator.addCompletion { [weak self] _ in
            guard let self else { return }
            self.retire(outgoing)
            self.pendingCrossFade = nil
        }
        pendingCrossFade = (animator, outgoing)
        animator.startAnimation()
    }

    private func finishPendingCrossFade() {
        guard let pending = pendingCrossFade else { return }
        pendingCrossFade = nil
        pending.animator.stopAnimation(false)
        pending.animator.finishAnimation(at: .end)   // 会跑 completion
        retire(pending.outgoing)
    }

    private func retire(_ controller: ChatViewController?) {
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
            DebugReadout.Item(title: "峰值", value: String(format: "%.0f", tracker.peakSpeed)),
            DebugReadout.Item(title: "armed", value: hasArmedThisDrag ? "●" : "—"),
            DebugReadout.Item(title: "纵向锁",
                              value: isVerticalLocked ? String(format: "%.2f", highlightSpring.value) : "—"),
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

    // MARK: - Shadow

    /// chat 页前缘那条横向渐变，画一次然后纵向拉伸。构造和 TG 一样
    /// （`NavigationTransitionCoordinator` 12-21 行），但重心压向边缘：中间那个
    /// 色标把大部分暗度留在最后几个点里，这才让边缘读起来是硬的而不是一团软雾。
    private static func makeShadowImage() -> UIImage {
        let width = SidebarMetrics.shadowWidth
        let darkness = SidebarMetrics.shadowDarkness
        let size = CGSize(width: width, height: 1)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.black.withAlphaComponent(0).cgColor,
                          UIColor.black.withAlphaComponent(darkness * 0.18).cgColor,
                          UIColor.black.withAlphaComponent(darkness).cgColor]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray,
                                            locations: [0, 0.6, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient,
                                                 start: .zero,
                                                 end: CGPoint(x: width, y: 0),
                                                 options: [])
        }.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
    }
}
