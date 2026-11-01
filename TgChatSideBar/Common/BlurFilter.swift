//
//  BlurFilter.swift
//  TgChatSideBar
//

import QuartzCore

/// 一个可以按半径动画的高斯模糊滤镜。
///
/// `CAFilter` 是私有类，但它是**唯一**能让模糊半径成为可动画属性的东西：
/// `UIVisualEffectView` 的半径不可调，`CIFilter` 要走离屏渲染一整套。Telegram
/// 自己也是这么做的（`UIKitRuntimeUtils` 里的 `makeBlurFilter`），只不过它把类名
/// 拆成字符串拼接来规避审核扫描——这是个 demo，不过审，所以直接写。
///
/// 拿到之后挂在 `layer.filters` 上，动画打在 `filters.gaussianBlur.inputRadius`
/// 这个 keypath 上。半径为 0 时要把 `filters` 清空，否则这一层会永远待在离屏
/// 合成通道里。
enum BlurFilter {
    static func make(radius: CGFloat) -> NSObject? {
        let selector = NSSelectorFromString("filterWithName:")
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: "gaussianBlur")?
                .takeUnretainedValue() as? NSObject else {
            return nil
        }
        filter.setValue(radius, forKey: "inputRadius")
        return filter
    }
}
