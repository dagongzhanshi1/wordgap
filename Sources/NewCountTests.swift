import AppKit
import SwiftUI

func runNewCountTests(previews: URL? = nil) throws {
    var checks = 0
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw TestFailure.failed(message) }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("WordGapNewCount-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let calendar = Calendar.current
    var time = calendar.startOfDay(for: Date(timeIntervalSince1970: 1800000000)).addingTimeInterval(9 * 3600)
    func fresh(_ name: String, goal: Int, terms: [String] = ["alpha", "bravo", "charlie", "delta", "echo"]) throws -> WordStore {
        let store = WordStore(folder: root.appendingPathComponent(name), resource: Bundle.main.resourceURL, clock: { time })
        try store.importWords(data: Data(("word\tmeaning\n" + terms.map { $0 + "\tn. 测试词" }.joined(separator: "\n")).utf8), filename: name + ".tsv")
        store.saved.settings.dailyNewGoal = goal
        store.saved.settings.wordOrder = .alphabetical
        store.settingsChanged(); store.next()
        return store
    }
    func candidate() -> Word {
        Word(id: "petrichor", word: "petrichor", phonetic: "", meaning: "n. 雨后泥土的气息", example: "", exampleTranslation: "", frequency: 0)
    }
    let ordinary = try fresh("ordinary", goal: 3)
    try check(ordinary.todayPendingNewCount == 3 && ordinary.todayNewSummary == "今日待新学 3", "初始待新学受每日目标限制，不是整个词库剩余量")
    try check(ordinary.newStudyProgress == 0 && ordinary.newCountHelp.contains("设置目标 3"), "进度和悬停解释与设置目标一致")
    ordinary.rate(.knew)
    try check(ordinary.todayPendingNewCount == 3 && ordinary.todayNewCount == 0, "未揭晓不能误完成新学")
    ordinary.skipWord()
    try check(ordinary.todayPendingNewCount == 3, "跳过不减少待新学数量")
    ordinary.revealed = true; ordinary.rate(.forgot)
    try check(ordinary.todayPendingNewCount == 2 && ordinary.todayNewCount == 1 && ordinary.todayPendingReviewCount == 1,
              "新词不认识完成一次新学，同时按原间隔进入待复习")
    ordinary.undo()
    try check(ordinary.todayPendingNewCount == 3 && ordinary.todayNewCount == 0, "撤回恢复待新学")
    for (index, rating) in [Rating.forgot, .vague, .knew].enumerated() {
        ordinary.revealed = true; ordinary.rate(rating)
        try check(ordinary.todayPendingNewCount == 2 - index && ordinary.todayNewCount == index + 1, "三种评分都只完成一个新词")
    }
    try check(ordinary.todayNewSummary == "今日待新学 0" && ordinary.current == nil && ordinary.newStudyProgress == 1,
              "完成目标显示剩余0，原停止新学规则保持")
    try check(ordinary.todayPendingReviewCount == 2, "新学完成不影响不认识10分钟、模糊30分钟复习")
    let originalGoal = ordinary.saved.settings.dailyNewGoal
    ordinary.saved.settings.dailyNewGoal = 5; ordinary.settingsChanged()
    try check(ordinary.todayPendingNewCount == 2, "提高目标立即增加今日待新学")
    ordinary.saved.settings.dailyNewGoal = originalGoal; ordinary.settingsChanged()
    try check(ordinary.todayPendingNewCount == 0, "降低目标不产生负数或删除已学量")

    let queued = try fresh("queued", goal: 3)
    let queuedWords = Array(queued.selectedBook!.words.prefix(2))
    try queued.addQuickWord(queuedWords[0]); try queued.addQuickWord(queuedWords[1])
    try check(queued.todayPendingNewCount == 3 && queued.pendingQuickTasks.count == 2, "目标内的快捷加词不能与普通新词重复计数")
    try queued.addQuickWord(queuedWords[1])
    try check(queued.todayPendingNewCount == 3 && queued.pendingQuickTasks.count == 2, "重复加入尚未学习的词不能重复计算")
    queued.revealed = true; queued.rate(.knew)
    try check(queued.todayPendingNewCount == 2, "快捷加词评分后减少一次待新学")
    queued.saved.settings.dailyNewGoal = 1; queued.settingsChanged()
    try check(queued.todayPendingNewCount == 1, "目标已满仍需完成其余加词待学任务")

    let extra = try fresh("extra", goal: 1)
    extra.revealed = true; extra.rate(.knew)
    try extra.addQuickWord(candidate())
    try check(extra.todayPendingNewCount == 1 && extra.newStudyProgress < 1, "完成目标后额外加词显示待新学1，而非已完成")
    extra.skipWord()
    try check(extra.todayPendingNewCount == 1 && extra.current == nil, "暂时跳过加词保留任务，不补抽普通新词")
    extra.resumeQuickStudy(); extra.revealed = true; extra.rate(.forgot)
    try check(extra.todayPendingNewCount == 0 && extra.todayNewCount == 2 && extra.saved.settings.dailyNewGoal == 1,
              "额外学完后显示待新学0，已学量超目标但不改写用户设置")
    extra.undo()
    try check(extra.todayPendingNewCount == 1, "撤回额外加词评分恢复待学")
    extra.rate(.knew)
    try extra.addQuickWord(candidate())
    try check(extra.todayPendingNewCount == 1 && extra.todayNewCount == 2, "今天已学过再主动加入仍需再学一次，不能显示0")
    extra.revealed = true; extra.rate(.vague)
    try check(extra.todayPendingNewCount == 0 && extra.todayNewCount == 2, "重复加词评分后任务完成，今日新学量仍去重")
    let reloaded = WordStore(folder: root.appendingPathComponent("extra"), resource: Bundle.main.resourceURL, clock: { time })
    try check(reloaded.todayPendingNewCount == 0 && reloaded.saved.reviews == extra.saved.reviews,
              "退出重开保留学习数据和正确剩余数")

    let short = try fresh("short", goal: 100, terms: ["alpha", "bravo"])
    try check(short.todayPendingNewCount == 2, "词库不足目标时显示实际还能学的词数")
    short.markMastered()
    try check(short.todayPendingNewCount == 1 && short.todayNewCount == 0, "直接掌握不算新学，但不把已排除词留在可学数量里")
    short.revealed = true; short.rate(.knew)
    try check(short.todayPendingNewCount == 0 && short.newStudyProgress == 1, "词库学完显示0")

    let reported = WordStore(folder: root.appendingPathComponent("reported"), resource: Bundle.main.resourceURL, clock: { time })
    let learned = Array(reported.selectedBook!.words.prefix(84))
    reported.saved.settings.dailyNewGoal = 80
    reported.saved.dailyNewWords[reported.todayKey] = learned.map(\.id)
    reported.saved.reviews = Dictionary(uniqueKeysWithValues: learned.map { ($0.id, Review.applying(.knew, previous: nil, now: time)) })
    reported.saved.quickStudyTasks = learned.suffix(4).map {
        QuickStudyTask(wordID: $0.id, bookID: reported.saved.settings.bookID, createdAt: time, completedAt: time)
    }
    reported.next()
    try check(reported.todayNewCount == 84 && reported.effectiveNewGoal == 84, "复现目标80加4个手动词导致旧文案84/84")
    try check(reported.todayNewSummary == "今日待新学 0" && reported.newStudyProgress == 1, "截图场景改为显示今日待新学0")
    try check(reported.newCountHelp.contains("已新学 84") && reported.newCountHelp.contains("设置目标 80"), "已学量和用户目标明确分开")
    try check(reported.saved.settings.dailyNewGoal == 80 && reported.saved.reviews.count == 84, "更新计数不得改写目标或清掉学习记录")

    let sameDay = time
    time = calendar.date(byAdding: .day, value: 1, to: time)!
    ordinary.refreshDay()
    try check(ordinary.todayNewCount == 0 && ordinary.todayPendingNewCount == 2, "跨日重新安排目标，但已学过的词不能混入新词")
    time = sameDay

    if let previews {
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        let sample = try fresh("preview", goal: 200)
        // Use the real bundled vocabulary to inspect a three-digit label in the unchanged mini-card.
        sample.selectBook("advanced")
        let ids = Array(sample.selectedBook!.words.prefix(77)).map(\.id)
        sample.saved.dailyNewWords[sample.todayKey] = ids
        sample.saved.reviews = Dictionary(uniqueKeysWithValues: ids.map { ($0, Review.applying(.knew, previous: nil, now: time)) })
        sample.next()
        try check(sample.todayNewSummary == "今日待新学 123", "三位数剩余文案可在新学模式显示")
        let glass = GlassAppearanceState.shared
        let enabled = glass.enabled, intensity = glass.intensity
        glass.apply(enabled: false, intensity: intensity)
        defer { glass.apply(enabled: enabled, intensity: intensity) }
        for dark in [false, true] {
            for complete in [false, true] {
                let store = complete ? reported : sample
                let panel = NSPanel(contentRect: NSRect(origin: .zero, size: CardLayout.miniSize),
                                    styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let host = fixedCardHost(MiniCardView(store: store, speak: { _ in }, settings: {}, hide: {}, togglePin: {}, toggleMini: {}))
                panel.contentView = host; panel.setContentSize(CardLayout.miniSize)
                RunLoop.main.run(until: Date().addingTimeInterval(0.06)); host.layoutSubtreeIfNeeded()
                try check(host.bounds.size == CardLayout.miniSize, "新文案不改变244×190迷你卡片尺寸")
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw TestFailure.failed("待新学预览失败") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw TestFailure.failed("待新学预览编码失败") }
                try data.write(to: previews.appendingPathComponent("\(complete ? "complete" : "pending")-\(dark ? "dark" : "light").png"))
                panel.close()
            }
        }
    }
    print("NEW_COUNT_TEST_OK: \(checks) checks; remaining new budget, every rating, undo, skip, quick add, repeated quick study, limits, exhausted vocabulary, screenshot84of84, restart, midnight")
}
