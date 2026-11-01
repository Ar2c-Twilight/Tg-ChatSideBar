//
//  DebugSettings.swift
//  TgChatSideBar
//

import Foundation

/// 调试开关。**改代码，不在界面上拨。**
///
/// 原来是个引用类型，第一行 chat 是一页开关，容器听它的 `onChange` 去应用。那套
/// 在模拟器上拨着方便，但代价是：模型里要多一个 `Kind`、右栏要多一个页面类型、
/// 为了容纳两种页面还要开一个协议——三层结构只为两个布尔值服务。
///
/// 现在就是两个常量。想看读数就改这里重编，二十秒的事。
enum DebugSettings {

    /// 底部那条实时读数。
    static let showsReadout = false

    /// SGB 进行中覆盖在屏幕上的容许窗口（半透明红框 + 吸附点红线）。
    ///
    /// 注意它只是「允许显示」：实际显不显示还要看手势在不在进行中。
    static let showsThresholdOverlay = false
}
