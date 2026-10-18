//
//  MotionTracker.swift
//  TgChatSideBar
//

import UIKit

/// 把手势报上来的原始速度采样，变成松手判定和 arm 事件需要的两个数：当前速度，
/// 以及这次手势见过的最高速度。
///
/// 刻意不关心视图——喂采样进去，读数出来。
final class MotionTracker {

    /// 手势报的最新速度，单位 pt/s。
    private(set) var velocity: CGPoint = .zero

    /// 自上次 `reset()` 以来见过的最高速度，单位 pt/s。
    ///
    /// 这是「动量突然变小」能被检测到的关键：arm 条件是*刚才在快速移动* **而且**
    /// *现在几乎停住了*，前半句需要整个手势的记忆，不是单帧的值。
    ///
    /// 这里曾经还算过一个平滑后的加速度——那才是「减速」最直觉的表达——但它的
    /// 噪声大到没法拿来做阈值（两个触摸事件之间差 8ms 就能让它摆动上千），最后
    /// 真正好用的是「峰值速度 + 当前速度」这一对门限，于是那套机械就删掉了。
    private(set) var peakSpeed: CGFloat = 0

    /// 用 `UIScrollView` 自己的阻尼率，这样投影出来的惯性和用户在每一个滚动视图
    /// 上甩出来的手感是一致的。
    var decelerationRate: CGFloat = UIScrollView.DecelerationRate.normal.rawValue

    func reset() {
        velocity = .zero
        peakSpeed = 0
    }

    /// 喂一次采样，通常来自 `UIPanGestureRecognizer.velocity(in:)`。
    func update(velocity newValue: CGPoint) {
        velocity = newValue
        peakSpeed = Swift.max(peakSpeed, newValue.magnitude)
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
