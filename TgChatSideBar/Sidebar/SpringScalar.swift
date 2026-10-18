//
//  SpringScalar.swift
//  TgChatSideBar
//

import QuartzCore

/// 在 display link 上给**一个数**做弹簧动画。
///
/// 为什么不用 `UIViewPropertyAnimator`：这里要动的是 `progress` 这个标量——屏幕
/// 上每一帧都从它派生出来——而不是某个视图属性。用 animator 驱动它意味着要写
/// `pauseAnimation()` + `fractionComplete` +
/// `continueAnimation(withTimingParameters:durationFactor:)`，还要把手指速度和
/// 「时长系数」来回换算。
///
/// 自己积分的话，这个 demo 最在乎的那件事就是白送的：**半路接管动画就是一句
/// `stop()`**——它把当前值*和*当前速度一起交出来，手指从那儿接着走。不回弹、
/// 不跳变。
final class SpringScalar {

    /// 每帧带着新值调用。
    var onChange: ((CGFloat) -> Void)?

    /// 弹簧停稳时调用一次（`stop()` 不会触发它）。
    var onSettle: (() -> Void)?

    private(set) var value: CGFloat = 0

    /// 每秒变化量，单位和 `value` 一致。
    private(set) var velocity: CGFloat = 0

    /// 无阻尼角频率的平方。越大越利落。
    var stiffness: CGFloat = 230

    /// 1 = 不过冲。略小于 1 会有一点点回弹，让吸附像实物而不是机械。
    var dampingRatio: CGFloat = 0.86

    private var target: CGFloat = 0
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    var isAnimating: Bool { link != nil }

    /// 写入值但不碰动画的记账——给拖动用，那时候这个数每帧都归手指管。
    func track(_ newValue: CGFloat) {
        value = newValue
        onChange?(value)
    }

    func animate(to newTarget: CGFloat, initialVelocity: CGFloat) {
        target = newTarget
        velocity = initialVelocity
        guard !isSettled else {
            finish()
            return
        }
        startLink()
    }

    /// 改变目标，但**保留弹簧已有的速度**。给那种半路会翻转的目标用：重新调
    /// `animate(to:initialVelocity:)` 每次都会把速度清零，于是每翻一次顿一下。
    ///
    /// 重复用同一个目标调它是安全的（`startLink` 幂等、`isSettled` 会兜底），而且
    /// 必须如此——`track` 把 value 挪走之后，即使目标没变也得能重新启动。
    func retarget(to newTarget: CGFloat) {
        target = newTarget
        guard !isSettled else {
            finish()
            return
        }
        startLink()
    }

    /// 原地冻结并把状态交出来，好让手势半路接管。**不会**触发 `onSettle`。
    @discardableResult
    func stop() -> (value: CGFloat, velocity: CGFloat) {
        stopLink()
        return (value, velocity)
    }

    private func acceleration(value: CGFloat, velocity: CGFloat) -> CGFloat {
        let omega = stiffness.squareRoot()
        return -stiffness * (value - target) - 2 * dampingRatio * omega * velocity
    }

    private var isSettled: Bool {
        abs(value - target) < 0.0005 && abs(velocity) < 0.005
    }

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    private func finish() {
        stopLink()
        value = target
        velocity = 0
        onChange?(value)
        onSettle?()
    }

    @objc private func step(_ link: CADisplayLink) {
        guard lastTimestamp > 0 else {
            lastTimestamp = link.timestamp
            return
        }
        // 一帧太长的话一次性积分会把弹簧算炸，所以先夹住时长，再用固定小步长走完。
        let elapsed = min(link.timestamp - lastTimestamp, 1.0 / 20.0)
        lastTimestamp = link.timestamp

        let substep: CGFloat = 1.0 / 240.0
        var remaining = CGFloat(elapsed)

        while remaining > 0 {
            let dt = Swift.min(substep, remaining)
            remaining -= dt
            velocity += acceleration(value: value, velocity: velocity) * dt
            value += velocity * dt
        }

        if isSettled {
            finish()
        } else {
            onChange?(value)
        }
    }
}
