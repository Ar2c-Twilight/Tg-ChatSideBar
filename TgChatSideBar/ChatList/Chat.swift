//
//  Chat.swift
//  TgChatSideBar
//

import UIKit

/// 会话的占位替身。没有网络、没有持久化——只够让容器知道右边是哪个 chat、
/// 让列表画出一行能区分开的东西。
struct Chat: Identifiable, Equatable {

    let id: Int
    let name: String
    let lastMessage: String
    let tint: UIColor

    static let samples: [Chat] = {
        let names = [
            "Design Review", "Ar2c", "iOS 杂谈", "Fluid Interfaces",
            "家庭群", "Telegram Beta", "Swift 周报", "咖啡搭子",
            "Core Animation", "手势研究所", "午饭吃什么", "UIKit 考古",
            "周末登山", "Metal 渲染", "读书会",
        ]
        let messages = [
            "这个过渡还是有点生硬", "明天上午可以", "26 的 glass 真香",
            "投影公式那段我重看了一遍", "记得带伞", "又崩了…",
            "本周更新挺多", "三点老地方", "隐式动画坑死我了",
            "动量骤降要单独检测", "随便", "这 API 居然 iOS 7 就有了",
            "海拔 1200", "shader 编译好慢", "下周聊这本",
        ]
        // 一律用同一个颜色：这是占位家具，五颜六色的头像会被读成「有含义」，
        // 而它并没有。
        return (0..<names.count).map { index in
            Chat(id: index,
                 name: names[index],
                 lastMessage: messages[index],
                 tint: .systemBlue)
        }
    }()
}
