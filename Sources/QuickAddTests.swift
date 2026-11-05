import AppKit
import SwiftUI

private final class QuickDefinitionStub: QuickDefinitionAPI {
    var requests = 0
    var fail = false
    var delay: UInt64 = 1_000_000
    func lookup(_ term: String) async throws -> Word {
        requests += 1
        try? await Task.sleep(nanoseconds: delay) // Deliberately ignore cancellation to test stale replies.
        if fail { throw QuickWordError.message("测试连接失败") }
        return Word(id:term.lowercased(),word:term,phonetic:"",meaning:"n. 测试释义",example:"",exampleTranslation:"",frequency:0,definitionSource:"DeepSeek AI")
    }
}

@MainActor func runQuickAddTests(previews: URL?) async throws {
    var checks = 0
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !condition() { throw TestFailure.failed("快捷加词：" + message) }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("WordGapQuickTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let now = Date(timeIntervalSince1970: 1800000000)
    func fresh(_ name: String) -> WordStore { WordStore(folder:root.appendingPathComponent(name),resource:Bundle.main.resourceURL,clock:{now},randomIndex:{_ in 0}) }
    func candidate(_ term: String = "petrichor") -> Word { Word(id:term,word:term,phonetic:"ˈpɛtrɪkɔːr",meaning:"n. 雨后泥土的气息",example:"I love the smell of petrichor.",exampleTranslation:"我喜欢雨后泥土的气息。",frequency:0,definitionSource:"DeepSeek AI") }
    func wait() async { try? await Task.sleep(nanoseconds:60_000_000) }
    let store = fresh("normal")
    let bundled = try Data(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("advanced.json"))
    let originalCount = store.selectedBook!.words.count
    try check(QuickWordInput.term("  (Resilient). ") == "Resilient", "选中文字的标点和空白")
    try check(QuickWordInput.normalized(" DON’T ") == "don't", "大小写与英文弯引号去重")
    for text in ["https://example.com", "two\nwords", "sk-example-private-token", "12345", "中文", String(repeating:"x",count:80), "one two three four five six"] {
        try check(QuickWordInput.term(text) == nil, "拒绝非词条内容")
    }
    try check(QuickWordInput.term("state-of-the-art") != nil && QuickWordInput.term("in spite of") != nil, "支持短语和连字符")
    let existing = store.selectedBook!.words.first!
    let stub = QuickDefinitionStub()
    let model = QuickAddModel(store:store,api:stub,keyAvailable:true)
    model.prepare(existing.word.uppercased(),origin:"测试")
    await wait()
    try check(model.existing && model.meaning == existing.meaning && stub.requests == 0, "已有词直接复用，不请求 API")
    try check(try store.addQuickWord(existing), "已有词明确返回已有")
    try check(!store.revealed && store.current?.id == existing.id && store.pendingQuickTasks.count == 1, "已有词进入隐藏词义的待学卡")
    try check(store.saved.reviews.isEmpty && store.todayCount == 0 && store.saved.studyEvents.isEmpty, "加入不算学习完成")
    store.rate(.knew)
    try check(store.pendingQuickTasks.count == 1 && store.saved.reviews.isEmpty, "未揭晓不能评分")
    store.markMastered()
    try check(!store.saved.mastered.contains(existing.id) && store.pendingQuickTasks.count == 1, "掌握不能跳过主动学习")
    try store.addQuickWord(existing)
    try check(store.pendingQuickTasks.count == 1 && store.selectedBook!.words.count == originalCount, "重复加词不会生成两项任务或重复词条")
    store.revealMeaning(); store.rate(.vague)
    try check(store.pendingQuickTasks.isEmpty && store.todayNewCount == 1 && store.saved.reviews[existing.id]?.due == now.addingTimeInterval(1800), "主动模糊评分完成并安排30分钟")
    store.undo()
    try check(store.pendingQuickTasks.count == 1 && store.saved.reviews[existing.id] == nil && store.todayNewCount == 0, "撤回恢复待学和统计")
    store.revealed = true; store.rate(.knew)
    try check(store.saved.reviews[existing.id]?.due == now.addingTimeInterval(86400), "认识后1天复习")
    store.saved.settings.dailyNewGoal = 1; store.settingsChanged()
    try check(store.current == nil, "原每日目标仍生效")
    let bookID = store.saved.settings.bookID
    try check(try !store.addQuickWord(candidate()), "新词明确返回未收录")
    try check(store.saved.settings.bookID == bookID && store.bookIDs.contains("petrichor"), "补全加入当前词库而不切库")
    try check(store.selectedBook!.words.count == originalCount + 1 && store.saved.quickWords[bookID]?.count == 1, "内置词库通过保存层新增")
    try check(store.current?.id == "petrichor" && !store.revealed && store.todayNewCount == 1 && store.effectiveNewGoal == 2, "已完成目标仍可主动加词")
    try check(try Data(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("advanced.json")) == bundled, "不写入内置词表或破坏签名")
    store.skipWord()
    try check(store.pendingQuickTasks.count == 1 && store.current == nil && store.emptyTitle == "加词仍待学习", "跳过不算完成且不被普通队列重复抽到")
    store.setMode(.review)
    try check(store.emptyTitle != "加词仍待学习", "复习空态保持正确")
    store.resumeQuickStudy()
    try check(store.current?.id == "petrichor" && store.mode == .newWords && !store.revealed, "重新打开优先主动学习")
    let reloaded = fresh("normal")
    try check(reloaded.current?.id == "petrichor" && reloaded.pendingQuickTasks.count == 1 && reloaded.saved.quickWords[bookID]?.first?.definitionSource == "DeepSeek AI", "退出重开仍保留新增词和待学")
    reloaded.revealMeaning(); reloaded.rate(.forgot)
    try check(reloaded.pendingQuickTasks.isEmpty && reloaded.todayNewCount == 2 && reloaded.saved.reviews["petrichor"]?.due == now.addingTimeInterval(600), "不认识也需实际评分，10分钟复习")
    try check(reloaded.effectiveNewGoal == 2, "超额加词完成后分母不会小于分子")
    try reloaded.addQuickWord(candidate()); reloaded.revealMeaning(); reloaded.rate(.knew)
    try check(reloaded.todayNewCount == 2 && reloaded.pendingQuickTasks.isEmpty, "同日再次学同词仍按唯一词统计")
    let finished = fresh("normal")
    try check(finished.pendingQuickTasks.isEmpty && finished.current == nil, "已完成任务重启不会重复强制学习")

    let mastery = fresh("mastery")
    let oldReview = Review(stage:5,due:now.addingTimeInterval(30*86400),last:now,count:7,rating:.knew)
    mastery.saved.reviews[existing.id] = oldReview; mastery.saved.mastered.insert(existing.id); mastery.persist()
    try mastery.addQuickWord(existing)
    try check(mastery.saved.reviews[existing.id] == oldReview && mastery.saved.mastered.contains(existing.id), "加入前不改已有进度和掌握状态")
    mastery.revealMeaning(); mastery.rate(.knew)
    try check(mastery.saved.reviews[existing.id]?.stage == 1 && !mastery.saved.mastered.contains(existing.id) && mastery.todayNewCount == 1, "实际评分才重新开始该词间隔")
    try check(mastery.saved.reviews[existing.id]?.count == 8, "累计学习次数保留，重新学习不清零")
    try check(mastery.saved.studyEvents.last(where:{$0.kind == .rated})?.previousStage == 5, "明细保留原熟悉阶段")
    mastery.undo()
    try check(mastery.saved.reviews[existing.id] == oldReview && mastery.saved.mastered.contains(existing.id) && mastery.pendingQuickTasks.count == 1, "撤回完整恢复旧学习状态")

    let cross = fresh("cross")
    try cross.importWords(data:Data("word\tmeaning\nbluebird\tn. 蓝鸟\n".utf8),filename:"custom.tsv")
    let customID = cross.saved.settings.bookID
    try check(cross.existingQuickWord(existing.word)?.meaning == existing.meaning, "跨活动词库识别已有词")
    try cross.addQuickWord(existing)
    try check(cross.saved.settings.bookID == customID && cross.bookIDs.contains(existing.id), "跨库已有词加入当前库")
    cross.deleteBook(customID)
    try check(cross.pendingQuickTasks.isEmpty && cross.saved.quickStudyTasks.contains(where:{$0.bookID == customID && $0.completedAt == nil}), "删除词库保留历史而不继续弹任务")
    cross.restoreBook(customID); cross.selectBook(customID)
    try check(cross.pendingQuickTasks.count == 1, "恢复词库也恢复待学")

    let empty = fresh("empty")
    empty.deleteBook("advanced")
    try empty.addQuickWord(candidate("serendipity"))
    try check(empty.selectedBook?.name == "随手生词" && empty.pendingQuickTasks.count == 1 && empty.bookIDs.contains("serendipity"), "无活动库时创建随手生词")
    let obstructed = root.appendingPathComponent("unwritable")
    try Data("file".utf8).write(to:obstructed)
    let failure = WordStore(folder:obstructed,resource:Bundle.main.resourceURL,clock:{now})
    do { try failure.addQuickWord(candidate()); throw TestFailure.failed("保存失败未抛错") } catch is QuickWordError { }
    try check(failure.pendingQuickTasks.isEmpty && failure.saved.quickWords.isEmpty && !failure.bookIDs.contains("petrichor"), "保存失败不残留词条或任务")
    let legacy = try JSONDecoder().decode(SavedData.self,from:Data("{}".utf8))
    try check(legacy.quickWords.isEmpty && legacy.quickStudyTasks.isEmpty, "老格式无需新字段即可读取")

    let aiStore = fresh("ai")
    let ai = QuickDefinitionStub(), aiModel = QuickAddModel(store:aiStore,api:QuickDefinitionStub(),keyAvailable:true)
    let asyncModel = QuickAddModel(store:aiStore,api:ai,keyAvailable:true)
    asyncModel.prepare("petrichor",origin:"测试"); await wait()
    try check(ai.requests == 1 && asyncModel.canAdd && asyncModel.meaning == "n. 测试释义" && aiStore.saved.quickStudyTasks.isEmpty, "自动补全后等待用户确认")
    asyncModel.meaning = "n. 自己修改的释义"; asyncModel.submit()
    try check(aiStore.current?.meaning == "n. 自己修改的释义" && aiStore.todayCount == 0 && !aiStore.revealed, "用户修改释义被保存，尚未学完")
    ai.delay = 20_000_000
    asyncModel.prepare("quicktestword",origin:"测试"); await Task.yield()
    asyncModel.term = "quickfailureword"; asyncModel.inspect(); await wait()
    try check(asyncModel.term == "quickfailureword" && asyncModel.meaning.isEmpty && !asyncModel.loading, "编辑单词时丢弃旧回复")
    asyncModel.prepare("quicktestword",origin:"测试"); await Task.yield(); asyncModel.cancel(); await wait()
    try check(asyncModel.meaning.isEmpty && !asyncModel.loading, "关闭时取消且晚回复不改界面")
    ai.fail = true; asyncModel.prepare("quickfailureword",origin:"测试"); await wait()
    try check(asyncModel.term == "quickfailureword" && asyncModel.meaning.isEmpty && asyncModel.status.contains("失败") && aiStore.pendingQuickTasks.count == 1, "失败保留输入且不插入词条")
    aiModel.prepare("petrichor",origin:"测试") // Existing word has no request.
    try check(aiModel.existing, "新增保存后立即可去重")

    func response(_ fields: [String:Any], finish: String = "stop", fenced: Bool = false) throws -> Data {
        var content = String(data:try JSONSerialization.data(withJSONObject:fields),encoding:.utf8)!
        if fenced { content = "```json\n" + content + "\n```" }
        return try JSONSerialization.data(withJSONObject:["choices":[["message":["content":content],"finish_reason":finish]]])
    }
    var entry: [String:Any] = ["recognized":true,"word":"petrichor","meaning":"n. 雨后气息","phonetic":"/ˈpɛtrɪkɔːr/","example":"A pleasant smell.","exampleTranslation":"宜人的气味。"]
    try check(try QuickDefinitionClient.decode(response(entry,fenced:true),term:"petrichor").phonetic == "ˈpɛtrɪkɔːr", "严格解析词条并兼容JSON围栏")
    for change: [String:Any] in [["recognized":false],["word":"other"],["meaning":"no Chinese"],["meaning":""],["phonetic":String(repeating:"x",count:101)]] {
        var invalid = entry; change.forEach { invalid[$0.key] = $0.value }
        do { _ = try QuickDefinitionClient.decode(response(invalid),term:"petrichor"); throw TestFailure.failed("错误AI词条被接收") } catch is QuickWordError { checks += 1 }
    }
    do { _ = try QuickDefinitionClient.decode(response(entry,finish:"length"),term:"petrichor"); throw TestFailure.failed("截断词条被接收") } catch is QuickWordError { checks += 1 }
    entry.removeValue(forKey:"meaning")
    do { _ = try QuickDefinitionClient.decode(response(entry),term:"petrichor"); throw TestFailure.failed("缺字段被接收") } catch is QuickWordError { checks += 1 }
    checks += try await runQuickAddFocusTests(store: aiStore)
    checks += try await runChineseQuickAddTests()
    if let previews {
        try FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true)
        let previewModel = QuickAddModel(store:aiStore,api:QuickDefinitionStub(),keyAvailable:true)
        previewModel.prepare("petrichor",origin:"测试")
        for dark in [false,true] {
            let view = QuickAddView(model:previewModel,cancel:{})
            try renderQuickView(view, size:CardLayout.miniSize,dark:dark,to:previews.appendingPathComponent(dark ? "quick-dark.png" : "quick-light.png"))
        }
        // WindowServer-composited glass is absent from offscreen NSView bitmaps.
        // Also render the readable fallback to inspect text, spacing and disabled states.
        let glassEnabled = GlassAppearanceState.shared.enabled, glassIntensity = GlassAppearanceState.shared.intensity
        GlassAppearanceState.shared.apply(enabled:false,intensity:glassIntensity)
        for dark in [false,true] {
            try renderQuickView(QuickAddView(model:previewModel,cancel:{}),size:CardLayout.miniSize,dark:dark,
                to:previews.appendingPathComponent(dark ? "quick-fallback-dark.png" : "quick-fallback-light.png"))
        }
        previewModel.meaning = ""
        try renderQuickView(QuickAddView(model:previewModel,cancel:{}),size:CardLayout.miniSize,dark:false,
            to:previews.appendingPathComponent("quick-fallback-disabled.png"))
        previewModel.inspect()
        GlassAppearanceState.shared.apply(enabled:glassEnabled,intensity:glassIntensity)
        previewModel.keyAvailable = false; previewModel.term = "serendipitousness"; previewModel.inspect()
        try renderQuickView(QuickAddView(model:previewModel,cancel:{}),size:CardLayout.miniSize,dark:false,to:previews.appendingPathComponent("quick-key.png"))
        previewModel.keyAvailable = true; previewModel.lookup(); await wait()
        try renderQuickView(QuickAddView(model:previewModel,cancel:{}),size:CardLayout.miniSize,dark:false,to:previews.appendingPathComponent("quick-new.png"))
        try renderQuickView(MiniCardView(store:aiStore,speak:{_ in},settings:{},hide:{},togglePin:{},toggleMini:{}),size:CardLayout.miniSize,dark:false,to:previews.appendingPathComponent("pending-mini.png"))
        GlassAppearanceState.shared.apply(enabled:false,intensity:glassIntensity)
        previewModel.term = ""; previewModel.inspect()
        for dark in [false,true] {
            try renderQuickView(QuickAddView(model:previewModel,cancel:{}),size:CardLayout.miniSize,dark:dark,
                to:previews.appendingPathComponent(dark ? "quick-empty-dark.png" : "quick-empty-light.png"))
        }
        previewModel.keyAvailable = true; previewModel.editTerm("释怀（不再纠结过去）")
        for dark in [false,true] {
            try renderQuickView(QuickAddView(model:previewModel,cancel:{}),size:CardLayout.miniSize,dark:dark,
                to:previews.appendingPathComponent(dark ? "quick-chinese-dark.png" : "quick-chinese-light.png"))
        }
        GlassAppearanceState.shared.apply(enabled:glassEnabled,intensity:glassIntensity)
    }
    print("QUICK_ADD_TEST_OK: \(checks) checks")
}

@MainActor private func runQuickAddFocusTests(store: WordStore) async throws -> Int {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw TestFailure.failed("加词输入焦点：" + message) }
    }
    let ownProcess = ProcessInfo.processInfo.processIdentifier
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let saved = try encoder.encode(store.saved)
    for seed in ["", "abandon", ""] {
        let model = QuickAddModel(store: store, api: QuickDefinitionStub(), keyAvailable: false)
        model.term = seed; model.inspect()
        let panel = CardPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: CardLayout.miniSize), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.orderOut(nil); panel.close() }
        panel.contentView = glassCardHost(QuickAddView(model: model, cancel: {}))
        panel.orderBack(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        guard let field = QuickAddInputFocus.field(in: panel.contentView!) else { throw TestFailure.failed("未找到原生单词输入框") }
        try check(!(field is NSSecureTextField), "目标必须是单词栏，不是API Key栏")
        // Reproduce the responder being reset after SwiftUI's initial onAppear.
        panel.makeFirstResponder(nil)
        try check(QuickAddInputFocus.focus(in: panel), "窗口就绪后恢复输入，不依赖onAppear时机")
        guard let editor = field.currentEditor() as? NSTextView else { throw TestFailure.failed("未进入文字编辑模式") }
        try check(panel.firstResponder === editor, "系统第一响应者是单词栏的文字编辑器")
        try check(editor.selectedRange() == NSRange(location: 0, length: (seed as NSString).length), "带入的单词选中，可直接替换")
        editor.insertText("serendipity", replacementRange: editor.selectedRange())
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(model.term == "serendipity", "直接输入能更新词条，不需要鼠标")
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        model.status = "正在更新释义提示"
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(field.currentEditor() === editor && editor.selectedRange().location == 3, "状态更新不会重置光标或反复全选")
    }
    let savedAfterInput = try encoder.encode(store.saved)
    try check(savedAfterInput == saved, "打开和输入不修改学习记录")
    try check(!NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier != ownProcess, "所有检查在屏幕外完成，测试进程不抢前台")
    print("QUICK_FOCUS_TEST_OK: \(checks) checks; empty/prefilled/reopened input, native responder, direct typing, selection, caret retention, no record changes or foreground activation")
    return checks
}

@MainActor private func renderQuickView<Content:View>(_ content: Content, size: NSSize, dark: Bool, to url: URL) throws {
    let panel = CardPanel(contentRect:NSRect(origin:NSPoint(x:-10000,y:-10000),size:size),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed = false; defer { panel.close() }
    panel.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
    let host = glassCardHost(content.environment(\.colorScheme,dark ? .dark : .light))
    panel.contentView = host; panel.setContentSize(size); panel.orderBack(nil)
    RunLoop.main.run(until:Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded()
    // Cache the hosting view itself. NSGlassEffectView is WindowServer-composited
    // and its offscreen parent bitmap contains only an empty glass shell.
    let drawing = cardFeedbackHost(host)
    guard let bitmap = drawing.bitmapImageRepForCachingDisplay(in:drawing.bounds) else { throw TestFailure.failed("预览渲染失败") }
    drawing.cacheDisplay(in:drawing.bounds,to:bitmap)
    guard let data = bitmap.representation(using:.png,properties:[:]) else { throw TestFailure.failed("预览保存失败") }
    try data.write(to:url)
}

@MainActor func runQuickDefinitionLiveTest(destination: URL, key: String?, term: String = "petrichor") async throws {
    let client = QuickDefinitionClient(keyProvider:{key ?? QuickAIKey.read()})
    let word = try await client.lookup(term)
    guard QuickWordInput.term(word.word) != nil, word.definitionSource == "DeepSeek AI",
          QuickWordInput.chineseMeaning(term) != nil || word.id == QuickWordInput.normalized(term) else { throw TestFailure.failed("真实补全未得到有效词条") }
    if term == "petrichor", !word.meaning.contains("雨") { throw TestFailure.failed("真实补全未得到目标词义") }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    try encoder.encode(word).write(to:destination,options:.atomic)
    print("QUICK_DEFINITION_LIVE_OK")
}
