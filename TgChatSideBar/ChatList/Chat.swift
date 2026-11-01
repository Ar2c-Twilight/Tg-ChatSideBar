//
//  Chat.swift
//  TgChatSideBar
//

import UIKit

/// 会话的占位替身。没有网络、没有持久化——只够让容器知道右边是哪个 chat、
/// 让列表画出一行能区分开的东西。
///
/// 气泡的文本也放在这儿：它是**数据**，不是 `ChatViewController` 该编的东西。
/// 内容是这个项目真实的调试过程，这样来回切换的时候每一页都不一样，而且看得出
/// 切的是哪一页——随机噪声做不到这一点，调动画时很难判断换页有没有真的发生。
struct Chat: Identifiable, Equatable {

    let id: Int
    let name: String
    let lastMessage: String
    let tint: UIColor
    /// `(文本, 是不是自己发的)`。
    let script: [(text: String, isOutgoing: Bool)]

    static func == (lhs: Chat, rhs: Chat) -> Bool {
        lhs.id == rhs.id
    }

    static let samples: [Chat] = topics.enumerated().map { index, topic in
        Chat(id: index,
             name: topic.name,
             lastMessage: topic.script.last?.text ?? "",
             // 一律用同一个颜色：这是占位家具，五颜六色的头像会被读成「有含义」，
             // 而它并没有。
             tint: .systemBlue,
             script: topic.script)
    }

    private static let topics: [(name: String, script: [(text: String, isOutgoing: Bool)])] = [
        ("三档停靠", [
            ("从 chat 页往右滑，松手该落在哪儿？", true),
            ("TG 原版就一行：velocity > 1000 || progress > 0.2，一个 OR 两个字面量", false),
            ("只有两个结果。没有「停在中间」这个态", false),
            ("那就加第三个。判据用两条：位移在 0.2…0.8 窗口内，且动量够低", true),
            ("动量用 WWDC18 的投影换算成 progress 单位——「这一甩还会再带多远」", true),
            ("distance = (v/1000) × rate/(1-rate)，rate 0.998 时约等于 v × 0.499", false),
            ("滞回只压在动量上：0.4 进 / 0.6 出", true),
            ("位移是个位置，用户看得见它在哪，没有抖动可言", true),
            ("动量才是噪声源，速度采样逐帧跳。单阈值会让列表在手指悬停时来回抖", false),
            ("从源头消掉，而不是靠调慢动画盖住——后者只是把抖动换成迟钝", true),
        ]),
        ("弹簧还是 CA", [
            ("为什么不用 UIView.animate？那不是通用做法吗", false),
            ("要动的是一个标量 progress，屏幕上每一帧都从它派生", true),
            ("animator 擅长直接动视图属性。用它驱动标量要 pauseAnimation + fractionComplete + continueAnimation，速度传进传出都别扭", true),
            ("自己积分的话，半路抓住就是一句 stop()——它把当前值和当前速度一起交出来", true),
            ("那 TG 切 chat 的滑动为什么是 CA？", false),
            ("因为那个目标只有一个、发一次、中途不改", true),
            ("而且切换本身要堵主线程 40ms，CA 跑在 render server 上不受影响，那正是刚需", true),
            ("果冻能不能也用 CA", false),
            ("不行。它的目标每帧都在变，而 CA 不告诉你当前速度", true),
            ("每次重定目标都会从静止重启，滞后消失，果冻就没了", true),
            ("你要是每帧读 presentation() 差分出速度，那就是用更少的控制权重新实现了一遍积分器", true),
        ]),
        ("果冻效果", [
            ("高亮框在行与行之间跳变，太生硬", false),
            ("给四条边各一根弹簧。前进方向那条更硬、跟在后面那条更软", true),
            ("移动时框会被拉长，停下时弹回来", true),
            ("形变就是两根弹簧的滞后本身，没有单独的动画", true),
            ("侧边的挤压取自纵向弹簧的滞后量，squash = min(lag, 1) × 9", false),
            ("段落感呢", false),
            ("目标是「行」，不是手指。再加十分之一的 lean 朝手指探过去", true),
            ("块坐在行上，但承认手指在哪儿", true),
        ]),
        ("切 chat 的 90 毫秒", [
            ("纵向拖着换聊天，每切一次都卡一下", false),
            ("我先猜是构造控制器贵。插探针测——item.selected 只要 0ms", true),
            ("但 100ms 之后主线程被堵 93ms，最大 132ms。120Hz 下丢 11 帧", true),
            ("那 33ms 是什么", false),
            ("我之前量错了。计时起点放在 makeChild 之后，把同步那一段整个漏掉了", true),
            ("真正的问题是：为什么要重建控制器？我们只是想换数据源", false),
            ("……TG 自己有 updateChatLocationToOther，整棵树零调用方", true),
            ("建一个新的 history node 原地换上，导航栏输入框壁纸全不动", true),
            ("90ms → 40ms。而且是你那句话的措辞把问题问对了的", true),
        ]),
        ("模糊的边缘", [
            ("预告时糊壁纸，但边缘 alpha < 1，露出一圈淡边", false),
            ("高斯要越界采样，而界外什么都没有，所以边缘按半径宽度淡出", true),
            ("CAFilter 的 gaussianBlur 没有边缘钳制开关", true),
            ("那就把层放大，让淡化的那一圈落到可见范围之外，交给父层裁掉", true),
            ("等价于「复制边缘 → 模糊 → 裁切」，只是让采样越界去采真实像素", true),
            ("外扩 = 半径 × 2，按短边算成等比缩放", false),
        ]),
        ("那条切口", [
            ("缩小聊天内容之后，上下出现一条直的切口", false),
            ("我先猜是 historyNode 在裁。设了 clipsToBounds = false——空操作，它本来就是 false", true),
            ("又猜是宽气泡被左右裁。也不对", true),
            ("最后插探针把层级打出来：唯一在裁的是 ChatControllerNode，在屏幕边缘", false),
            ("可内容是缩小的，离边缘更远，按理不会被新切出一条边", true),
            ("切口出现在上边和下边", false),
            ("那就对了——切口一直存在，是被壁纸的 edge effect 盖着的", true),
            ("我们在预告时把那两条毛玻璃淡掉了，遮羞布被我拿走了", true),
            ("不是裁切范围变了，是我拿掉了一层本来在干这件事的东西", true),
            ("那两次猜测都可以靠一开始就问「在哪一边」避免掉", true),
        ]),
        ("粘连拉不出细丝", [
            ("smin 的 k 要大于两倍间距才连得上", true),
            ("但那么大的 k 在两块贴合时会把整体向外吹胀 k/4", true),
            ("颈部粗细和贴合时的外胀是同一个参数，所以拉不出细丝", true),
            ("我自己画了一条带二次腰线的丝，腰部随分离距离线性收细", true),
            ("后来在 TG 的 storyBlob.metal 里看到 dynamicBinding", false),
            ("k 跟着距离走：靠近时小、拉开时长到 2.1 倍", false),
            ("PersistenceFactor 这个名字就是在说这件事", false),
            ("我当时想到过这条路，判成 ad hoc 放弃了。人家已经上线了", true),
            ("他们的抗锯齿也是固定两像素，完全不碰 fwidth", false),
            ("不问梯度，就不会被梯度骗", true),
        ]),
        ("测量还是推理", [
            ("这次会话里我至少有六次推理得很有道理然后被实测打脸", true),
            ("smin 拉不出细丝 → TG 的 dynamicBinding 早解决了", true),
            ("延迟是为了躲主线程开销 → 手势从来没掉过帧", true),
            ("没 ready 的 chat 会显示加载占位 → 它什么都不画", true),
            ("扫过十行只落地一次 → 加载比手指快，每行都落地了", true),
            ("加速度判不了「稳了」→ 判据方向被我写反了", true),
            ("link 会漏停导致读到陈旧的点 → 三个终止状态是同一个 case，不存在那条路径", true),
            ("每一条你都得先跑一遍、看出不对、再告诉我", false),
            ("后来凡是插探针去测的，基本一次就对", true),
            ("「我来猜个 bug」这种句式听起来像发现了问题，实际只是在消耗注意力", true),
        ]),
        ("additive 动画", [
            ("TG 切 chat 用的是 additive position，这是新特性吗", false),
            ("iOS 2 就有了。普通动画是替换，additive 是叠加", true),
            ("呈现值 = 模型值 + 动画值", true),
            ("所以布局可以同时进行。非 additive 的话布局每设一次 position 就把动画掐一次", true),
            ("中断也是安全的——动画被移除时图层已经在正确位置上了", true),
            ("和我们做的事其实同构：把运动表达成相对于正确状态的增量", true),
            ("果冻也是这个形状，形变是两根弹簧的差", false),
        ]),
        ("手势仲裁", [
            ("peek 下在 chat 上纵向滑：要退出 peek，但滚动还得继续", false),
            ("两件事同时发生在一根手指上，不是两个手势抢它", true),
            ("所以嗅探器永远停在 .possible，从不进 .began", true),
            ("没进过 .began 的识别器不参与仲裁——它不挡任何人，也不需要谁为它先失败", true),
            ("点击就是反过来：对停住的页面没有意义，直接拿走", true),
            ("但 chat 自己的点击识别器先成了，我们的被取消", false),
            ("缺的是失败依赖。pan 要排除在外，否则每次滚动起手都要先等点击超时", true),
        ]),
        ("吞掉的触摸", [
            ("停在 peek 时点左边的列表，没反应", false),
            ("hitTest 里写着：过渡期间 return self.view，容器吞掉一切", true),
            ("对运动中的过渡是对的——点下去会落在半路上的控制器", true),
            ("但停住的过渡两边都已经就位，必须对命中测试透明", true),
            ("这是「16 处假设 transition 是暂态的」里兑现的第一处", false),
        ]),
        ("预告的闩锁", [
            ("手指在阈值附近悬停时，视差模糊缩放会一起抖", false),
            ("iPhone 的 home 手势是怎么做的？过了某个点就不再因为手抖退出", true),
            ("那就把一件事拆成两个问法", true),
            ("「现在松手会落在 peek 吗」——逐帧，跟速度，这是判定", true),
            ("「用户是不是在预告里」——这是状态，有进入和退出条件", true),
            ("判定只能打开闩锁，只有位移离开窗口能关掉它", true),
            ("松手仍然走真实判定，快甩该 pop 还是 pop", false),
            ("把两个问题混进一个布尔值才是结构问题，抖动只是症状", true),
        ]),
        ("构建的陷阱", [
            ("改回原版之后，模拟器上效果没变", false),
            ("对一下哈希：archive-root 里的和装着的一样，ipa 里的是另一个", true),
            ("Telegram_archive-root 是 Make.py 后处理打的包，缓存命中时不重新生成", true),
            ("于是出现最难查的那种症状：代码改了、构建报成功、屏幕上没变化", true),
            ("更糟的是它不是每次都错，只在「这次结果恰好命中旧缓存」时才错", true),
            ("而还原改动正是最容易命中缓存的情况", false),
            ("所以这个 bug 偏偏挑在撤销的时候出现，特别容易被误判成「撤销没生效」", true),
            ("顺带，磁盘缓存涨到 144G 把盘塞满了。--disk_cache 没有任何回收机制", true),
        ]),
        ("ListView 的坐标", [
            ("demo 里高亮框的位置是 index × rowHeight 算出来的", true),
            ("TG 这边不行，行由 ListView 自己摆", false),
            ("那就别算，直接问可见节点要 frame", true),
            ("走 convert 的话滚动偏移和各种 inset 都是白送的", true),
            ("弹簧的单位也从「行」改成「点」，顺带不再假设行高一致", true),
        ]),
        ("投稿", [
            ("10 月 11 日那条规则：不再收静态稿、不再收无代码的视频", false),
            ("等于公开承认：交互的细节只能用能跑的东西表达", true),
            ("被收录的那个是把整棵改过的树当新仓库推上去，默认分支叫功能名", false),
            ("落地页里最聪明的是那个 compare/master...feature 链接", true),
            ("reviewer 不用在几万次提交里翻那几百行", true),
            ("还有一节 Status，老实写「只在模拟器上跑过」", false),
            ("不藏短处", true),
            ("我们手上这套，每一个数字背后都有测过的理由", true),
            ("这个说服力，画多少图都换不来", false),
        ]),
    ]
}
