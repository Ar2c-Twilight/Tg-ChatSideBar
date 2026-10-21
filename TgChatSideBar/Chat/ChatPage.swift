//
//  ChatPage.swift
//  TgChatSideBar
//

import UIKit

/// 能放进右栏那个槽位的东西。
///
/// 容器对右栏的依赖只有这么多：知道它是哪个 chat（用来判断要不要换、交叉淡入
/// 该不该做）、能把安全区喂给它、以及它是个 `UIViewController`（所以能做子控制器
/// 容器）。除此之外容器不关心里面画的是气泡还是别的什么。
///
/// 有了这层，「第一页放的是调试开关而不是聊天气泡」就不需要在 `ChatViewController`
/// 里加分支——换一个类型就行，容器那边一个字都不用改。
protocol ChatPage: UIViewController {

    /// 这一页对应哪个 chat。`Chat.id` 同时也是它在列表里的行号。
    var chat: Chat { get }

    /// 从**容器**的安全区捕获的内边距。这一页会横向平移出屏幕边缘，所以它自己的
    /// `safeAreaInsets` 拿来布局是没用的。
    var contentInsets: UIEdgeInsets { get set }
}
