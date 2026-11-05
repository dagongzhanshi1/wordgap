import AppKit
import SwiftUI

func runReviewCountTests(previews: URL? = nil) throws {
    var checks = 0
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw TestFailure.failed(message) }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("WordGapReviewCount-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1800000000))
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
    var time = day.addingTimeInterval(9 * 3600)
    func word(_ id: String) -> Word {
        Word(id: id, word: id, phonetic: "", meaning: "n. 测试释义", example: "", exampleTranslation: "", frequency: 0)
    }
    func review(_ due: Date) -> Review { Review(stage: 2, due: due, last: day, count: 2, rating: .knew) }
    let words = ["current", "overdue", "later", "tomorrow", "unseen", "mastered"].map(word)
    let book = Book(id: "pending-fixture", name: "待复习测试", words: words, isCustom: true)
    let other = Book(id: "other-fixture", name: "另一词库", words: [word("other")], isCustom: true)
    let store = WordStore(folder: root.appendingPathComponent("study"), resource: Bundle.main.resourceURL, clock: { time })
    store.saved = SavedData()
    store.saved.customBooks = [book, other]; store.books = [book, other]; store.allBooks = [book, other]
    store.saved.settings.wordOrder = .alphabetical
    store.saved.settings.mode = .review
    store.saved.reviews = ["current": review(time), "overdue": review(day.addingTimeInterval(-86400)),
                           "later": review(time.addingTimeInterval(1800)), "tomorrow": review(tomorrow),
                           "mastered": review(day), "other": review(time)]
    store.saved.mastered = ["mastered"]
    store.selectBook(book.id)
    try check(store.todayPendingReviewCount == 3, "今日待复习包含逾期、当前和稍后到期词，排除明天、新词、掌握词及其他词库")
    try check(store.dueCount == 2 && store.todayReviewSummary == "今日待复习 3", "当前到期数和今日待复习数必须分开")
    try check(store.dailyProgress == 0, "今天仍待复习的词不能显示为完成")
    let savedBeforeReading = store.saved.reviews
    _ = store.todayPendingReviewCount; _ = store.todayReviewSummary; _ = store.dailyProgress
    try check(store.saved.reviews == savedBeforeReading, "读取待复习数不能改写排程")

    try check(store.current?.id == "current", "固定字母顺序测试应先出现当前到期词")
    store.revealed = true; store.rate(.forgot)
    try check(store.todayPendingReviewCount == 3 && store.dueCount == 1, "不认识10分钟后仍在今天，待复习数保持、当前到期数减少")
    try check(store.todayReviewCount == 1 && store.dailyProgress == 0, "学习量继续记录，但不认识不能虚增完成进度")
    time = time.addingTimeInterval(599); store.next()
    try check(store.current?.id == "overdue" && store.dueCount == 1, "未满10分钟的词不能提前出题")
    time = time.addingTimeInterval(1); store.next()
    try check(store.current?.id == "current" && store.dueCount == 2, "满10分钟重新进入复习，今日待复习数不重复累加")
    store.revealed = true; store.rate(.vague)
    try check(store.todayPendingReviewCount == 3 && store.dueCount == 1, "模糊30分钟后仍在今天，继续保留待复习")
    try check(store.todayReviewCount == 1 && store.saved.studyEvents.filter { $0.kind == .rated }.count == 2,
              "同词再评分仍按不同词计学习量，评分次数正常累计")
    time = time.addingTimeInterval(1799); store.next()
    try check(store.current?.id != "current", "未满30分钟的模糊词不能提前出现")
    time = time.addingTimeInterval(1); store.next()
    try check(store.current?.id == "current", "满30分钟的模糊词可再次评分")
    store.revealed = true; store.rate(.knew)
    try check(store.todayPendingReviewCount == 2 && store.todayReviewCount == 1, "重复词选认识也应使待复习减1，历史复习词数仍去重")
    try check(abs(store.dailyProgress - 1.0 / 3) < 0.00001, "复习进度按今日已移出待复习的比例计算")
    store.undo()
    try check(store.todayPendingReviewCount == 3 && store.dailyProgress == 0, "撤回认识恢复待复习与进度")
    store.rate(.knew)
    try check(store.todayPendingReviewCount == 2, "撤回后重新认识只扣除一次")
    let beforeSkip = store.saved.reviews
    store.skipWord()
    try check(store.todayPendingReviewCount == 2 && store.saved.reviews == beforeSkip, "跳过不能改变今日剩余数或排程")
    store.markMastered()
    try check(store.todayPendingReviewCount == 1, "标记掌握从今日待复习移出")
    store.undo()
    try check(store.todayPendingReviewCount == 2, "撤回掌握恢复今日待复习")
    store.restoreMastered("mastered")
    try check(store.todayPendingReviewCount == 3, "恢复已掌握且逾期的词重新计入")
    store.selectBook(other.id)
    try check(store.todayPendingReviewCount == 1 && store.dueCount == 1, "切换词库使用对应词库的待复习数")
    let reloaded = WordStore(folder: root.appendingPathComponent("study"), resource: Bundle.main.resourceURL, clock: { time })
    try check(reloaded.todayPendingReviewCount == 1 && reloaded.saved.reviews == store.saved.reviews,
              "重启直接从已有排程恢复，不需要迁移或清空数据")

    time = tomorrow.addingTimeInterval(-300)
    let boundaryBook = Book(id: "boundary", name: "跨日测试", words: [word("boundary")], isCustom: true)
    let boundary = WordStore(folder: root.appendingPathComponent("midnight"), resource: Bundle.main.resourceURL, clock: { time })
    boundary.saved = SavedData(); boundary.saved.customBooks = [boundaryBook]
    boundary.books = [boundaryBook]; boundary.allBooks = [boundaryBook]
    boundary.saved.settings.mode = .review
    boundary.saved.reviews = ["boundary": review(time)]
    boundary.selectBook(boundaryBook.id)
    try check(boundary.todayPendingReviewCount == 1 && boundary.current != nil, "午夜前当前到期词计入今天")
    boundary.revealed = true; boundary.rate(.forgot)
    try check(boundary.todayPendingReviewCount == 0 && boundary.dueCount == 0 && boundary.current == nil,
              "23:55的不认识排到明天00:05，从今天待复习移出但不提前展示")
    time = tomorrow; boundary.refreshDay()
    try check(boundary.todayPendingReviewCount == 1 && boundary.dueCount == 0 && boundary.current == nil,
              "跨日自动纳入今天，尚未到期继续等待")
    time = tomorrow.addingTimeInterval(299); boundary.next()
    try check(boundary.current == nil && boundary.todayPendingReviewCount == 1, "跨日后的等待期不会提前出题")
    time = tomorrow.addingTimeInterval(300); boundary.next()
    try check(boundary.current?.id == "boundary", "跨日待复习到期后正常出题")
    boundary.revealed = true; boundary.rate(.vague)
    try check(boundary.todayPendingReviewCount == 1 && boundary.current == nil, "当天模糊仍待复习且不能立即重复")
    time = time.addingTimeInterval(1800); boundary.next()
    boundary.revealed = true; boundary.rate(.knew)
    try check(boundary.todayPendingReviewCount == 0 && boundary.dailyProgress == 1, "认识后移出今天并完成当天复习进度")

    if let previews {
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        let sample = WordStore(folder: root.appendingPathComponent("preview"), resource: Bundle.main.resourceURL, clock: { time })
        sample.saved.settings.mode = .review
        sample.saved.reviews = Dictionary(uniqueKeysWithValues: sample.selectedBook!.words.prefix(607).map { ($0.id, review(time)) })
        sample.next(); sample.revealed = true
        try check(sample.todayReviewSummary == "今日待复习 607", "三位数待复习文案覆盖截图场景")
        let originalGlass = GlassAppearanceState.shared.enabled
        let intensity = GlassAppearanceState.shared.intensity
        GlassAppearanceState.shared.apply(enabled: false, intensity: intensity)
        defer { GlassAppearanceState.shared.apply(enabled: originalGlass, intensity: intensity) }
        for dark in [false, true] {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: CardLayout.miniSize),
                                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = fixedCardHost(MiniCardView(store: sample, speak: { _ in }, settings: {}, hide: {}, togglePin: {}, toggleMini: {}))
            panel.contentView = host; panel.setContentSize(CardLayout.miniSize)
            RunLoop.main.run(until: Date().addingTimeInterval(0.06)); host.layoutSubtreeIfNeeded()
            try check(host.bounds.size == CardLayout.miniSize, "新文案不能撑大244×190迷你卡片")
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw TestFailure.failed("待复习卡片预览失败") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw TestFailure.failed("待复习预览编码失败") }
            try data.write(to: previews.appendingPathComponent(dark ? "mini-dark.png" : "mini-light.png"))
            panel.close()
        }
    }
    print("REVIEW_COUNT_TEST_OK: \(checks) checks; pending vs due, repeated ratings, progress, undo, mastery, skip, books, restart, midnight, unchanged scheduling")
}
