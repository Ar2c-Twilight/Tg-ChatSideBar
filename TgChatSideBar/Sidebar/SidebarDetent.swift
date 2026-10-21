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

    /// 需要屏宽是因为 `.peek` 的停靠点是由**列宽**定义的（见
    /// `SidebarMetrics.peekColumnWidth`），而 `progress` 是归一化的比例，两者之间
    /// 要除一下屏宽。
    func progress(width: CGFloat) -> CGFloat {
        switch self {
        case .chat: return 0
        case .peek: return SidebarMetrics.peekProgress(width: width)
        case .list: return 1
        }
    }
}

/// 所有可调的数集中在一处：它们都需要在真机上反复试，而没有一个值得去翻找。
enum SidebarMetrics {

    // MARK: 停靠点与判据

    /// `.peek` 停靠时侧栏的列宽，pt。
    ///
    /// 定成**头像加左右对称的内边距**，于是 peek 下头像正好居中在列里。试过定成和行高
    /// 相等（cell 正好是正方形，76pt），但那样头像贴着列的右边缘、左 16 右 0，实际观感
    /// 不如留出对称留白。
    ///
    /// 由尺寸倒推而不是直接定一个 progress 比例：比例会随屏宽漂，而「头像两边留白相等」
    /// 是一条和设备无关的几何约束。
    static var peekColumnWidth: CGFloat { cellLeftInset * 2 + avatarSize }

    /// 把列宽换算成 `progress`。刻意由列宽倒推而不是反过来——这不是 iPadOS 分屏那种
    /// 可以自由拖分隔条的模式，列宽确定下来，cell 的布局才是被设计出来的。
    static func peekProgress(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return (peekColumnWidth / width).clamped(to: 0...1)
    }

    /// **位移**判据：页面实际要到哪个区间，`.peek` 才在候选里。单窗口、无滞回
    /// ——这是个位置，用户看得见它在哪，本来就没有抖动可言。
    ///
    /// 下界必须**低于** `peekProgress(width:)`，否则吸附点落在窗口外面：松手判定要求
    /// 「至少到 0.2」，却又把它往回吸到窗口之外，于是永远没法在吸附点上松手并被判为
    /// peek，进入预告时的触觉也不会在吸附点附近响。
    ///
    /// 92pt 的列宽在所有 iPhone 宽度上换算出来都 ≥ 0.209，所以 0.2 这个固定下界是
    /// 安全的——这也是列宽从 76 放宽到 92 顺带解决掉的一个问题：列宽是绝对值而窗口
    /// 是归一化比例，列越窄、宽屏上的余量越薄，76pt 时 Plus 和 Pro Max 上就会翻负。
    static let peekWindow: ClosedRange<CGFloat> = 0.2...0.8

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

    /// SGB 进行中、**且 `.peek` 已经被预告**时，纵向位移超过这个值就**夺走整个
    /// 手势**：横向分量从此不再处理，档位锁死在 `.peek`，手势余下的部分改为驱动
    /// 高亮框在侧栏里上下滑。
    ///
    /// 取半个行高，纯粹是「这个量级的纵向移动才算有纵向意图」的经验值——纵向接管
    /// 之后高亮框跟的是手指的**绝对位置**，和这里走了多少已经没有换算关系了。
    ///
    /// （早先这个值和行高的一半严格挂钩：那时框跟的是累积位移，半行正好等于「移到
    /// 下一行」所需的量，于是锁定和第一次换行同时发生。改成绝对位置之后这层关系
    /// 自然消失了——锁定的同时框直接去手指底下那一行，本来就是立刻就有反应。）
    static var verticalLockThreshold: CGFloat { cellHeight / 2 }

    /// 手指偏离行中心时，高亮框跟着偏多少的比例。
    ///
    /// 接管之后它被**揉进弹簧的目标**里（`target = rowIndex + lean`），不再是叠在
    /// 上面的一层独立位移——于是「框在哪」只有一个来源，动画统一了。
    ///
    /// 接管之前没有弹簧目标可揉（框还钉在选中行上），那时它作为一个直接的 y 偏移
    /// 加在左边那块上。
    static let rowLeanFactor: CGFloat = 0.1

    // MARK: 果冻

    /// 高亮框的上下两条边各有一根弹簧。**前进方向那条更硬、跟在后面那条更软**，
    /// 于是移动时框会被拉长、停下时弹回来——果冻感就是这么来的。
    ///
    /// 两个数的比值决定拉长多少；绝对值决定追得多紧（越小越滞后）。
    static let edgeStiffnessLeading: CGFloat = 420
    static let edgeStiffnessFollowing: CGFloat = 190

    /// 横向那两条边的弹簧。左右不做软硬之分：横向的目标是对称往里收的，没有
    /// 「前进方向」可言。
    static let sideStiffness: CGFloat = 300
    static let sideDamping: CGFloat = 0.55

    /// 块落后目标整整一行时，左右各往里收多少 pt。
    ///
    /// 这是「变扁」的全部来源。横向目标**不能只由分裂进度给**——锁定之后分裂恒为 1、
    /// 那一项是个常数，横向弹簧就一动不动（这正是之前效果不明显的原因）。改成跟
    /// **纵向的落后量**走：块离目标越远（正在飞）就越扁，追上了就恢复。也就是动画里
    /// 的 squash and stretch——纵向被拉长的同时横向收窄，像在守恒。
    static let sideSquash: CGFloat = 9

    /// 上下两条边共用的阻尼比。越小回弹越明显：0.82 几乎不过冲（约 1%），0.55 过冲约
    /// 13%——换算到一行 76pt 就是落位时越过约 10pt 再荡回来。果冻要的就是这个。
    static let edgeDamping: CGFloat = 0.70

    // MARK: 高亮框的「分裂」

    /// 纵向接管逼近时，高亮框会从一条通栏的实心块，裂成两块圆角卡片：
    /// `[0, peekColumnWidth]` 和 `[peekColumnWidth, 整宽]`——正好是 peek 下露出来
    /// 的那一列、和会被 chat 页盖住的那一段的分界。
    ///
    /// 进度跟着 `translationY / verticalLockThreshold` 走，接管成立的那一刻冻结，
    /// 整个手势周期内不再变。所以它读起来是「侧栏那一块正在从列表里挣脱出来」，
    /// 而不是一个会来回呼吸的装饰。
    ///
    /// 裂开到位时两块的圆角。只在**接管之前**随纵向位移长出来，接管那一刻冻结。
    static let splitCornerRadius: CGFloat = 20

    // MARK: 立体感（纵向接管后左边那块的材质）

    /// 接管成立时这些效果一起淡入、手势结束一起淡出，用一个 0…1 的量统一驱动。
    /// 弹簧配得很硬、几乎不过冲——这是一次材质切换，不该晃。
    static let reliefStiffness: CGFloat = 900
    static let reliefDamping: CGFloat = 1.0

    /// 外投影。
    static let reliefShadowOpacity: CGFloat = 0.28
    static let reliefShadowRadius: CGFloat = 10
    static let reliefShadowOffsetY: CGFloat = 4

    /// 内阴影：顺着描边向内渗的一圈白色高光。
    static let reliefGlowRadius: CGFloat = 4
    static let reliefGlowOpacity: CGFloat = 0.9


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
    static let avatarSize: CGFloat = 60
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
    static let chatCrossFadeDuration: TimeInterval = 0.1
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
        return progress + momentum < SidebarMetrics.peekProgress(width: width) ? .chat : .list
    }

    /// 判定眼中的动量：投影出的滑行距离占屏宽的比例。暴露出来是给调试读数用的，
    /// 这样调阈值时看到的就是被比较的那个数本身。
    static func momentum(velocityX: CGFloat, width: CGFloat, decelerationRate: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return MotionTracker.project(velocityX, decelerationRate: decelerationRate) / width
    }

}
