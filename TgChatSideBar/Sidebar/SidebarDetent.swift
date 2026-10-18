//
//  SidebarDetent.swift
//  TgChatSideBar
//

import Foundation
import CoreGraphics

/// 侧栏可以停下来的几个位置。
///
/// `progress` 是整个容器布局所依赖的唯一标量：0 = chat 全屏，1 = 列表全屏。
/// 其余一切——露出的列宽、遮罩透明度、圆角、cell 的外观——都是它的纯函数。
enum SidebarDetent {

    /// chat 全屏，列表完全不可见。
    case chat

    /// 两者同屏：左边一条窄列表，chat 被推到右边。
    case peek

    /// 列表全屏。按定义这里*没有任何 chat 被选中*，所以也没有「把 chat 拉回来」
    /// 这个手势——没有东西可拉。
    case list

    var progress: CGFloat {
        switch self {
        case .chat: return 0
        case .peek: return SidebarMetrics.peekProgress
        case .list: return 1
        }
    }
}

/// 所有可调的数集中在一处：它们都需要在真机上反复试，而没有一个值得去翻找。
enum SidebarMetrics {

    // MARK: 停靠点与判据

    /// `.peek` 吸附到哪儿。刻意做成固定值——这不是 iPadOS 分屏那种可以自由拖
    /// 分隔条的模式；列宽确定下来，cell 的布局才是被设计出来的，而不是勉强活着。
    static let peekProgress: CGFloat = 0.3

    /// **位移**判据：页面实际要到哪个区间，`.peek` 才在候选里。单窗口、无滞回
    /// ——这是个位置，用户看得见它在哪，本来就没有抖动可言。
    static let peekWindow: ClosedRange<CGFloat> = 0.2...0.6

    /// **动量**判据，滞回就住在这儿。
    ///
    /// 动量用 WWDC18 的投影换算成和 `progress` 同样的单位——「这一甩还会再带多远，
    /// 占屏宽的几分之几」。低于阈值说明手指已经稳下来了，停在这里是可信的；高于
    /// 阈值说明它还在往某个地方去。
    ///
    /// 两道阈值是因为这个量才是噪声源：速度采样逐帧跳，而预告在实时驱动视差，
    /// 单阈值会让手指悬在附近时列表来回抖。**「撤销比授予更难」是从源头消掉它**，
    /// 而不是靠调慢动画盖住——后者只是把抖动换成迟钝。
    ///
    /// 在默认阻尼率下，0.4 约合 315 pt/s，0.6 约合 470 pt/s。
    static let momentumEnterThreshold: CGFloat = 0.4
    static let momentumExitThreshold: CGFloat = 0.6

    // MARK: arm 事件

    /// 手指得真的动过，「减速」才有意义——这一条排除那种慢慢蹭、碰巧路过窗口的情况。
    static let armMinimumPeakSpeed: CGFloat = 300

    /// ……并且现在已经几乎停住。
    static let armMaximumCurrentSpeed: CGFloat = 80

    // MARK: 视觉（全部取自 TG 的 NavigationTransitionCoordinator）

    /// chat 盖住列表期间，列表上那层黑色遮罩的最大透明度。
    static let dimAlpha: CGFloat = 0.15

    /// chat 页前缘那条渐变阴影。比 TG 的 16pt / 0.28 更窄更深，而且加了个中间
    /// 色标把大部分衰减压进靠近边缘的那几个点里——这才让边缘读起来是「硬」的，
    /// 而不是一团软雾。
    static let shadowWidth: CGFloat = 12
    static let shadowDarkness: CGFloat = 0.45

    static let shadowAlpha: CGFloat = 0.9

    // MARK: 纵向接管

    /// SGB 进行中、且 `progress` 落在 `peekWindow` 里时，纵向位移超过这个值就
    /// **夺走整个手势**：横向分量从此不再处理，档位锁死在 `.peek`，手势余下的部分
    /// 改为驱动高亮框在侧栏里上下滑。
    ///
    /// **正好是半个行高**，而这不是巧合：高亮框落在哪一行是对连续行号四舍五入得到
    /// 的，所以「移到下一行」需要的位移也正好是半个行高。两者相等意味着**锁定和
    /// 第一次换行是同一个瞬间发生的**——手势不会先僵住、再等你多滑一截才有反应。
    ///
    /// 这也要求纵向行程从**手势起点**算，而不是从锁定那一刻重新起算；否则触发锁定
    /// 用掉的那半行就被丢掉了。
    static var verticalLockThreshold: CGFloat { cellHeight / 2 }

    /// 高亮框一格一格跳过去的那条弹簧。比主弹簧更硬、回弹更明显一点——这一下要
    /// 读起来像「咔哒」一声落位，而不是平滑地滑过去。
    static let highlightStiffness: CGFloat = 420
    static let highlightDamping: CGFloat = 0.80

    // MARK: 视差

    /// 列表还是「背后那一页」时滞后多少，按屏宽的比例。TG 的值
    /// （`NavigationTransitionCoordinator.swift:161`）。
    static let parallaxRatio: CGFloat = 0.3

    /// 驱动 `peekBlend` 的那条弹簧。接近临界阻尼：它最终换算成的是*位移*，
    /// 位移过冲看起来是「抖」而不是「弹」。
    static let peekBlendStiffness: CGFloat = 190
    static let peekBlendDamping: CGFloat = 0.95

    // MARK: 聊天列表的 cell

    static let cellHeight: CGFloat = 76
    static let avatarSize: CGFloat = 56
    static let cellLeftInset: CGFloat = 16
    static let cellTextGap: CGFloat = 12

    // MARK: 列表往后退

    /// chat 页盖上来时列表往后退多少：头像缩到这个比例，文字淡到
    /// `recededTextOpacity`。这是个深度线索——列表是在往后退，不只是被挡住。
    static let recededAvatarScale: CGFloat = 0.75
    static let recededTextOpacity: CGFloat = 0.5

    /// peek 状态把上面两个值覆盖成什么。头像回到满大小——peek 那一列本来就是
    /// 一条头像栏，头像就是它的内容；文字则拉到**零**：在这个列宽下文字会被
    /// chat 页从词中间切断，干净的缺席比毛糙的切口好看。
    static let peekAvatarScale: CGFloat = 1
    static let peekTextOpacity: CGFloat = 0

    // MARK: 切换 chat

    /// 必须明显短于收回的弹簧，这样页面贴边之前新 chat 就已经就位了。
    static let chatCrossFadeDuration: TimeInterval = 0.2
}

/// 松手判定。做成一组只吃普通数字的自由函数，这样不跑任何 UI 也能推演和断言。
enum SidebarRelease {

    /// 在 `progress` 处以 `velocityX` 松手，会落到哪一档。
    ///
    /// 用 WWDC18 的投影而不是裸的位移阈值：要问的是「这根手指奔着哪儿去」，于是
    /// 在中间慢慢松手自然就落在它本来所在的位置——这正是「停在此处、不要把过渡
    /// 走完」那个行为。
    ///
    /// 吃一个 `isPeekPending`（上一次它自己的答案），好让动量滞回有东西可依附。
    /// 它仍然是纯函数：状态存在调用方，所以照样可以脱离 UI 断言。
    static func detent(progress: CGFloat,
                       velocityX: CGFloat,
                       width: CGFloat,
                       decelerationRate: CGFloat,
                       isPeekPending: Bool) -> SidebarDetent {
        guard width > 0 else { return .chat }

        let momentum = MotionTracker.project(velocityX, decelerationRate: decelerationRate) / width

        // 两条独立判据。位置就是个普通窗口；滞回只给动量，因为它才是噪声大的那个。
        let momentumLimit = isPeekPending ? SidebarMetrics.momentumExitThreshold
                                          : SidebarMetrics.momentumEnterThreshold
        if SidebarMetrics.peekWindow.contains(progress), abs(momentum) < momentumLimit {
            return .peek
        }

        // 不是 peek，那就由这一甩决定方向——没什么可读的甩动时，退化成按位置判。
        return progress + momentum < SidebarMetrics.peekProgress ? .chat : .list
    }

    /// 判定眼中的动量：投影出的滑行距离占屏宽的比例。暴露出来是给调试读数用的，
    /// 这样调阈值时看到的就是被比较的那个数本身。
    static func momentum(velocityX: CGFloat, width: CGFloat, decelerationRate: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return MotionTracker.project(velocityX, decelerationRate: decelerationRate) / width
    }

    /// arm 事件该不该触发：在窗口内、刚才很快、现在几乎停住。只触发一次由调用方负责。
    static func shouldArm(progress: CGFloat,
                          peakSpeed: CGFloat,
                          currentSpeed: CGFloat) -> Bool {
        SidebarMetrics.peekWindow.contains(progress)
            && peakSpeed >= SidebarMetrics.armMinimumPeakSpeed
            && currentSpeed <= SidebarMetrics.armMaximumCurrentSpeed
    }
}
