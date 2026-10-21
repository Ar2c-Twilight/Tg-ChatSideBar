//
//  MotionTracker.swift
//  TgChatSideBar
//

import UIKit

/// 把手势报上来的原始速度采样，变成松手判定需要的东西。
///
/// 刻意不关心视图——喂采样进去，读数出来。
final class MotionTracker {

    /// 手势报的最新速度，单位 pt/s。
    private(set) var velocity: CGPoint = .zero

    /// 用 `UIScrollView` 自己的阻尼率，这样投影出来的惯性和用户在每一个滚动视图
    /// 上甩出来的手感是一致的。
    var decelerationRate: CGFloat = UIScrollView.DecelerationRate.normal.rawValue

    func reset() {
        velocity = .zero
    }

    /// 喂一次采样，通常来自 `UIPanGestureRecognizer.velocity(in:)`。
    func update(velocity newValue: CGPoint) {
        velocity = newValue
    }

    /// 如果现在松手，手指会沿某个轴再滑多远。
    ///
    /// WWDC18「Designing Fluid Interfaces」里的投影公式：
    ///
    ///     distance = (velocity / 1000) * rate / (1 - rate)
    ///
    /// 速度单位 pt/s。在滚动视图的默认阻尼率（0.998）下大约等于
    /// `velocity × 0.499`，也就是 1000 pt/s 的一甩会滑行约 499pt。
    ///
    /// 这是闭式解，所以不需要像弹簧那样逐帧积分——同一类指数衰减的物理，但这个
    /// 问题（「最终会停在哪」）有现成的公式。
    static func project(_ velocity: CGFloat, decelerationRate: CGFloat) -> CGFloat {
        guard decelerationRate > 0, decelerationRate < 1 else { return 0 }
        return (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }
}
