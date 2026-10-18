//
//  CoreGraphics+Math.swift
//  TgChatSideBar
//

import CoreGraphics

extension CGFloat {

    /// 这里的 `Swift.` 前缀不能省：在 `CGFloat` 的扩展里面，裸写的 `min` / `max`
    /// 会解析到 `CGFloat` 自己的静态成员（Xcode 26 SDK）而不是全局函数，整个
    /// 文件会编译不过。
    func clamped(to limits: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}

/// 线性插值。`t` 不夹——需要夹的调用方通常已经用 `normalized(from:to:)` 夹过了。
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

extension CGPoint {

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    var magnitude: CGFloat {
        (x * x + y * y).squareRoot()
    }
}
