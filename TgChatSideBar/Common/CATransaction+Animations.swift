//
//  CATransaction+Animations.swift
//  TgChatSideBar
//

import QuartzCore

extension CATransaction {

    /// 关掉隐式动画跑一段代码。
    ///
    /// 手写的 `CALayer`（不是某个 `UIView` 的背衬图层）**每次属性赋值都会隐式动画
    /// 0.25 秒**。对每帧都要重写 frame / path 的图层来说，表现为「永远慢手指半拍」，
    /// 而且因为每帧都在打断上一次动画，看起来是糊的。所有逐帧写图层的地方都要包这一层。
    static func withoutAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
