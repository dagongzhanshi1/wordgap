import AppKit
import SwiftUI

private final class ChineseDefinitionStub: QuickDefinitionAPI {
    var requests: [String] = []
    var fail = false
    var delay: UInt64 = 1_000_000
    var word = Word(id:"let go",word:"let go",phonetic:"",meaning:"phr. 释怀；放下不再纠结",example:"It took time to let go of the past.",exampleTranslation:"放下过去需要时间。",frequency:0,definitionSource:"DeepSeek AI")
    func lookup(_ term: String) async throws -> Word {
        requests.append(term)
        let result = word
        try? await Task.sleep(nanoseconds: delay)
        if fail { throw QuickWordError.message("测试连接失败") }
        return result
    }
}

@MainActor func runChineseQuickAddTests() async throws -> Int {
    var checks = 0
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !condition() { throw TestFailure.failed("中文选词：" + message) }
    }
    func wait() async { try? await Task.sleep(nanoseconds:60_000_000) }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WordGapChineseTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let now = Date(timeIntervalSince1970:1800000000)
    func fresh(_ name: String) -> WordStore { WordStore(folder:folder.appendingPathComponent(name),resource:Bundle.main.resourceURL,clock:{now},randomIndex:{_ in 0}) }
    let context = "释怀（不再纠结过去）"
    try check(QuickWordInput.chineseMeaning("  \(context)  ") == context && QuickWordInput.term(context) == nil, "识别中文和语境，但不能作为英语词直接入库")
    try check(QuickWordInput.query("in spite of") == "in spite of" && QuickWordInput.chineseMeaning("apple") == nil, "英语及原有短语识别保持")
    for invalid in ["中文\n下一行", "中文\t释义", "https://example.com/中文", "中文 sk-example-private-token", String(repeating:"汉",count:61), "123456", ""] {
        try check(QuickWordInput.query(invalid) == nil, "拒绝非词条、多行、过长输入和疑似密钥")
    }

    func response(_ fields: [String:Any]) throws -> Data {
        let content = String(data:try JSONSerialization.data(withJSONObject:fields),encoding:.utf8)!
        return try JSONSerialization.data(withJSONObject:["choices":[["message":["content":content],"finish_reason":"stop"]]])
    }
    let entry: [String:Any] = ["recognized":true,"word":"let go","meaning":"phr. 释怀；放下不再纠结","phonetic":"","example":"Try to let go of the past.","exampleTranslation":"试着放下过去。"]
    let decoded = try QuickDefinitionClient.decode(response(entry),term:context)
    try check(decoded.id == "let go" && decoded.word == "let go" && decoded.meaning.contains("释怀"), "中文请求解析为正常英文短语词条")
    for change: [String:Any] in [["recognized":false],["word":"释怀"],["word":"let go / move on"],["word":"one two three four five six"],["meaning":"no Chinese"],["meaning":""]] {
        var invalid = entry; change.forEach { invalid[$0.key] = $0.value }
        do { _ = try QuickDefinitionClient.decode(response(invalid),term:context); throw TestFailure.failed("无效中文候选被接收") } catch is QuickWordError { checks += 1 }
    }
    do { _ = try QuickDefinitionClient.decode(response(entry),term:"another"); throw TestFailure.failed("英文请求被擅自替换") } catch is QuickWordError { checks += 1 }

    let store = fresh("normal"), api = ChineseDefinitionStub()
    let model = QuickAddModel(store:store,api:api,keyAvailable:true)
    model.prepare(context,origin:"输入")
    try check(model.isChineseInput && !model.canAdd && model.canSubmit && model.submitTitle == "生成英文 ↵", "中文输入只允许生成，不能直接加入中文")
    await wait()
    try check(api.requests.isEmpty && store.pendingQuickTasks.isEmpty, "中文预填等待回车，不自动联网或创建学习记录")

    // Keep the actual SwiftUI input mounted through Chinese -> English replacement.
    let ownProcess = ProcessInfo.processInfo.processIdentifier
    let panel = CardPanel(contentRect:NSRect(origin:NSPoint(x:-10000,y:-10000),size:CardLayout.miniSize),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed = false; defer { panel.orderOut(nil); panel.close() }
    panel.contentView = glassCardHost(QuickAddView(model:model,cancel:{})); panel.orderBack(nil)
    await wait()
    model.submit(); model.submit(); await wait()
    try check(api.requests == [context], "回车仅请求一次，并保留完整中文语境")
    try check(model.term == "let go" && model.meaning.contains("释怀") && model.canAdd && !model.isChineseInput, "英文结果和释义保留，不被输入变更回调清空")
    try check(QuickAddInputFocus.field(in:panel.contentView!)?.stringValue == "let go" && model.status.contains(context), "输入框切成英文，提示保留原中文")
    try check(store.pendingQuickTasks.isEmpty && store.saved.reviews.isEmpty && store.todayCount == 0, "生成候选本身不加词、不算学习")
    model.meaning = "phr. 释怀；不再执着于过去"
    model.submit()
    try check(store.current?.word == "let go" && store.current?.meaning == model.meaning && !store.revealed, "确认后进入普通英文背词卡，保留用户修改的释义")
    try check(store.pendingQuickTasks.count == 1 && store.mode == .newWords && store.todayCount == 0, "使用现有今日新学待学流程")
    store.rate(.knew)
    try check(store.pendingQuickTasks.count == 1 && store.saved.reviews.isEmpty, "中文生成的词同样必须先揭晓再评分")
    store.revealMeaning(); store.rate(.vague)
    try check(store.pendingQuickTasks.isEmpty && store.todayNewCount == 1 && store.saved.reviews["let go"]?.due == now.addingTimeInterval(1800), "模糊后30分钟复习，与其他词一致")
    let reloaded = fresh("normal")
    try check(reloaded.bookIDs.contains("let go") && reloaded.saved.reviews["let go"] == store.saved.reviews["let go"], "重启保留词库与复习排程")
    let count = store.selectedBook!.words.count, review = store.saved.reviews["let go"]
    model.prepare(context,origin:"输入"); model.submit(); await wait()
    try check(model.existing && model.meaning == store.existingQuickWord("let go")?.meaning, "生成命中已有英文词时复用词库释义")
    model.submit()
    try check(store.selectedBook!.words.count == count && store.pendingQuickTasks.count == 1 && store.saved.reviews["let go"] == review, "重复结果不重复建词，实际学习前不改原进度")

    let unavailableAPI = ChineseDefinitionStub(), noKey = QuickAddModel(store:fresh("no-key"),api:unavailableAPI,keyAvailable:false)
    noKey.prepare(context,origin:"输入"); noKey.meaning = "手动中文"; noKey.submit(); await wait()
    try check(!noKey.canAdd && !noKey.canSubmit && unavailableAPI.requests.isEmpty && noKey.term == context && noKey.status.contains("API"), "缺Key时保留中文，不能伪造英文或直接加中文")
    let failedAPI = ChineseDefinitionStub(); failedAPI.fail = true
    let failed = QuickAddModel(store:fresh("failed"),api:failedAPI,keyAvailable:true)
    failed.prepare(context,origin:"输入"); failed.submit(); await wait()
    try check(failed.term == context && !failed.loading && failed.meaning.isEmpty && failed.store.pendingQuickTasks.isEmpty && failed.status.contains("失败"), "网络失败保留中文且不留下词条")

    let slowAPI = ChineseDefinitionStub(); slowAPI.delay = 20_000_000
    let slow = QuickAddModel(store:fresh("slow"),api:slowAPI,keyAvailable:true)
    slow.prepare(context,origin:"输入"); slow.submit(); await Task.yield()
    slow.editTerm("different"); await wait()
    try check(slow.term == "different" && slow.meaning.isEmpty && !slow.loading, "修改输入后丢弃旧中文请求的晚回复")
    slow.prepare(context,origin:"输入"); slow.submit(); await Task.yield(); slow.cancel(); await wait()
    try check(slow.term == context && slow.meaning.isEmpty && !slow.loading, "关闭取消后不被晚回复改成英文")
    let invalidAPI = ChineseDefinitionStub(); invalidAPI.word.word = "释怀"
    let invalid = QuickAddModel(store:fresh("invalid"),api:invalidAPI,keyAvailable:true)
    invalid.prepare(context,origin:"输入"); invalid.submit(); await wait()
    try check(invalid.term == context && !invalid.canAdd && invalid.store.pendingQuickTasks.isEmpty, "无效候选不能进入词库")
    // The user can switch between their own apps during these background checks.
    try check(!NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier != ownProcess, "界面与输入检查不会激活测试进程或抢前台")
    print("CHINESE_QUICK_ADD_TEST_OK: \(checks) checks; contextual generation, confirmation, deduplication, native input, standard study/review, persistence and cancellation")
    return checks
}
