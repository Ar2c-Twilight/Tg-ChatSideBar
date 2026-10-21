//
//  InnerGlowLayer.swift
//  TgChatSideBar
//

import UIKit

/// 内阴影：顺着描边**向内**延伸的一圈柔光。
///
/// `CALayer` 的 shadow 只会往外投，所以内阴影得用一个经典的反转技巧：
///
/// 1. 路径取「一个比自己大一圈的矩形」**挖掉**「自己这个圆角矩形」，按 even-odd
///    填充——于是实心的部分在外面，中间是个洞。
/// 2. 给这个形状投影。洞的边缘于是把影子投**进**洞里。
/// 3. 再用圆角矩形做 mask，把外面那圈实心部分裁掉，只留下漏进洞里的那部分影子。
///
/// 影子的颜色用白色，看起来就是沿着边缘向内的一道高光。
final class InnerGlowLayer: CAShapeLayer {

    /// 柔光往内渗多远。
    var glowRadius: CGFloat = 4

    /// 圆角，要和被装饰的那个视图一致。
    var cornerRadius2: CGFloat = 0

    private let maskLayer = CAShapeLayer()

    override init() {
        super.init()
        fillRule = .evenOdd
        // 这一层的填充最终会被 mask 裁掉，只是投影的来源，颜色无所谓但必须不透明。
        fillColor = UIColor.white.cgColor
        shadowColor = UIColor.white.cgColor
        shadowOffset = .zero
        shadowOpacity = 1
        mask = maskLayer
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    /// 重新按当前 `bounds` 算路径。每帧都要调（块一直在形变）。
    func refreshPath() {
        shadowRadius = glowRadius
        let spread = glowRadius * 3        // 外圈要够宽，否则影子会在边界处被截断
        let outside = UIBezierPath(rect: bounds.insetBy(dx: -spread, dy: -spread))
        let hole = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius2)
        outside.append(hole)
        outside.usesEvenOddFillRule = true
        path = outside.cgPath

        maskLayer.frame = bounds
        maskLayer.path = hole.cgPath
    }
}
