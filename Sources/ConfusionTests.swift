import AppKit
import SwiftUI

private func confusionWord(_ term: String, _ meaning: String) -> Word {
    Word(id:term,word:term,phonetic:"",meaning:meaning,example:"",exampleTranslation:"",frequency:0)
}
private let confusionSamples = [
    ConfusionSuggestion(word:"rival",meaning:"竞争对手",kind:.shape,difference:"trivial 指琐碎的事；rival 是竞争对手。"),
    ConfusionSuggestion(word:"trifle",meaning:"琐事",kind:.meaning,difference:"trivial 是形容词；trifle 作名词可指琐事。"),
    ConfusionSuggestion(word:"rifle",meaning:"步枪",kind:.shape,difference:"rival 是竞争对手；rifle 才是步枪。")
]
private final class ConfusionStub: ConfusionAPI {
    var requests:[String] = []
    var fail = false, inflight = 0, maxInflight = 0
    var delay:UInt64 = 25_000_000
    var result = Array(confusionSamples.prefix(2))
    func suggest(for word:Word,nearby:[Word]) async throws -> [ConfusionSuggestion] {
        requests.append(word.word); inflight += 1; maxInflight = max(maxInflight,inflight)
        defer { inflight -= 1 }
        try? await Task.sleep(nanoseconds:delay) // Ignore cancellation deliberately to detect stale replies.
        if fail { throw QuickWordError.message("模拟断网") }
        return result.filter { $0.word != word.word }
    }
}
@MainActor func runConfusionTests(previews:URL?) async throws {
    var checks = 0
    func check(_ value:@autoclosure () throws -> Bool,_ message:String) throws {
        checks += 1; if try !value() { throw TestFailure.failed("易混词："+message) }
    }
    func pause(_ ms:UInt64 = 60) async { try? await Task.sleep(nanoseconds:ms*1_000_000) }
    func until(_ predicate:() -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !predicate() && Date() < limit { await pause(10) }
        try check(predicate(),"异步状态必须在3秒内完成")
    }
    func event(_ code:UInt16,_ text:String = "",_ flags:NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("WordGapConfusionTests-"+UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let word = confusionWord("trivial","adj. 琐碎的；不重要的")
    func response(_ content:String,_ finish:String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject:["choices":[["finish_reason":finish,"message":["content":content]]]])
    }
    func json(_ items:[ConfusionSuggestion],source:String = "trivial") throws -> String {
        struct Result:Encodable { var source:String; var suggestions:[ConfusionSuggestion] }
        return String(data:try JSONEncoder().encode(Result(source:source,suggestions:items)),encoding:.utf8)!
    }
    try check(try ConfusionClient.decode(response(json(Array(confusionSamples.prefix(2)))),for:word).count == 2,"正常结构化回复")
    try check(try ConfusionClient.decode(response("```json\n"+json([])+"\n```"),for:word).isEmpty,"空推荐与代码围栏")
    func reject(_ bytes:Data,_ message:String) throws {
        var rejected = false; do { _ = try ConfusionClient.decode(bytes,for:word) } catch { rejected = true }
        try check(rejected,message)
    }
    try reject(response(json([],source:"other")),"拒绝串词")
    try reject(response(json([confusionSamples[0],confusionSamples[0]])),"拒绝重复")
    try reject(response(json([ConfusionSuggestion(word:"trivial",meaning:"琐碎的",kind:.shape,difference:"目标不能推荐自身") ])),"拒绝原词")
    try reject(response(json(Array(repeating:confusionSamples[0],count:4))),"拒绝超过3个候选")
    try reject(response(json([ConfusionSuggestion(word:"rival",meaning:"competitor",kind:.shape,difference:"缺少中文释义")])),"拒绝缺少中文")
    try reject(response(json([ConfusionSuggestion(word:"rival",meaning:"对手",kind:.shape,difference:String(repeating:"长",count:81))])),"拒绝过长区别")
    try reject(response(json([]),"length"),"拒绝截断回复")
    try reject(response(json([ConfusionSuggestion(word:"rival",meaning:"对手",kind:.shape,difference:"拼写只差一个字母")])),"拒绝可能失真的字母拆解")
    try reject(response("{\"source\":\"trivial\",\"suggestions\":[{\"word\":\"rival\",\"kind\":\"unknown\"}]}"),"拒绝缺失字段和未知类别")
    let peninsula = confusionWord("peninsula","n. 半岛")
    let unnecessary = [ConfusionSuggestion(word:"insult",meaning:"侮辱；冒犯",kind:.shape,difference:"peninsula是半岛；insult是侮辱，词性词义不同。"),
                       ConfusionSuggestion(word:"painful",meaning:"痛苦的",kind:.shape,difference:"peninsula指半岛；painful指痛苦的，词性词义不同。")]
    try check(try ConfusionClient.decode(response(json(unnecessary,source:"peninsula")),for:peninsula).isEmpty,"截图中的牵强形近词应被丢弃，返回没有")
    for (source,other) in [("adapt","adopt"),("affect","effect"),("form","from"),("angel","angle"),("economic","economical"),("trivial","rival")] {
        let item = ConfusionSuggestion(word:other,meaning:"测试释义",kind:.shape,difference:"测试具体区别")
        try check(ConfusionInput.screened([item],for:confusionWord(source,"测试释义")).count == 1,"保留确实形近的整词或相邻换位："+source)
    }
    let positiveMeaning = ConfusionSuggestion(word:"financial",meaning:"财务的",kind:.meaning,difference:"economic指经济，financial侧重资金与财务。")
    let positiveSound = ConfusionSuggestion(word:"flour",meaning:"面粉",kind:.sound,difference:"flower是花，flour是面粉。")
    try check(ConfusionInput.screened([positiveMeaning],for:confusionWord("economic","经济的")).count == 1,"形近过滤不误伤近义用法辨析")
    try check(ConfusionInput.screened([positiveSound],for:confusionWord("flower","花")).count == 1,"形近过滤不冒充音近判断")
    let falseSeeds = ConfusionInput.nearby(peninsula,in:[confusionWord("insult","侮辱"),confusionWord("painful","痛苦的")])
    try check(falseSeeds.isEmpty,"本机拼写线索也不再给出片段相似的词")
    let legacyFolder = root.appendingPathComponent("legacy-quality")
    try FileManager.default.createDirectory(at:legacyFolder,withIntermediateDirectories:true)
    let personalWord = confusionWord("rival","竞争对手")
    var legacyState = ConfusionState()
    legacyState.entries[ConfusionInput.key(peninsula)] = ConfusionEntry(suggestions:unnecessary)
    legacyState.entries[ConfusionInput.key(personalWord)] = ConfusionEntry(suggestions:[confusionSamples[2]],chosen:"rifle")
    let legacyBytes = try JSONEncoder().encode(legacyState)
    let legacyFile = legacyFolder.appendingPathComponent("confusables.json")
    try legacyBytes.write(to:legacyFile)
    let legacyAPI = ConfusionStub(), legacyModel = ConfusionController(folder:legacyFolder,api:legacyAPI,keyAvailable:{true},debounce:0.01)
    legacyModel.present(peninsula,active:true); await pause()
    try check(legacyModel.entry?.suggestions.isEmpty == true && legacyModel.selected == nil,"旧缓存中的截图错误立即过滤")
    try check(legacyAPI.requests.isEmpty && legacyModel.state.entries[ConfusionInput.key(peninsula)]?.suggestions.count == 2,"筛旧缓存不重复请求或改写原始选择")
    try check(legacyModel.handle(event(11,"b",.command)) && legacyModel.filtering && legacyAPI.requests.isEmpty,"空结果可查看且不会重新凑词")
    legacyModel.present(personalWord,active:true)
    try check(legacyModel.selected?.word == "rifle","主动保留的个人易混组合继续保留")
    legacyModel.shutdown()
    try check(try Data(contentsOf:legacyFile) == legacyBytes,"只读过滤不改写本机缓存或排除记录")
    let seeds = ConfusionInput.nearby(confusionWord("rival","对手"),in:[word,confusionWord("rifle","步枪"),confusionWord("arrival","到达"),confusionWord("elephant","象"),confusionWord("RIVAL","对手")])
    try check(seeds.contains(where:{$0.word == "arrival"}) && !seeds.contains(where:{$0.word == "RIVAL" || $0.word == "elephant"}),"本地拼写筛选去重并过滤远词")
    try check(ConfusionInput.key(word) != ConfusionInput.key(confusionWord("trivial","数学中平凡的")),"缓存按英文与词义区分")

    let api = ConfusionStub(), folder = root.appendingPathComponent("main")
    let model = ConfusionController(folder:folder,api:api,keyAvailable:{true},debounce:0.01)
    defer { model.shutdown() }
    model.present(word,active:false); model.request(); await pause()
    try check(api.requests.isEmpty,"隐藏卡片不产生API费用")
    model.setActive(true); await pause()
    try check(api.requests.isEmpty,"打开卡片不自动生成")
    try check(!model.handle(event(34,"i",.command)) && api.requests.isEmpty && !model.loading,"旧⌘I不再触发生成")
    try check(!model.handle(event(11,"b",[.command,.shift])) && api.requests.isEmpty,"⌘B不误截带其他修饰键的组合")
    try check(model.handle(event(11,"b",.command)) && model.loading,"⌘B按需生成并立即给出准备提示")
    try await until { model.entry != nil }
    try check(api.requests == ["trivial"] && model.selected?.word == "rival","自动生成并显示首选")
    model.present(word,active:true); await pause()
    try check(api.requests.count == 1,"缓存命中不重复付费")
    try check(model.handle(event(11,"b",.command)) && model.filtering,"⌘B 打开筛选")
    try check(model.handle(event(48,"\t")) && model.focused?.word == "trifle","Tab 切候选")
    try check(model.handle(event(36,"\r")) && !model.filtering && model.selected?.word == "trifle","回车保留并返回词义")
    model.toggleFilter(); try check(model.handle(event(51)) && model.selected?.word == "rival","删除排除并回到剩余候选")
    try check(model.handle(event(53)) && !model.filtering,"Esc 先退出筛选")
    model.toggleFilter()
    for code:UInt16 in [18,19,20,21,49] { try check(!model.handle(event(code)),"原评分掌握和揭晓键继续传给背词") }
    try check(model.handle(event(124)) && model.handle(event(123)),"筛选内左右键不会跳过原词")
    model.exclude(); try check(model.selected == nil && model.entry?.excluded.count == 2,"可排除全部")
    model.flush()
    let restored = ConfusionController(folder:folder,api:api,keyAvailable:{true},debounce:0.01)
    restored.present(word,active:true); await pause()
    try check(restored.selected == nil && restored.entry?.excluded.count == 2 && api.requests.count == 1,"重启不复活排除词或重新付费")
    restored.restoreCandidates(); restored.cycle(); restored.keep(); restored.flush()
    let retained = ConfusionController(folder:folder,api:api,keyAvailable:{true})
    retained.present(word,active:false)
    try check(retained.selected?.word == "trifle" && retained.entry?.chosen == "trifle","保留选择跨重启")
    retained.setEnabled(false); retained.flush()
    let disabled = ConfusionController(folder:folder,api:api,keyAvailable:{true})
    disabled.present(word,active:true); await pause()
    try check(!disabled.enabled && !disabled.handle(event(11,"b",.command)) && api.requests.count == 1,"关闭开关持久保存且不请求")
    restored.shutdown(); retained.shutdown(); disabled.shutdown()

    let serialAPI = ConfusionStub(); serialAPI.delay = 160_000_000
    let serial = ConfusionController(folder:root.appendingPathComponent("serial"),api:serialAPI,keyAvailable:{true},debounce:0.01)
    let second = confusionWord("modest","谦虚的"), skipped = confusionWord("subtle","微妙的")
    serial.present(word,active:true); serial.request(); try await until { serialAPI.requests.count == 1 }
    serial.present(skipped,active:true); serial.request(); serial.present(second,active:true); serial.request()
    try await until { serial.entry != nil }
    try check(serialAPI.requests == ["trivial","modest"] && serialAPI.maxInflight == 1,"连续切词仅排当前最新词、请求串行")
    try check(serial.state.entries[ConfusionInput.key(word)] != nil && serial.matches(second),"旧回复缓存原词且不改当前词")
    serial.present(word,active:true); try check(!serial.filtering && serial.selected != nil,"返回之前词复用缓存并复位筛选")
    let freshWord = confusionWord("minor","较小的；次要的")
    serial.present(freshWord,active:true); await pause(200)
    try check(serialAPI.requests.count == 2 && serial.entry == nil,"切到无缓存的词也不会自动请求")
    serial.request(); serial.setActive(false); serial.setActive(true); await pause(200)
    try check(serialAPI.requests.count == 2,"收起取消尚未发送的请求，重开不会自行生成")
    serial.shutdown()
    let cancelAPI = ConfusionStub(); cancelAPI.delay = 100_000_000
    let cancel = ConfusionController(folder:root.appendingPathComponent("cancel"),api:cancelAPI,keyAvailable:{true},debounce:0.01)
    cancel.present(word,active:true); cancel.request(); try await until { !cancelAPI.requests.isEmpty }
    cancel.setEnabled(false); await pause(130)
    try check(cancel.entry == nil && !cancel.loading,"禁用后迟到回复不能写入或复活界面")
    cancel.shutdown()
    let failureAPI = ConfusionStub(); failureAPI.fail = true
    let failure = ConfusionController(folder:root.appendingPathComponent("failure"),api:failureAPI,keyAvailable:{true},debounce:0.01)
    failure.present(word,active:true); failure.request(); try await until { !failure.error.isEmpty }
    for _ in 0..<5 { failure.present(word,active:true) }; await pause()
    try check(failureAPI.requests.count == 1 && failure.entry == nil,"失败后不会自动重复请求")
    failureAPI.fail = false; failure.retry(); try await until { failure.entry != nil }
    try check(failureAPI.requests.count == 2,"可主动重试恢复")
    failure.shutdown()
    let missingAPI = ConfusionStub()
    let missing = ConfusionController(folder:root.appendingPathComponent("missing"),api:missingAPI,keyAvailable:{false},debounce:0.01)
    missing.present(word,active:true); missing.request(); await pause()
    try check(missingAPI.requests.isEmpty,"缺失Key不发送请求")
    missing.shutdown()
    let invalid = ConfusionController(folder:root.appendingPathComponent("invalid"),api:missingAPI,keyAvailable:{true},debounce:0.01)
    invalid.present(confusionWord("one two three four five six","无效长句"),active:true); invalid.request(); await pause()
    try check(missingAPI.requests.isEmpty && !invalid.loading && !invalid.error.isEmpty,"不支持的条目不请求且不陷入等待")
    invalid.shutdown()
    let negativeAPI = ConfusionStub(); negativeAPI.result = []
    let negative = ConfusionController(folder:root.appendingPathComponent("negative"),api:negativeAPI,keyAvailable:{true},debounce:0.01)
    negative.present(word,active:true); negative.request(); try await until { negative.entry != nil }
    negative.present(word,active:true); await pause()
    try check(negative.entry?.suggestions.isEmpty == true && negativeAPI.requests.count == 1,"没有可靠候选可留空并缓存")
    negative.shutdown()
    let weakAPI = ConfusionStub(); weakAPI.result = unnecessary
    let weakFolder = root.appendingPathComponent("weak")
    let weak = ConfusionController(folder:weakFolder,api:weakAPI,keyAvailable:{true},debounce:0.01)
    weak.present(peninsula,active:true); weak.request(); try await until { weak.entry != nil }
    try check(weak.entry?.suggestions.isEmpty == true && weak.selected == nil && weak.error.isEmpty,"新回复只有牵强候选时当作正常没有，不提示失败重试")
    weak.flush(); weak.shutdown()
    let weakReloaded = ConfusionController(folder:weakFolder,api:weakAPI,keyAvailable:{true},debounce:0.01)
    weakReloaded.present(peninsula,active:true); _ = weakReloaded.handle(event(11,"b",.command)); await pause()
    try check(weakReloaded.entry?.suggestions.isEmpty == true && weakAPI.requests.count == 1,"没有的结果也持久缓存，重启不自动重新生成")
    weakReloaded.shutdown()
    let backupFolder = root.appendingPathComponent("backup")
    try FileManager.default.createDirectory(at:backupFolder,withIntermediateDirectories:true)
    try Data("invalid".utf8).write(to:backupFolder.appendingPathComponent("confusables.json"))
    try JSONEncoder().encode(model.state).write(to:backupFolder.appendingPathComponent("confusables.backup.json"))
    let recovered = ConfusionController(folder:backupFolder,api:api,keyAvailable:{true})
    try check(recovered.state.entries.count == model.state.entries.count && recovered.error.contains("备份"),"缓存损坏回退独立备份")
    recovered.shutdown()

    let store = WordStore(folder:root.appendingPathComponent("study"),resource:Bundle.main.resourceURL,randomIndex:{_ in 0})
    store.current = word
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let progress = try encoder.encode(store.saved)
    let progressDisk = try Data(contentsOf:root.appendingPathComponent("study/progress.json"))
    let layoutAPI = ConfusionStub()
    let layoutModel = ConfusionController(folder:root.appendingPathComponent("layout-cache"),api:layoutAPI,keyAvailable:{true},debounce:0.01)
    layoutModel.present(word,active:true); layoutModel.request(); try await until { layoutModel.entry != nil }
    // Actual SwiftUI layout in an offscreen native window, including long explanations.
    let panel = CardPanel(contentRect:NSRect(x:-10000,y:-10000,width:244,height:190),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed = false; defer { panel.close(); layoutModel.shutdown() }
    var frames:[String:CGRect] = [:], baseline:[String:CGRect] = [:]
    let host = glassCardHost(MiniCardView(store:store,speak:{_ in},settings:{},hide:{},togglePin:{},toggleMini:{},inspectLayout:{frames = $0},confusions:layoutModel))
    panel.contentView = host; panel.setContentSize(CardLayout.miniSize); panel.orderBack(nil)
    let windowFrame = panel.frame
    if let previews { try FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true) }
    for mode in ["hidden","revealed","picker","excluded","disabled"] {
        store.revealed = mode != "hidden"
        if mode == "picker" { layoutModel.toggleFilter() }
        if mode == "excluded" { layoutModel.exclude(); layoutModel.exclude() }
        if mode == "disabled" { layoutModel.setEnabled(false) }
        for dark in [false,true] {
            panel.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
            await pause(50); host.layoutSubtreeIfNeeded(); await pause(10)
            try check(panel.frame == windowFrame && cardFeedbackHost(host).bounds.size == CardLayout.miniSize,"\(mode)固定迷你窗口尺寸位置")
            try check(frames.count == 4 && frames["meaning"]?.height == 70,"\(mode)含完整词义与评分测量")
            if baseline.isEmpty { baseline = frames }
            try check(frames == baseline,"\(mode)切换筛选和深浅色不挤动任何阅读与评分区域")
            if let previews { try saveConfusionPreview(host,to:previews.appendingPathComponent("\(mode)-\(dark ? "dark" : "light").png")) }
        }
    }
    try check(baseline["meaning"]!.height - 58 >= 12,"解释区实际高度比原版至少多12点")
    try check(baseline["ratings"]!.height == 20,"缩小的是实际评分按钮，保持可点击的20点高度")
    try check(baseline["ratings"]!.minY - baseline["meaning"]!.maxY >= 1.5,"释义和按钮仍有清楚间隔，不互相覆盖")
    // Reproduce the user's long definition plus a two-line contrast, locally.
    let substantial = confusionWord("substantial","adj. 坚固的；结实的；大量的；可观的；重大的，重要的；实质的；基本的；大体上的")
    layoutAPI.result = [ConfusionSuggestion(word:"substantive",meaning:"实质性的",kind:.shape,difference:"substantive强调实质重要或有独立意义，substantial强调量大或坚固。")]
    store.current = substantial; store.revealed = true
    layoutModel.setEnabled(true); layoutModel.present(substantial,active:true); layoutModel.request()
    try await until { layoutModel.entry != nil }
    for dark in [false,true] {
        panel.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        await pause(50); host.layoutSubtreeIfNeeded(); await pause(10)
        try check(panel.frame == windowFrame && frames == baseline,"截图中的长释义与辨析也保持紧凑固定布局")
        if let previews { try saveConfusionPreview(host,to:previews.appendingPathComponent(dark ? "substantial-dark.png" : "substantial-light.png")) }
    }
    // A fresh, uncached word exposes the shortcut without starting a network call.
    let beforeUnrequested = layoutAPI.requests.count
    store.current = freshWord; store.revealed = true; layoutModel.setEnabled(true); layoutModel.present(freshWord,active:true)
    for dark in [false,true] {
        panel.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        await pause(50); host.layoutSubtreeIfNeeded(); await pause(10)
        try check(frames == baseline && panel.frame == windowFrame,"按需入口不移动词义与评分")
        if let previews { try saveConfusionPreview(host,to:previews.appendingPathComponent(dark ? "on-demand-dark.png" : "on-demand-light.png")) }
    }
    try check(layoutAPI.requests.count == beforeUnrequested && !layoutModel.loading,"按需入口显示不触发生成")
    // No useful contrast must be explicit in both the reading area and the picker.
    layoutAPI.result = unnecessary; store.current = peninsula
    layoutModel.present(peninsula,active:true); layoutModel.request(); try await until { layoutModel.entry != nil }
    for filtering in [false,true] {
        layoutModel.filtering = filtering
        for dark in [false,true] {
            panel.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
            await pause(50); host.layoutSubtreeIfNeeded(); await pause(10)
            try check(frames == baseline && panel.frame == windowFrame,"明确没有的提示不移动评分或改变卡片尺寸")
            if let previews { try saveConfusionPreview(host,to:previews.appendingPathComponent("none-\(filtering ? "picker" : "reading")-\(dark ? "dark" : "light").png")) }
        }
    }
    // Long dictionary text and the maximum valid comparison remain scrollable within the same region.
    let longWord = confusionWord("trivial",String(repeating:"adj. 琐碎的；不重要的。",count:30))
    layoutAPI.result = [ConfusionSuggestion(word:"trifle",meaning:"琐事",kind:.meaning,difference:String(repeating:"词性和用法不同。",count:9))]
    store.current = longWord; store.revealed = true
    layoutModel.setEnabled(true); layoutModel.present(longWord,active:true); layoutModel.request()
    try await until { layoutModel.entry != nil }
    for filtering in [false,true] {
        layoutModel.filtering = filtering
        await pause(50); host.layoutSubtreeIfNeeded(); await pause(10)
        try check(panel.frame == windowFrame && frames == baseline,"超长释义和最大辨析不撑大卡片或移动评分")
        if let previews { try saveConfusionPreview(host,to:previews.appendingPathComponent(filtering ? "long-picker.png" : "long-reading.png")) }
    }
    layoutModel.flush()
    try check(try encoder.encode(store.saved) == progress && Data(contentsOf:root.appendingPathComponent("study/progress.json")) == progressDisk,"筛选和持久化不改词库、待学、评分、排程、统计和磁盘记录")
    try check(NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier && !NSApp.isActive,"检查全过程未抢占工作焦点")
    print("CONFUSION_TEST_OK: \(checks) checks; validation, conservative quality, explicit empty result, legacy cache screening, on-demand only, cache, selection, exclusions, keyboard, races, cancellation, fixed layout, study preservation, no foreground activation")
}
@MainActor private func saveConfusionPreview(_ host:NSView,to url:URL) throws {
    // WindowServer's glass cannot be captured offscreen. Use the identical readable
    // fallback content for visual layout inspection, then restore real glass.
    let glass = GlassAppearanceState.shared
    let enabled = glass.enabled, intensity = glass.intensity
    glass.apply(enabled:false,intensity:intensity)
    (host as? LiquidCardHost)?.apply(enabled:false,intensity:intensity)
    defer { glass.apply(enabled:enabled,intensity:intensity); (host as? LiquidCardHost)?.apply(enabled:enabled,intensity:intensity) }
    RunLoop.main.run(until:Date().addingTimeInterval(0.04)); host.layoutSubtreeIfNeeded()
    let drawing = cardFeedbackHost(host)
    guard let bitmap = drawing.bitmapImageRepForCachingDisplay(in:drawing.bounds) else { throw TestFailure.failed("易混词预览失败") }
    drawing.cacheDisplay(in:drawing.bounds,to:bitmap)
    guard let data = bitmap.representation(using:.png,properties:[:]) else { throw TestFailure.failed("易混词预览编码失败") }
    try data.write(to:url)
}
@MainActor func runConfusionLiveTest(destination:URL,key:String?) async throws {
    let client = ConfusionClient(keyProvider:{key ?? QuickAIKey.read()})
    let fixtures = [confusionWord("peninsula","n. 半岛"),confusionWord("adapt","v. 适应；改编"),confusionWord("economic","adj. 经济的；经济学的")]
    var results:[String:[ConfusionSuggestion]] = [:]
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    for word in fixtures {
        let nearby = word.word == "peninsula" ? [confusionWord("insult","侮辱"),confusionWord("painful","痛苦的")] : []
        let items = try await client.suggest(for:word,nearby:nearby)
        results[word.word] = items
        try encoder.encode(results).write(to:destination,options:.atomic)
        if word.word == "peninsula" {
            guard items.isEmpty else { throw QuickWordError.message("截图案例仍给出不必要的推荐") }
        } else { guard !items.isEmpty else { throw QuickWordError.message("确实易混的公开词未获得辨析："+word.word) } }
        try ConfusionInput.validate(items,for:word)
    }
    print("CONFUSION_LIVE_OK: peninsula correctly empty; adapt and economic useful contrasts")
}
