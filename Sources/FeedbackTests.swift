import AppKit
import SwiftUI
import QuartzCore

func runFeedbackTests(folder: URL, resource: URL?) throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure.failed(message) }
    }
    let now = Date(timeIntervalSince1970: 1800000000)
    let store = WordStore(folder: folder.appendingPathComponent("answer-feedback"), resource: resource, clock: { now })
    try store.importWords(data: Data("word\tmeaning\nalpha\t甲\nbeta\t乙\ngamma\t丙\ndelta\t丁".utf8), filename: "feedback.tsv")
    var received: [AnswerFeedback] = [], beforeWord: String?, advanced = true
    store.onAnswerFeedback = { kind in
        received.append(kind)
        advanced = advanced && store.current?.id != beforeWord
    }
    store.rate(.knew)
    try check(received.isEmpty, "未揭晓的无效评分不应产生反馈")
    for rating in [Rating.forgot, .vague, .knew] {
        beforeWord = store.current?.id; store.revealMeaning(); store.rate(rating)
    }
    beforeWord = store.current?.id; store.markMastered()
    try check(received == [.forgot, .vague, .knew, .mastered] && advanced,
              "四种操作都应反馈，而且换词必须已经完成，不等待动画")
    store.saved.settings.feedbackSound = true; store.persist()
    let reloaded = WordStore(folder: folder.appendingPathComponent("answer-feedback"), resource: resource, clock: { now })
    try check(reloaded.saved.settings.feedbackSound && reloaded.saved.reviews == store.saved.reviews,
              "提示音开关应保存，且不改变复习记录")

    let app = NSApplication.shared, previous = app.appearance
    app.appearance = nil
    let system = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 244, height: 190),
                          styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = fixedCardHost(Text("外观测试").foregroundStyle(AppPalette.ink).background(AppPalette.background))
    window.contentView = host
    defer { window.close(); app.appearance = previous }
    for _ in 0..<3 {
        AppAppearance.dark.apply(to: app, windows: [window])
        try check(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "深色应应用到原生宿主")
        AppAppearance.system.apply(to: app, windows: [window])
        try check(app.appearance == nil && window.appearance == nil && host.appearance == nil &&
                  host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == system,
                  "从深色回到跟随系统必须清除所有覆盖，恢复系统外观")
    }

    let feedback = AnswerFeedbackController(resource: resource)
    try check(feedback.sounds.count == 4 && feedback.sounds.values.allSatisfy { $0.duration >= 0.25 && $0.duration <= 0.45 },
              "四种提示音必须预加载，且为250至450毫秒的柔和短音")
    let fixedFrame = host.frame, start = CACurrentMediaTime()
    for index in 0..<100 { feedback.show(AnswerFeedback.allCases[index % 4], in: host, soundEnabled: false) }
    let elapsed = CACurrentMediaTime() - start
    try check(elapsed < 0.5 && host.frame == fixedFrame && host.subviews.last?.layer?.animationKeys()?.count == 1,
              "快速反馈不能等待动画、叠加动画队列或改变卡片尺寸")
    try check(host.subviews.last?.hitTest(.zero) == nil, "反馈层不能拦截点击")
    feedback.clear()
    try runCardAudioTests(folder: folder, resource: resource)
    print(String(format: "FEEDBACK_TEST_OK: 四种操作先换词后反馈；100次反馈 %.1f ms；无排队/尺寸变化；短音预加载；深色转系统三轮", elapsed * 1000))
}
