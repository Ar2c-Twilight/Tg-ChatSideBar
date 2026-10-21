//
//  LeadingEdges.swift
//  TgChatSideBar
//

import CoreGraphics

/// 高亮框左边那块的**四条边**，每条由一根独立的弹簧驱动。
///
/// 为什么是四条边而不是一个 frame：四条边各自追各自的目标、各有各的滞后，块就会
/// 在移动和变形时被拉扁拉长——果冻感就是这么来的，不是哪一段额外的动画。
///
/// - 纵向（`top` / `bottom`）单位是**行**，目标差一整行。前进方向那条更硬，所以
///   上下移动时块会被拉长。
/// - 横向（`left` / `right`）单位是**pt**，在容器坐标里。目标由分裂进度给，所以
///   收窄成正方形的那一下也是弹着收的。
struct LeadingEdges: Equatable {
    var top: CGFloat
    var bottom: CGFloat
    var left: CGFloat
    var right: CGFloat
}
