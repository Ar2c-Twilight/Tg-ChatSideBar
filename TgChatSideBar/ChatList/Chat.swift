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
        ("Three detents", [
            ("Swipe right from a chat — where should it land when you let go?", true),
            ("Upstream is one line: velocity > 1000 || progress > 0.2. One OR, two literals", false),
            ("Two outcomes only. There is no “stop in the middle” state", false),
            ("So add a third. Two criteria: displacement inside a 0.2…0.8 window, and momentum low enough", true),
            ("Momentum projected into progress units with the WWDC18 formula — “how much further would this flick carry”", true),
            ("distance = (v/1000) × rate/(1-rate); at rate 0.998 that is about v × 0.499", false),
            ("Hysteresis sits on momentum only: 0.4 to enter, 0.6 to leave", true),
            ("Displacement is a position. The user can see where it is, so there is nothing to flicker", true),
            ("Momentum is the noisy one — velocity samples jump frame to frame. One threshold makes the list judder while a finger hovers", false),
            ("Kill it at the source rather than hiding it behind a slower animation — that only trades judder for sluggishness", true),
        ]),
        ("Spring or CA", [
            ("Why not UIView.animate? Is that not the usual way?", false),
            ("What has to move is a scalar, progress. Every frame on screen is derived from it", true),
            ("Animator is good at driving view properties directly. Driving a scalar with it means pauseAnimation + fractionComplete + continueAnimation, and velocity is awkward in both directions", true),
            ("Integrate it yourself and catching it mid-flight is one call to stop() — which hands back the current value and the current velocity together", true),
            ("Then why is Telegram's own chat-switch slide a CA animation?", false),
            ("Because that target is single, fired once, and never changed mid-flight", true),
            ("And the switch itself blocks the main thread for 40 ms. CA runs on the render server and does not care — which is exactly what it is needed for", true),
            ("Could the jelly use CA too?", false),
            ("No. Its target changes every frame, and CA will not tell you the current velocity", true),
            ("Every retarget would restart from rest, the lag would vanish, and the jelly with it", true),
            ("Read presentation() every frame and difference it for velocity and you have reimplemented the integrator with less control", true),
        ]),
        ("The jelly", [
            ("The highlight block jumps between rows. Too abrupt", false),
            ("Give each of the four edges its own spring. The leading edge stiffer, the trailing one softer", true),
            ("It stretches while it moves and springs back when it lands", true),
            ("The deformation is the lag between two springs. There is no separate animation", true),
            ("The side squash comes from the vertical spring's lag: squash = min(lag, 1) × 9", false),
            ("What about a sense of settling?", false),
            ("The target is the row, not the finger. Then add a tenth of a lean toward the finger", true),
            ("The block sits on the row, but admits where the finger is", true),
        ]),
        ("The 90 ms switch", [
            ("Dragging vertically to change chats, every switch hitches", false),
            ("I assumed building the controller was expensive. Instrumented it — item.selected costs 0 ms", true),
            ("But 100 ms later the main thread is blocked for 93 ms, worst 132 ms. Eleven frames at 120 Hz", true),
            ("Then what was the 33 ms?", false),
            ("I measured it wrong. The timer started after makeChild, which skipped the whole synchronous part", true),
            ("The real question is: why rebuild the controller at all? We only want to swap the data source", false),
            ("…Telegram already has updateChatLocationToOther. Zero callers in the entire tree", true),
            ("Build a new history node and swap it in place — nav bar, input panel and wallpaper never move", true),
            ("90 ms → 40 ms. And it was the wording of your question that framed it right", true),
        ]),
        ("Blurred edges", [
            ("Blurring the wallpaper during the preview leaves a pale rim — edge alpha below 1", false),
            ("Gaussian samples past the boundary, and there is nothing out there, so the edge fades over the radius", true),
            ("CAFilter's gaussianBlur has no edge-clamp switch", true),
            ("So grow the layer, push the faded rim outside the visible area, and let the parent clip it", true),
            ("Equivalent to clamp → blur → crop, except the out-of-bounds samples hit real pixels", true),
            ("Overscan = radius × 2, converted to a uniform scale against the short side", false),
        ]),
        ("That seam", [
            ("After shrinking the chat content, a straight seam appears top and bottom", false),
            ("I assumed historyNode was clipping. Set clipsToBounds = false — a no-op, it already was", true),
            ("Then assumed wide bubbles were being clipped sideways. Also wrong", true),
            ("Finally dumped the layer tree: the only thing clipping is ChatControllerNode, at the screen edge", false),
            ("But the content is smaller, further from the edge. It should not be newly cut", true),
            ("The seam shows up on the top and bottom edges", false),
            ("That is the answer — the seam was always there, hidden under the wallpaper's edge effect", true),
            ("We fade those two frosted strips out during the preview. I removed the thing that was covering it", true),
            ("The clip region did not change. I took away a layer that was already doing this job", true),
            ("Both wrong guesses were avoidable by asking “which edge” first", true),
        ]),
        ("Metaballs with no thread", [
            ("smin needs k larger than twice the gap before the blobs connect at all", true),
            ("But a k that large inflates the whole shape by k/4 when they are touching", true),
            ("Neck thickness and the inflation when touching are the same parameter, so no thin thread is possible", true),
            ("I drew my own thread with a quadratic waist that narrows linearly with separation", true),
            ("Later found dynamicBinding in Telegram's storyBlob.metal", false),
            ("k follows distance: small when close, up to 2.1× when pulled apart", false),
            ("The name PersistenceFactor is saying exactly that", false),
            ("I had considered that route and dismissed it as ad hoc. They had already shipped it", true),
            ("Their antialiasing is a fixed two pixels too — fwidth never enters it", false),
            ("Do not ask the gradient and the gradient cannot lie to you", true),
        ]),
        ("Measure, don't reason", [
            ("In this session I have reasoned my way to a convincing answer and been contradicted by measurement at least six times", true),
            ("smin cannot make a thread → dynamicBinding solved it long ago", true),
            ("The delay exists to dodge main-thread cost → the gesture never dropped a frame", true),
            ("A chat that is not ready shows a loading placeholder → it draws nothing at all", true),
            ("Sweeping ten rows commits once → loading beats the finger, every row committed", true),
            ("Acceleration cannot tell you “settled” → I had the criterion backwards", true),
            ("A missed stop leaves the link reading stale points → all three terminal states are one case, that path does not exist", true),
            ("Every one of those, you had to run first, see it was wrong, and then tell me", false),
            ("Afterwards, anything I instrumented was right the first time", true),
            ("“Let me guess at a bug” sounds like finding a problem. It only spends attention", true),
        ]),
        ("Additive animation", [
            ("Telegram's chat switch uses additive position. Is that new?", false),
            ("It has been there since iOS 2. A normal animation replaces; additive adds", true),
            ("Presented value = model value + animation value", true),
            ("So layout can run at the same time. Without additive, every position assignment kills the animation", true),
            ("Interruption is safe too — when the animation is removed the layer is already in the right place", true),
            ("Structurally the same thing we are doing: express motion as a delta against the correct state", true),
            ("The jelly has that shape as well. The deformation is the difference between two springs", false),
        ]),
        ("Gesture arbitration", [
            ("Dragging vertically on the chat while parked at peek: it should dismiss, and the scroll has to continue", false),
            ("Two things happening to one finger, not two gestures fighting for it", true),
            ("So the sniffer stays at .possible forever and never reaches .began", true),
            ("A recognizer that never began takes no part in arbitration — it blocks nobody, and nobody has to fail for it", true),
            ("A tap is the opposite: meaningless to a parked page, so take it outright", true),
            ("But the chat's own tap recognizer wins first and ours gets cancelled", false),
            ("What was missing is a failure requirement. Pan has to be excluded, or every scroll waits out the tap timeout first", true),
        ]),
        ("Swallowed touches", [
            ("Parked at peek, tapping the list on the left does nothing", false),
            ("hitTest says: during a transition, return self.view. The container swallows everything", true),
            ("Correct for a transition in motion — a tap would land on a controller that is halfway there", true),
            ("But a parked transition has both sides in place and must be transparent to hit testing", true),
            ("First of the sixteen places that assume a transition is transient", false),
        ]),
        ("Latching the preview", [
            ("Hovering near the threshold makes parallax, blur and scale all judder together", false),
            ("How does the iPhone home gesture do it? Past a point, a shaky hand no longer backs it out", true),
            ("So split one thing into two questions", true),
            ("“Would releasing now land at peek” — per frame, follows velocity. That is the verdict", true),
            ("“Is the user inside the preview” — that is a state, with entry and exit conditions", true),
            ("The verdict can only open the latch. Only displacement leaving the window closes it", true),
            ("Release still runs the real verdict — a fast flick still pops", false),
            ("Mixing two questions into one boolean was the structural fault. The judder was only the symptom", true),
        ]),
        ("A build trap", [
            ("After reverting to the original, the simulator showed no change", false),
            ("Compared hashes: the one in archive-root matches what is installed, the one in the ipa is different", true),
            ("Telegram_archive-root is packaged by Make.py post-processing, and is not regenerated on a cache hit", true),
            ("Which produces the worst symptom to debug: code changed, build reported success, screen unchanged", true),
            ("Worse, it is not wrong every time — only when this build happens to hit an old cache entry", true),
            ("And reverting a change is exactly the case most likely to hit one", false),
            ("So the bug waits for the moment you undo something, where it reads as “the undo did not take”", true),
            ("Incidentally the disk cache grew to 144 G and filled the drive. --disk_cache has no eviction at all", true),
        ]),
        ("ListView coordinates", [
            ("In the prototype the highlight position is index × rowHeight", true),
            ("That will not work here. ListView places the rows itself", false),
            ("So stop computing and ask the visible node for its frame", true),
            ("Going through convert gives you the scroll offset and every inset for free", true),
            ("The spring's unit changes from rows to points, and stops assuming uniform row height", true),
        ]),
        ("Submission", [
            ("The rule posted on October 11: no more static work, no more videos without code", false),
            ("Which is an admission that interaction detail can only be expressed by something that runs", true),
            ("The one that got featured pushed the whole modified tree as a new repo, default branch named after the feature", false),
            ("The smartest thing on that landing page is the compare/master...feature link", true),
            ("A reviewer does not have to dig a few hundred lines out of tens of thousands of commits", true),
            ("There is also a Status section that plainly says “simulator only”", false),
            ("No hiding the weak spots", true),
            ("What we have here has a measured reason behind every number", true),
            ("No amount of mockups buys that kind of credibility", false),
        ]),
    ]
}
