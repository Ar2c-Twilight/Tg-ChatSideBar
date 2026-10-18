//
//  SGBGestureRecognizer.swift
//  TgChatSideBar
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

/// SGB = Slide to Go Back（滑动返回）。驱动 `progress` 的那个 pan。
///
/// 它认领**屏幕任意位置的任意横向拖动**，不限于从边缘带起手——这其实也是 TG 的
/// 默认行为（它的导航手势是 `.right`，即 `[.rightEdge, .rightCenter]`；只认边缘
/// 那个限制是它*选择性*地加在横向滚动内容之上的）。这个 demo 里没有任何横向滚动
/// 的东西，不需要让位给谁。
///
/// 结构照着 TG 的 `InteractiveTransitionGestureRecognizer`：它在
/// `touchesBegan` / `touchesMoved` 里**自己把 `state` 设成 `.failed`** 来判断这次
/// 触摸是不是自己的，而不是去问 delegate。验证通过之前不调
/// `super.touchesMoved`，所以它还在拿主意的整段时间里 UIKit 都看到 `.possible`
/// ——这也意味着 `.began` 时 `translation(in:)` 从零开始，内容不会在手指底下跳。
final class SGBGestureRecognizer: UIPanGestureRecognizer {

    /// 向左拖能不能认领这个手势。在 `.chat` 下是 false——那时 `progress` 已经在
    /// 最小值，向左滑没事可做，触摸该留给内容。
    var permitsLeftward = false

    private var firstLocation: CGPoint = .zero
    private var isValidated = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        // 关键就是要比内容更早反应；让 UIKit 缓冲最初几次触摸会白白损失头几个点的行程。
        delaysTouchesBegan = false
        cancelsTouchesInView = true
    }

    override func reset() {
        super.reset()
        isValidated = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view {
            firstLocation = touch.location(in: view)
        }
        isValidated = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else {
            super.touchesMoved(touches, with: event)
            return
        }

        if !isValidated {
            let location = touch.location(in: view)
            let dx = location.x - firstLocation.x
            let dy = location.y - firstLocation.y
            let absX = abs(dx)
            let absY = abs(dy)

            if !permitsLeftward && dx < 0 && absX > absY {
                state = .failed            // 方向不对
                return
            }

            // TG 的三条规则，顺序一样：2pt 处用 2:1 的比例做早期判决，否则等
            // 触摸在任意方向上走满 10pt 再硬仲裁。
            let total = (absX * absX + absY * absY).squareRoot()
            if total > 10 {
                if absX >= absY {
                    isValidated = true
                } else {
                    state = .failed
                    return
                }
            } else if absY > 2 && absY > absX * 2 {
                state = .failed
                return
            } else if absX > 2 && absY * 2 < absX {
                isValidated = true
            }

            guard isValidated else { return }   // 还没拿定主意，先吞掉
        }

        super.touchesMoved(touches, with: event)
        if state == .possible {
            state = .began
        }
    }
}

extension SGBGestureRecognizer: UIGestureRecognizerDelegate {

    /// 绝不和任何人同时识别——全部仲裁都靠下面那条失败依赖。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }

    /// 所有别的 pan——包括每个滚动视图自带的那个——都要等这一个先失败。这是 TG
    /// 的反转写法（`NavigationContainer` 198-210 行）。之所以可以接受，是因为上面
    /// 那个闸门在纵向移动约 2pt 内就会自判失败，滚动几乎察觉不到这点延迟。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer
    }
}
