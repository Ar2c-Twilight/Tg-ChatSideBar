//
//  PeekTouchSniffer.swift
//  TgChatSideBar
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 观察停靠着的 chat 页上的**纵向**拖动，但从不占用它。
///
/// 在 `.peek` 下，滚动 chat 同时意味着两件事：*把这一页放回去* **以及** 滚动会话。
/// 不是先后，也不是二选一。两件事并行。
///
/// 只管纵向：横向属于 SGB，而 SGB 在 `.peek` 下可以落回 `.peek`、落到 `.chat`
/// 或者 `.list`。横向也强行退出的话就会和 SGB 抢同一次触摸——那正是「手指往右、
/// 页面往左」那个毛病的来源，这个版本就是来替掉它的。
///
/// 点击*不*在这里处理。点击是一个独立的、普通的、**会消费触摸**的 tap 识别器，
/// 所以点一下停靠页只会把它放回去，不会顺带按到底下的东西。
///
/// 诀窍在于这个识别器**永远不离开 `.possible`**。没有 begin 过的识别器不挡任何人：
/// 它不受失败依赖约束、不会被问要不要同时识别，加上 `cancelsTouchesInView = false`，
/// 触摸到达视图的方式和它根本没装上去时一模一样。所以不存在「仲裁输掉」这回事
/// ——底下的一切照常工作，它只是在旁边汇报自己看见了什么。
///
/// （TG 没有对应物，它的导航手势全都消费触摸。UIKit 里最接近的概念是 iOS 13 的
/// 上下文菜单：一次连续的长按既唤出菜单又从菜单里选——不过那是一个手势的两个
/// 阶段，而这里是一次触摸的两个效果。）
final class PeekTouchSniffer: UIGestureRecognizer {

    /// 纵向拖动开始了。每个触摸序列只触发一次，在移动方向明确为纵向时立刻触发。
    var onVerticalSwipeStarted: (() -> Void)?

    /// 超过这个位移就算拖动而不是按压。
    private let swipeSlop: CGFloat = 4

    private var startLocation: CGPoint = .zero
    private var hasReported = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // 三个都重要：触摸必须原封不动、不被延迟地到达视图，否则底下那一页就会
        // 只在 `.peek` 下手感发黏，别的地方都正常，极难排查。
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func reset() {
        super.reset()
        hasReported = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        startLocation = touch.location(in: view)
        hasReported = false
        // 不调 `super`，也不改 state：保持 `.possible` 正是全部要点。
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !hasReported, let touch = touches.first, let view else { return }
        let location = touch.location(in: view)
        let dx = abs(location.x - startLocation.x)
        let dy = abs(location.y - startLocation.y)
        // 纵向而且占优。主要往横里走的拖动是 SGB 的，在这里上报会让页面既跟着
        // 手指又在逃离手指。
        guard dy > swipeSlop, dy > dx else { return }
        hasReported = true
        onVerticalSwipeStarted?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed   // 唯一一次改 state，纯粹是为了拿到 reset()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }
}
