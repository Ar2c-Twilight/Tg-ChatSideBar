#!/usr/bin/env swift
//
// 用鼠标事件驱动模拟器，按 JSON 描述的手势回放，录演示视频用。
//
//   swift simtouch.swift calibrate         标定一次（窗口移动或缩放后重做）
//   swift simtouch.swift hud               浮动显示鼠标的设备坐标
//   swift simtouch.swift record out.json   比划一遍，录成 JSON
//   swift simtouch.swift play shot.json    回放
//
// 坐标一律是「设备点」，标定负责换算到屏幕像素，所以 JSON 不依赖窗口在哪儿、缩放多少。

import AppKit
import CoreGraphics
import Foundation

// ───────────────────────────── 手势格式 ─────────────────────────────

/// ```json
/// {
///   "device": [393, 852],
///   "steps": [
///     { "wait": 1.0 },
///     { "drag": [[0.02, 0.49], [0.42, 0.49]], "duration": 0.8, "ease": "easeOut", "lift": false },
///     { "hold": 0.4, "lift": false },
///     { "drag": [[0.42, 0.49], [0.42, 0.80]], "duration": 1.4, "hold": 0.35 },
///     { "tap": [0.12, 0.35] }
///   ]
/// }
/// ```
///
/// **坐标是归一化的 0…1**，(0.5, 0.5) 是屏幕正中。x 按屏宽归一、y 按屏高归一，所以
/// (1, 1) 是右下角——同一份手势换个机型也落在相对位置上，不用重算点数。
///
/// `device` 只是元数据：映射全靠标定测出来的那个矩形。留着它是为了**对账**——
/// 回放时会拿它的宽高比和标定的矩形比一比，差得多就警告，这样「写了 440×956 却在
/// 393×852 上回放」这种错能当场被抓住，而不是手势悄悄跑偏。
///
/// `drag` 吃任意多个点（折线，不只是两个端点）。`duration` 是整段的总时长。
///
/// **`lift`**（默认 true）是格式里唯一不显然的一项。`wait` 之间手指是抬起来的，
/// 而有些手势必须是一根连续的触摸——比如右滑到分栏、停住、不松手直接往下。
/// 把前面几步标成 `"lift": false`，它们就串成一次触摸，最后一步才抬手。
///
/// **`hold`** 既可以当独立一步，也可以当 `drag` 的尾巴。它不是 `wait`：手指还按着，
/// 而且**持续在发采样**——见 `Finger.hold`。
struct Gesture: Decodable {
    var device: [Double]?
    var steps: [Step]

    struct Step: Decodable {
        var wait: Double?
        var drag: [[Double]]?
        var duration: Double?
        var ease: Easing?
        var hold: Double?
        var tap: [Double]?
        var lift: Bool?
        /// 和 `ease` 同义，写数组时用哪个都行。
        var curve: Easing?
        /// 分镜标记。回放前打印时间轴用，`play` 本身不看它。
        var _comment: String?
    }
}

/// 三次贝塞尔缓动，和 CSS 的 `cubic-bezier()`、AE 的速度曲线是同一套。
///
/// 作用在「走完路径的进度」上，不是作用在坐标上，所以折线的形状不会被曲线改变——
/// 变的只是沿着它走的快慢。
///
/// JSON 里两种写法都认：
///   `"ease": "easeOut"`                     具名预设
///   `"ease": [0.38, 0.70, 0.125, 1.0]`      四个控制点，x1 y1 x2 y2
///
/// **不写就是 `easeInOut`**，不是 `linear`。匀速是机器的走法，人手起步要加速、到位要减速，
/// 而这个脚本存在的理由就是让它看起来不像脚本。要匀速得明写 `"ease": "linear"`。
///
/// 具名预设用的就是 CSS 的那几条定义，不是我自己拍的二次曲线——这样「easeOut」在这里
/// 和在 AE 里是同一条线，对着调不会对不上。
struct Easing: Decodable {
    var x1: Double, y1: Double, x2: Double, y2: Double

    /// 不写 `ease` 时用的那条。
    static let `default` = Easing.presets["easeInOut"]!

    static let presets: [String: Easing] = [
        // CSS 的五条，定义照抄，所以这几个名字在这里和在 AE / 浏览器里是同一条线。
        "linear":    Easing(x1: 0.0,  y1: 0.0,  x2: 1.0,  y2: 1.0),
        "ease":      Easing(x1: 0.25, y1: 0.1,  x2: 0.25, y2: 1.0),
        "easeIn":    Easing(x1: 0.42, y1: 0.0,  x2: 1.0,  y2: 1.0),
        "easeOut":   Easing(x1: 0.0,  y1: 0.0,  x2: 0.58, y2: 1.0),
        "easeInOut": Easing(x1: 0.42, y1: 0.0,  x2: 0.58, y2: 1.0),

        // 一族「冲出去再长尾收住」的减速曲线，从陡到缓。手势里想表现「迅速到位然后稳住」
        // 的那几步用这一族，CSS 那五条在同样的时长里显得软。
        //
        // 前两条是标准幂次缓动的贝塞尔近似，名字不是我起的——对着 1−2^(−10t) 和 1−(1−t)⁵
        // 在 0…1 上采样 201 点比过，最大误差分别是 0.012 和 0.011。
        "easeOutExpo":  Easing(x1: 0.16, y1: 1.0, x2: 0.30, y2: 1.0),
        "easeOutQuint": Easing(x1: 0.22, y1: 1.0, x2: 0.36, y2: 1.0),
        // 比 expo 还陡（对着 1−2^(−10t) 最大误差 0.155），不对应任何标准幂次，所以按行为
        // 命名：前 10% 的时间里走掉一半以上的路程，剩下的全是收尾。
        "snap":         Easing(x1: 0.05, y1: 0.7, x2: 0.10, y2: 1.0),

        // 界面自己切 chat 时用的那条（`NavigationInteractiveDetentMetrics.chatSwitchCurve`）。
        // 手势里想和界面动效同源的地方用它。
        "chatSwitch":   Easing(x1: 0.380, y1: 0.700, x2: 0.125, y2: 1.000),
    ]

    init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard let preset = Easing.presets[name] else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "未知的曲线「\(name)」。可用：\(Easing.presets.keys.sorted().joined(separator: ", "))，或者写成 [x1, y1, x2, y2]。"
                )
            }
            self = preset
            return
        }
        let values = try container.decode([Double].self)
        guard values.count == 4 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "贝塞尔要四个数：[x1, y1, x2, y2]。")
        }
        self.init(x1: values[0], y1: values[1], x2: values[2], y2: values[3])
    }

    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        // 标准三次贝塞尔，首尾控制点锁在 0 和 1。
        let u = 1.0 - t
        return 3.0 * u * u * t * a + 3.0 * u * t * t * b + t * t * t
    }

    private static func bezierSlope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1.0 - t
        return 3.0 * u * u * a + 6.0 * u * t * (b - a) + 3.0 * t * t * (1.0 - b)
    }

    /// 给定时间进度，求位移进度。
    ///
    /// 曲线是参数式的，x 和 y 都由同一个参数 s 决定，所以要先从 x 反解出 s。牛顿迭代
    /// 为主、二分兜底——斜率接近 0 时牛顿会飞出去，那正是 `easeIn` 起点附近的情形。
    func apply(_ x: Double) -> Double {
        let x = min(1.0, max(0.0, x))
        if self.x1 == self.y1 && self.x2 == self.y2 {
            return x
        }
        var s = x
        for _ in 0 ..< 8 {
            let error = Easing.bezier(s, self.x1, self.x2) - x
            if abs(error) < 1e-6 { return Easing.bezier(s, self.y1, self.y2) }
            let slope = Easing.bezierSlope(s, self.x1, self.x2)
            if abs(slope) < 1e-6 { break }
            s -= error / slope
        }
        var low = 0.0, high = 1.0
        s = x
        for _ in 0 ..< 24 {
            let value = Easing.bezier(s, self.x1, self.x2)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = s } else { high = s }
            s = (low + high) / 2.0
        }
        return Easing.bezier(s, self.y1, self.y2)
    }
}

// ───────────────────────────── 标定 ─────────────────────────────

/// 模拟器那块屏幕在 Mac 屏幕坐标系里的位置。
///
/// 不去推算：Simulator 的窗口尺寸不是设备点数的整数倍（含标题栏，还可能带缩放），
/// 从 `CGWindowListCopyWindowInfo` 的 bounds 反推要同时猜好几个量。让人点两下反而准。
///
/// 测的是**整个矩形**（左上 + 右下），不是只测宽度：坐标归一化之后，映射只需要这个矩形，
/// 设备的逻辑尺寸一个都不需要知道。
struct Calibration: Codable {
    var originX: Double
    var originY: Double
    var pixelWidth: Double
    var pixelHeight: Double

    static let path = NSString(string: "~/.simtouch-calibration.json").expandingTildeInPath

    static func load() -> Calibration? {
        guard let data = FileManager.default.contents(atPath: Calibration.path) else { return nil }
        return try? JSONDecoder().decode(Calibration.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: URL(fileURLWithPath: Calibration.path))
    }

    var aspect: Double { self.pixelHeight / self.pixelWidth }

    /// 归一化 → Mac 屏幕像素。
    func screenPoint(_ normalized: CGPoint) -> CGPoint {
        return CGPoint(x: self.originX + Double(normalized.x) * self.pixelWidth,
                       y: self.originY + Double(normalized.y) * self.pixelHeight)
    }

    /// Mac 屏幕像素 → 归一化。
    func normalizedPoint(_ screen: CGPoint) -> CGPoint {
        return CGPoint(x: (Double(screen.x) - self.originX) / self.pixelWidth,
                       y: (Double(screen.y) - self.originY) / self.pixelHeight)
    }
}

/// CGEvent 和 CGWindowList 都是左上原点；`NSEvent.mouseLocation` 是左下原点。
func pointerInCGCoordinates() -> CGPoint {
    let location = NSEvent.mouseLocation
    let height = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0.0
    return CGPoint(x: location.x, y: height - location.y)
}

func calibrate() {
    print("把鼠标移到模拟器屏幕的\u{001B}[1m左上角\u{001B}[0m，回车。")
    _ = readLine()
    let topLeft = pointerInCGCoordinates()
    print("  \(topLeft)")
    print("再移到\u{001B}[1m右下角\u{001B}[0m，回车。")
    _ = readLine()
    let bottomRight = pointerInCGCoordinates()
    print("  \(bottomRight)")

    let width = Double(bottomRight.x - topLeft.x)
    let height = Double(bottomRight.y - topLeft.y)
    guard width > 10.0, height > 10.0 else { print("两点太近，重来。"); exit(1) }
    Calibration(originX: Double(topLeft.x), originY: Double(topLeft.y),
                pixelWidth: width, pixelHeight: height).save()
    print(String(format: "好了：原点 (%.0f, %.0f)，屏幕 %.0f×%.0f 像素，宽高比 %.3f。",
                 Double(topLeft.x), Double(topLeft.y), width, height, height / width))
    print("存在 \(Calibration.path)。窗口挪动或缩放之后要重跑。")
}

// ───────────────────────────── 回放 ─────────────────────────────

struct Finger {
    static let sampleRate: Double = 120.0

    private let calibration: Calibration
    private let source = CGEventSource(stateID: .hidSystemState)
    private(set) var point: CGPoint
    private(set) var isDown = false

    init(calibration: Calibration, at point: CGPoint) {
        self.calibration = calibration
        self.point = point
    }

    private func post(_ type: CGEventType, _ normalized: CGPoint) {
        CGEvent(mouseEventSource: self.source,
                mouseType: type,
                mouseCursorPosition: self.calibration.screenPoint(normalized),
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    mutating func down(at point: CGPoint) {
        self.point = point
        self.post(.mouseMoved, point)
        usleep(useconds_t(touchDownOverhead * 1_000_000.0))
        self.post(.leftMouseDown, point)
        self.isDown = true
    }

    /// 沿折线走完，`ease` 作用在进度上。
    mutating func trace(_ path: [CGPoint], over duration: Double, ease: Easing) {
        guard path.count >= 2 else { return }
        // 长度按**像素**算，不按归一化值算。屏幕不是正方形，直接拿归一化差值求模长会让
        // 纵向的一段显得比它实际短，匀速就不再是匀速了。
        let aspect = self.calibration.aspect
        var lengths: [Double] = []
        var total = 0.0
        for i in 1 ..< path.count {
            let dx = Double(path[i].x - path[i - 1].x)
            let dy = Double(path[i].y - path[i - 1].y) * aspect
            let d = hypot(dx, dy)
            lengths.append(d)
            total += d
        }
        guard total > 0.0 else { return }

        let steps = max(1, Int(duration * Finger.sampleRate))
        for step in 1 ... steps {
            let eased = ease.apply(Double(step) / Double(steps))
            var remaining = eased * total
            var next = path[path.count - 1]
            for (i, length) in lengths.enumerated() {
                if remaining <= length || i == lengths.count - 1 {
                    let f = length > 0.0 ? min(1.0, remaining / length) : 1.0
                    next = CGPoint(x: path[i].x + (path[i + 1].x - path[i].x) * CGFloat(f),
                                   y: path[i].y + (path[i + 1].y - path[i].y) * CGFloat(f))
                    break
                }
                remaining -= length
            }
            self.point = next
            self.post(.leftMouseDragged, next)
            usleep(useconds_t(1_000_000.0 / Finger.sampleRate))
        }
    }

    /// 停住，但**继续发采样**。
    ///
    /// 三档停靠能停住全靠这个：松手的落点由末尾几个采样推出的速度投影决定，
    /// 停住而不发采样等于「手指没动过」，速度会保留滑行时的值，中间那一档就停不住。
    mutating func hold(_ duration: Double) {
        let steps = max(1, Int(duration * Finger.sampleRate))
        for _ in 0 ..< steps {
            self.post(.leftMouseDragged, self.point)
            usleep(useconds_t(1_000_000.0 / Finger.sampleRate))
        }
    }

    mutating func up() {
        guard self.isDown else { return }
        self.post(.leftMouseUp, self.point)
        self.isDown = false
    }

}

/// 按下之前那一下 `mouseMoved` 和它后面的停顿，`Finger.down` 里写死的。
let touchDownOverhead = 0.03
/// `tap` 按住多久，`play` 里写死的。
let tapHoldDuration = 0.05

/// 跑之前先把总时长算出来。
///
/// 和 `play` 走同一套状态机——尤其是 `lift` 的那一份：手指没抬起来的话，下一段 `drag`
/// 不会再付一次按下的开销，算漏了就会和实际差出几十毫秒乘以步数。
///
/// 顺带按 `_comment` 切出时间轴。那些标记就是视频的分镜名，所以这份输出可以直接抄进
/// `BuildComp.jsx` 的 `SECTIONS`。
func describe(_ gesture: Gesture) {
    var total = 0.0
    var isDown = false
    var marks: [(Double, String)] = []

    for step in gesture.steps {
        if let comment = step._comment {
            marks.append((total, comment))
        }
        if let seconds = step.wait {
            isDown = false
            total += seconds
        } else if step.tap != nil {
            isDown = false
            total += touchDownOverhead + tapHoldDuration
        } else if step.drag != nil {
            if !isDown { total += touchDownOverhead }
            total += step.duration ?? 0.5
            total += step.hold ?? 0.0
            isDown = !(step.lift ?? true)
        } else if let hold = step.hold {
            total += hold
            if isDown { isDown = !(step.lift ?? true) }
        }
    }

    print(String(format: "一遍 %.2fs（%d 步），循环间隔 1.5s → 每轮 %.2fs",
                 total, gesture.steps.count, total + 1.5))
    if !marks.isEmpty {
        print("时间轴：")
        for (at, name) in marks {
            print(String(format: "  %6.2fs  %@", at, name))
        }
    }
}

func play(_ gesture: Gesture, _ calibration: Calibration) {
    // 对账。坐标归一化之后 `device` 不参与映射，但它的宽高比应该和标定出来的矩形对得上；
    // 对不上说明 JSON 是照另一个机型写的，手势会整体跑偏，而那种偏差肉眼不一定看得出来。
    if let device = gesture.device, device.count >= 2, device[0] > 0.0 {
        let declared = device[1] / device[0]
        if abs(declared - calibration.aspect) > 0.04 {
            print(String(format: "⚠️  JSON 写的是 %.0f×%.0f（宽高比 %.3f），而标定的屏幕宽高比是 %.3f。",
                         device[0], device[1], declared, calibration.aspect))
            print("   机型多半对不上。要么重新标定，要么改 device。")
        }
    }
    var finger = Finger(calibration: calibration, at: .zero)

    for (index, step) in gesture.steps.enumerated() {
        let lift = step.lift ?? true

        if let seconds = step.wait {
            finger.up()
            usleep(useconds_t(seconds * 1_000_000.0))
            continue
        }

        if let tap = step.tap, tap.count >= 2 {
            finger.up()
            finger.down(at: CGPoint(x: tap[0], y: tap[1]))
            finger.hold(tapHoldDuration)
            finger.up()
            continue
        }

        if let drag = step.drag {
            let path = drag.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            guard let first = path.first else { continue }
            // 上一步说了不抬手就接着走，否则重新按下。
            if !finger.isDown {
                finger.down(at: first)
            }
            finger.trace(path, over: step.duration ?? 0.5, ease: step.ease ?? step.curve ?? Easing.default)
            if let hold = step.hold { finger.hold(hold) }
            if lift { finger.up() }
            continue
        }

        if let hold = step.hold {
            if !finger.isDown {
                print("  第 \(index + 1) 步是 hold，但手指没按着——当成 wait 处理了。")
                usleep(useconds_t(hold * 1_000_000.0))
            } else {
                finger.hold(hold)
                if lift { finger.up() }
            }
            continue
        }
    }
    finger.up()
}

// ───────────────────────────── HUD / 录制 ─────────────────────────────

/// 浮在最上层的坐标读数。Android 的「指针位置」那个东西。
final class HUD: NSObject {
    private let window: NSWindow
    private let label: NSTextField
    private let calibration: Calibration
    /// 只用来把读数同时显示成点数，映射不需要它。
    private let devicePointWidth: Double?
    private(set) var recorder: Recorder?

    init(calibration: Calibration, devicePointWidth: Double?, recordingTo path: String?) {
        self.calibration = calibration
        self.devicePointWidth = devicePointWidth
        self.recorder = path.map { Recorder(path: $0, devicePointWidth: devicePointWidth) }

        self.label = NSTextField(labelWithString: "—")
        self.label.font = NSFont.monospacedDigitSystemFont(ofSize: 15.0, weight: .medium)
        self.label.textColor = .white
        self.label.alignment = .center

        self.window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 300, height: 46),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.level = .floating
        self.window.isOpaque = false
        self.window.backgroundColor = NSColor.black.withAlphaComponent(0.78)
        self.window.hasShadow = true
        self.window.ignoresMouseEvents = true
        self.window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.window.contentView?.addSubview(self.label)
        self.label.frame = NSRect(x: 0, y: 13, width: 300, height: 20)
        self.window.orderFrontRegardless()

        super.init()
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // 自己这个进程里的事件也要看，否则在 HUD 上方移动时读数会卡住。
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        let n = self.calibration.normalizedPoint(pointerInCGCoordinates())
        var text = String(format: "%.4f, %.4f", n.x, n.y)
        // 点数一起显示：手势的阈值都是按点写的（92pt 的列宽、68pt 的行高），
        // 归一化值读不出那些关系。
        if let width = self.devicePointWidth {
            let height = width * self.calibration.aspect
            text += String(format: "   (%.0f, %.0f)pt", Double(n.x) * width, Double(n.y) * height)
        }
        if n.x < 0.0 || n.y < 0.0 || n.x > 1.0 || n.y > 1.0 {
            text += "  屏幕外"
        }
        self.label.stringValue = text
        self.recorder?.handle(event, normalized: n)
    }
}

/// 把比划出来的东西录成上面那个 JSON 格式。
///
/// 折线会被抽稀：鼠标每帧都在动，原样写出来是几百个点，没法读也没法改。保留的是
/// 「偏离直线超过 2pt」的拐点，直线段只留两端。
final class Recorder {
    private let path: String
    private let devicePointWidth: Double?
    private var steps: [String] = []
    private var current: [CGPoint] = []
    private var downAt: Date?
    private var lastEventAt: Date?

    init(path: String, devicePointWidth: Double?) {
        self.path = path
        self.devicePointWidth = devicePointWidth
        print("录制中。按住拖动=drag，单击=tap，Ctrl-C 结束并写出。")
    }

    func handle(_ event: NSEvent, normalized device: CGPoint) {
        switch event.type {
        case .leftMouseDown:
            if let last = self.lastEventAt {
                let gap = Date().timeIntervalSince(last)
                if gap > 0.15 { self.steps.append(String(format: "    { \"wait\": %.2f }", gap)) }
            }
            self.downAt = Date()
            self.current = [device]
        case .leftMouseDragged:
            self.current.append(device)
        case .leftMouseUp:
            defer { self.lastEventAt = Date(); self.current = [] }
            guard let downAt = self.downAt else { return }
            let duration = Date().timeIntervalSince(downAt)
            // 2pt 的容差，换算成归一化值。没有设备宽度就按 393 估一个。
            let simplified = Recorder.simplify(self.current, tolerance: 2.0 / (self.devicePointWidth ?? 393.0))
            if simplified.count < 2 || duration < 0.12 {
                self.steps.append(String(format: "    { \"tap\": [%.4f, %.4f] }", device.x, device.y))
            } else {
                let points = simplified.map { String(format: "[%.4f, %.4f]", $0.x, $0.y) }.joined(separator: ", ")
                self.steps.append(String(format: "    { \"drag\": [%@], \"duration\": %.2f }", points, duration))
            }
        default:
            break
        }
    }

    /// Ramer–Douglas–Peucker，够用的那一版。
    static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var maxDistance = 0.0
        var index = 0
        let first = points[0], last = points[points.count - 1]
        for i in 1 ..< points.count - 1 {
            let d = Recorder.distance(points[i], first, last)
            if d > maxDistance { maxDistance = d; index = i }
        }
        if maxDistance <= tolerance { return [first, last] }
        let left = Recorder.simplify(Array(points[0 ... index]), tolerance: tolerance)
        let right = Recorder.simplify(Array(points[index ..< points.count]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let length = hypot(dx, dy)
        guard length > 0.0 else { return hypot(Double(p.x - a.x), Double(p.y - a.y)) }
        return abs(dy * Double(p.x) - dx * Double(p.y) + Double(b.x) * Double(a.y) - Double(b.y) * Double(a.x)) / length
    }

    func write() {
        let device = self.devicePointWidth.map { "[\(Int($0)), \(Int($0 * 852.0 / 393.0))]" } ?? "null"
        let json = """
        {
          "device": \(device),
          "steps": [
        \(self.steps.joined(separator: ",\n"))
          ]
        }
        """
        try? json.write(toFile: self.path, atomically: true, encoding: .utf8)
        print("\n写到 \(self.path)（\(self.steps.count) 步）。duration 和 ease 多半要手调。")
    }
}

// ───────────────────────────── 入口 ─────────────────────────────

let arguments = Array(CommandLine.arguments.dropFirst())
/// DispatchSource 不被持有就会立刻失效。
var interruptSource: DispatchSourceSignal?

func requireCalibration() -> Calibration {
    guard let calibration = Calibration.load() else {
        print("还没标定。先跑 `swift simtouch.swift calibrate`。")
        exit(1)
    }
    return calibration
}

func activateSimulator() {
    NSWorkspace.shared.runningApplications
        .first { $0.bundleIdentifier == "com.apple.iphonesimulator" }?
        .activate()
    usleep(600_000)
}

switch arguments.first {
case "calibrate":
    calibrate()

case "hud", "record":
    let calibration = requireCalibration()
    let width = Double(ProcessInfo.processInfo.environment["SIMTOUCH_WIDTH"] ?? "")
    let outputPath = arguments.first == "record" ? (arguments.count > 1 ? arguments[1] : "gesture.json") : nil
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let hud = HUD(calibration: calibration, devicePointWidth: width, recordingTo: outputPath)
    hud.start()
    // Ctrl-C 是录制的正常结束方式，所以它必须负责写出来。`signal` 的处理函数里能做的
    // 事很有限，所以只在 DispatchSource 上挂，让它回到主线程再写。
    if hud.recorder != nil {
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler { hud.recorder?.write(); exit(0) }
        interrupt.resume()
        interruptSource = interrupt
    }
    if let width {
        print(String(format: "读数同时显示点数，按屏宽 %.0fpt 算。Ctrl-C 退出。", width))
    } else {
        print("只显示归一化坐标。想同时看点数就设 SIMTOUCH_WIDTH=393。Ctrl-C 退出。")
    }
    app.run()

case "play":
    guard arguments.count > 1, let data = FileManager.default.contents(atPath: arguments[1]) else {
        print("要一个 JSON 文件。")
        exit(1)
    }
    guard let gesture = try? JSONDecoder().decode(Gesture.self, from: data) else {
        print("JSON 解析失败。")
        exit(1)
    }
    let calibration = requireCalibration()
    describe(gesture)
    activateSimulator()
    print("三秒后开始（给录屏留一个干净的头）。")
    usleep(3_000_000)
    play(gesture, calibration)
    usleep(1_500_000)
    print("完。")

default:
    print("""
    swift simtouch.swift calibrate        标定（窗口移动或缩放后重做）
    swift simtouch.swift hud              浮动显示鼠标的设备坐标
    swift simtouch.swift record out.json  比划一遍，录成 JSON
    swift simtouch.swift play shot.json   回放
    """)
}
