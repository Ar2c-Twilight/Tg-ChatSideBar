//
//  OuterShadowLayer.swift
//  TgChatSideBar
//

import UIKit

/// 只画在形状**外侧**的投影。
///
/// `CALayer` 的投影本质上是「按 `shadowPath` 填充、再模糊」的一块色块，垫在图层
/// 内容后面。内容不透明时你只看得到边缘漏出来的那一圈；可一旦内容变透明，**整块
/// 影子就从里面透出来了**——看起来像中间糊了一团灰。
///
/// 所以这里反过来用和 `InnerGlowLayer` 同一个技巧：给图层加一个**反相遮罩**，
/// 形状是「大一圈的矩形挖掉自己」（even-odd），于是洞里（也就是 bounds 之内）
/// 的影子被裁掉，只剩外侧那一圈。
///
/// 遮罩确实会裁掉投影——`InnerGlowLayer` 也正是靠这一点成立的，两者互为印证。
final class OuterShadowLayer: CALayer {

    /// 圆角，要和被装饰的那个视图一致。
    var shapeCornerRadius: CGFloat = 0

    private let maskLayer = CAShapeLayer()

    override init() {
        super.init()
        shadowColor = UIColor.black.cgColor
        shadowOffset = CGSize(width: 0, height: SidebarMetrics.reliefShadowOffsetY)
        shadowRadius = SidebarMetrics.reliefShadowRadius
        shadowOpacity = 0
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.cgColor
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
        let box = CGRect(origin: .zero, size: bounds.size)
        shadowPath = UIBezierPath(roundedRect: box, cornerRadius: shapeCornerRadius).cgPath

        // 遮罩要盖得比影子能飘到的最远处还宽，否则外侧的影子会被遮罩边界截断。
        let spread = shadowRadius * 3 + abs(shadowOffset.height) + abs(shadowOffset.width)
        maskLayer.frame = box.insetBy(dx: -spread, dy: -spread)
        let outside = UIBezierPath(rect: CGRect(origin: .zero, size: maskLayer.bounds.size))
        outside.append(UIBezierPath(roundedRect: box.offsetBy(dx: spread, dy: spread),
                                    cornerRadius: shapeCornerRadius))
        outside.usesEvenOddFillRule = true
        maskLayer.path = outside.cgPath
    }
}
