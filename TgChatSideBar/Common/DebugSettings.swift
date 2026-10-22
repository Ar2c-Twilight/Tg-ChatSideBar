//
//  DebugSettings.swift
//  TgChatSideBar
//

import Foundation

/// 调试开关。引用类型，容器和开关页共享同一个实例——页面改它，容器听 `onChange`
/// 去应用，不需要把一堆回调从容器穿到页面里。
final class DebugSettings {

    /// 底部那条实时读数。
    var showsReadout = false {
        didSet {
            guard showsReadout != oldValue else { return }
            onChange?()
        }
    }

    /// SGB 进行中覆盖在屏幕上的容许窗口（半透明红框 + 吸附点红线）。
    ///
    /// 注意它只是「允许显示」：实际显不显示还要看手势在不在进行中。
    var showsThresholdOverlay = false {
        didSet {
            guard showsThresholdOverlay != oldValue else { return }
            onChange?()
        }
    }

    var onChange: (() -> Void)?
}
