//
//  OuterShadowLayer.swift
//  TgChatSideBar
//

import UIKit

/// 只画在形状**外侧**的投影，**烘焙成位图**，靠九宫格拉伸适配任意尺寸。
///
/// ## 为什么要烘
///
/// `CALayer` 的实时投影每帧都要重新模糊一遍。块一直在被四根弹簧形变，于是每帧
/// 一次模糊 + 一次离屏合成，这是掉帧的大头。烘成图之后，运行时只剩「改一个
/// frame」——九宫格拉伸是 GPU 上最便宜的操作之一，**模糊开销归零**。
///
/// ## 反向遮罩去哪了
///
/// 没有了——它被**烘进位图**里了。
///
/// 实时版本需要一个「大一圈的矩形挖掉自己」的遮罩，把 bounds 之内的影子裁掉
/// （否则填充一透明，整块影子就从里面透出来）。而遮罩意味着每帧一次离屏合成。
/// 现在那个洞是在画图的时候用 `.clear` 混合模式直接挖掉的——位图本身中间就是
/// 透明的，运行时不需要任何遮罩。
///
/// 这也是「怎么优化反向遮罩」的答案：不优化它，**消灭它**。
final class OuterShadowLayer: CALayer {

    /// 影子能飘出形状多远。九宫格的边距要覆盖它，否则拉伸会把影子切断。
    ///
    /// 这里乘 2 是**余量**，不是笔误：`CGContext.setShadow(blur:)` 的 blur 和
    /// `CALayer.shadowRadius` 不是一个量纲——前者大致对应 sigma = blur/2 的高斯，
    /// 可见范围能铺到 1.5 倍 blur。只留 1 倍的话，影子外缘会被位图边界切出一条硬边。
    /// 代价仅仅是位图大几个像素（61→101pt），运行时零开销。
    private var extent: CGFloat {
        SidebarMetrics.reliefShadowRadius * 2 + abs(SidebarMetrics.reliefShadowOffsetY)
    }

    /// 已经烘过的那个圆角值。只有圆角真的变了才重烘——而圆角只在「分裂」那一小段
    /// 里动，之后整个手势都不变，所以实际上只烘屈指可数的几次。
    private var bakedRadius: CGFloat = .nan
    private var bakedScale: CGFloat = 0

    override init() {
        super.init()
        // 这一层只是在展示一张图，自己不需要任何实时效果。
        opacity = 0
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现——本工程不使用 storyboard")
    }

    /// 把这一层摆到 `box` 外面一圈，必要时重烘位图。
    ///
    /// `box` 是被装饰的那个视图的 bounds（在它自己的坐标系里，也就是原点为零）。
    func layout(around box: CGRect, cornerRadius: CGFloat, scale: CGFloat) {
        // frame 每帧都要跟着变，这一句很便宜——拉伸交给 contentsCenter。
        frame = box.insetBy(dx: -extent, dy: -extent)

        let radius = cornerRadius.rounded()      // 取整，省掉几乎看不出差别的重烘
        guard radius != bakedRadius || scale != bakedScale else { return }
        bakedRadius = radius
        bakedScale = scale
        bake(cornerRadius: radius, scale: scale)
    }

    private func bake(cornerRadius radius: CGFloat, scale: CGFloat) {
        // 九宫格：四角按原样贴，中间那 1pt 被拉伸。所以图只要「两个角 + 1pt」这么大。
        let cap = radius + extent
        let side = cap * 2 + 1
        let size = CGSize(width: side, height: side)
        let inner = CGRect(x: extent, y: extent, width: side - extent * 2, height: side - extent * 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let shape = UIBezierPath(roundedRect: inner, cornerRadius: radius).cgPath

            cg.setShadow(offset: CGSize(width: 0, height: SidebarMetrics.reliefShadowOffsetY),
                         blur: SidebarMetrics.reliefShadowRadius,
                         color: UIColor.black.cgColor)
            cg.setFillColor(UIColor.black.cgColor)
            cg.addPath(shape)
            cg.fillPath()

            // 把中间挖空：反向遮罩就是在这一步被烘进位图的。
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.setBlendMode(.clear)
            cg.addPath(shape)
            cg.fillPath()
        }

        contents = image.cgImage
        contentsScale = scale
        contentsCenter = CGRect(x: cap / side, y: cap / side, width: 1 / side, height: 1 / side)
    }
}
