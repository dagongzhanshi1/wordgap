import Foundation
import AppKit

enum TestFailure: Error { case failed(String) }

func runSelfTests() throws {
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try condition() == false { throw TestFailure.failed(message) }
    }
    let now = Date(timeIntervalSince1970: 1800000000)
    let first = Review.applying(.knew, previous: nil, now: now)
    try check(first.stage == 1 && first.due.timeIntervalSince(now) == 86400, "首次认识应在一天后复习")
    let second = Review.applying(.knew, previous: first, now: now)
    try check(second.stage == 2 && second.due.timeIntervalSince(now) == 3 * 86400, "连续认识应延长到三天")
    let forgot = Review.applying(.forgot, previous: second, now: now)
    try check(forgot.stage == 0 && forgot.due.timeIntervalSince(now) == 600, "遗忘应重置并安排十分钟后复习")
    let vague = Review.applying(.vague, previous: second, now: now)
    try check(vague.stage == 1 && vague.due.timeIntervalSince(now) == 1800, "模糊应降低阶段并安排30分钟后复习")
    let recognizedAgain = Review.applying(.knew, previous: vague, now: now.addingTimeInterval(1800))
    try check(recognizedAgain.stage == 2 && recognizedAgain.due.timeIntervalSince(vague.due) == 3 * 86400,
              "模糊后再次认识，应从当前阶段继续按天复习")

    let csv = "\u{FEFF}word,meaning,phonetic,example,example_translation\r\nresilient,\"有韧性, 能恢复\",rɪˈzɪliənt,\"She said, \"\"stay strong\"\".\",保持坚强\r\nResilient,重复,r,,\r\nblank,,,,\r\n"
    let imported = try WordImporter.parse(Data(csv.utf8), filename: "words.csv")
    try check(imported.count == 1, "CSV 应过滤空释义并按大小写合并重复词")
    try check(imported[0].meaning == "有韧性, 能恢复", "引号中的逗号应保留")
    try check(imported[0].example == "She said, \"stay strong\".", "引号转义应保留")
    let tsv = "单词\t释义\t音标\t例句\t例句翻译\nsubtle\t微妙的\tˈsʌtl\tA subtle change.\t微妙的变化。"
    try check(try WordImporter.parse(Data(tsv.utf8), filename: "test.tsv").first?.word == "subtle", "中文列名 TSV 应可导入")

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WordGapTests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WordStore(folder: folder, resource: Bundle.main.resourceURL, clock: { now })
    try check(store.books.count == 1 && store.selectedBook?.name == "进阶词库", "默认应加载统一进阶词库")
    try check(store.selectedBook?.words.count == 7758, "统一进阶词库应有 7,758 个词")
    let coreIDs = store.bookIDs
    try check(!coreIDs.contains("state") && !coreIDs.contains("system") && !coreIDs.contains("issue") && !coreIDs.contains("provide"), "常见基础词不得再次进入队列")
    try check(coreIDs.contains("consolidate") && coreIDs.contains("ubiquitous") && coreIDs.contains("formidable"), "高阶词应保留")
    guard let word = store.current else { throw TestFailure.failed("未选出当前单词") }
    store.rate(.knew, now: now)
    try check(store.saved.reviews[word.id] == nil, "释义尚未揭晓时不可误评分")
    store.revealed = true
    store.rate(.forgot, now: now)
    try check(store.saved.reviews[word.id]?.rating == .forgot && store.todayCount == 1, "评分应保存并计入当日唯一词数")
    store.undo()
    try check(store.current?.id == word.id && store.saved.reviews[word.id] == nil && store.todayCount == 0, "撤回必须还原评分和每日计数")
    store.revealed = true; store.rate(.knew, now: now)
    let restored = WordStore(folder: folder, resource: Bundle.main.resourceURL, clock: { now })
    try check(restored.saved.reviews[word.id]?.stage == 1 && restored.todayCount == 1, "退出重开应恢复学习进度")
    let before = restored.saved.reviews
    var rotating = Set<String>()
    for _ in 0..<30 {
        restored.next()
        if let id = restored.current?.id { rotating.insert(id) }
    }
    try check(rotating.count == 30, "未评分词条应持续轮换，不应在少数词中循环")
    try check(restored.saved.reviews == before, "自动轮换和跳过不得修改复习记录")
    restored.saved.settings.miniMode = true; restored.settingsChanged()
    let miniReload = WordStore(folder: folder, resource: Bundle.main.resourceURL, clock: { now })
    try check(miniReload.saved.settings.miniMode && miniReload.saved.reviews == before,
              "迷你模式必须跨重启保留且不改变学习记录")
    let oldPreferences = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
    try check(oldPreferences.miniMode && !oldPreferences.pinned, "默认卡片应为迷你模式，定位到菜单栏单词下方")
    try check(oldPreferences.wordOrder == .random, "旧设置升级后应默认随机出词")
    try check(oldPreferences.appearance == .system, "旧设置缺少外观字段时应跟随系统")
    restored.saved.settings.appearance = .dark; restored.saved.settings.autoSpeak = true
    let presentation = restored.presentationID
    restored.settingsChanged()
    try check(restored.presentationID == presentation, "修改设置不应产生新的单词展示，避免自动发音重复")
    let appearanceReload = WordStore(folder: folder, resource: Bundle.main.resourceURL, clock: { now })
    try check(appearanceReload.saved.settings.appearance == .dark && appearanceReload.saved.settings.autoSpeak && appearanceReload.saved.reviews == before,
              "外观与自动发音偏好应跨重启保存，并保留学习进度")
    restored.next()
    try check(restored.presentationID != presentation, "每次换词必须产生新的展示，支持自动朗读")
    var darkBrightness: CGFloat = 0, lightBrightness: CGFloat = 0
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
        if let color = AppPalette.nativeBackground.usingColorSpace(.deviceRGB) {
            darkBrightness = color.redComponent + color.greenComponent + color.blueComponent
        }
    }
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        if let color = AppPalette.nativeBackground.usingColorSpace(.deviceRGB) {
            lightBrightness = color.redComponent + color.greenComponent + color.blueComponent
        }
    }
    try check(darkBrightness < 1 && lightBrightness > 2.8, "背景颜色必须随原生深浅色外观切换")
    let visible = NSRect(x: 0, y: 50, width: 1440, height: 828)
    let anchor = NSRect(x: 1330, y: 878, width: 100, height: 22)
    var placement = MiniCardPlacement()
    try check(placement.origin(size: CardLayout.miniSize, below: .zero, visible: visible) == nil &&
              placement.origin(size: CardLayout.miniSize, below: NSRect(x: 0, y: 0, width: 100, height: 22), visible: visible) == nil,
              "首次启动的零坐标及底部假坐标不能被缓存成左下角位置")
    guard let origin = placement.origin(size: CardLayout.miniSize, below: anchor, visible: visible) else {
        throw TestFailure.failed("有效菜单栏坐标必须可以定位")
    }
    try check(origin.x + CardLayout.miniSize.width <= visible.maxX - 8 &&
              origin.y + CardLayout.miniSize.height == anchor.minY - 1,
              "迷你卡片应贴在菜单栏下方且不越过右屏幕边界")
    let secondary = NSRect(x: -1920, y: 30, width: 1920, height: 1026)
    let secondOrigin = CardLayout.origin(size: CardLayout.miniSize,
                                        below: NSRect(x: -1918, y: 1056, width: 70, height: 24), visible: secondary)
    try check(secondOrigin.x == secondary.minX + 8 && secondOrigin.y >= secondary.minY + 8,
              "副屏的迷你卡片必须使用该屏幕坐标")
    var settlingPlacement = MiniCardPlacement()
    let transientAnchor = NSRect(x: 1300, y: 878, width: 60, height: 22)
    let finalAnchor = NSRect(x: 1000, y: 878, width: 80, height: 22)
    try check(settlingPlacement.origin(size: CardLayout.miniSize, below: transientAnchor, visible: visible,
                                      settlingTime: 0.2, now: 100) == nil,
              "首次有效坐标仍可能在调整，不能立即锁到菜单栏错误位置")
    try check(settlingPlacement.origin(size: CardLayout.miniSize, below: finalAnchor, visible: visible,
                                      settlingTime: 0.2, now: 100.1) == nil &&
              settlingPlacement.origin(size: CardLayout.miniSize, below: finalAnchor, visible: visible,
                                      settlingTime: 0.2, now: 100.25) == nil,
              "菜单栏横向移动后必须重新等待稳定，不沿用过早的坐标")
    let settledOrigin = settlingPlacement.origin(size: CardLayout.miniSize, below: finalAnchor, visible: visible,
                                                 settlingTime: 0.2, now: 100.31)
    try check(settledOrigin == CardLayout.origin(size: CardLayout.miniSize, below: finalAnchor, visible: visible, gap: 1),
              "稳定后必须在最终菜单栏单词正下方定位，且保持1点间距")
    try check(settlingPlacement.origin(size: CardLayout.miniSize, below: transientAnchor, visible: visible,
                                      settlingTime: 0.2, now: 100.32) == settledOrigin,
              "首次位置锁定后，换词不能再等待或移动卡片")
    placement = MiniCardPlacement()
    let fixedOrigin = placement.origin(size: CardLayout.miniSize, below: anchor, visible: visible)
    for width in [CGFloat(35), 80, 160, 55] {
        let movedAnchor = NSRect(x: 1000, y: 878, width: width, height: 22)
        try check(placement.origin(size: CardLayout.miniSize, below: movedAnchor, visible: visible) == fixedOrigin,
                  "菜单栏词长变化及重新打开时，迷你卡片不能跟随移动")
    }
    guard let movedScreenOrigin = placement.origin(size: CardLayout.miniSize,
                                            below: NSRect(x: -300, y: 1056, width: 60, height: 24), visible: secondary) else {
        throw TestFailure.failed("新屏幕的有效菜单栏坐标必须可以定位")
    }
    try check(secondary.contains(NSRect(origin: movedScreenOrigin, size: CardLayout.miniSize)),
              "原屏幕不可用时才重新定位到可见区域")

    // Exercise the real hosting view offscreen; never activate a window or use real user data.
    let layoutStore = WordStore(folder: folder.appendingPathComponent("window-layout"), resource: Bundle.main.resourceURL, clock: { now })
    let longWord = String(repeating: "abcdefgh", count: 12)
    let longMeaning = String(repeating: "n. 这是一段较长的释义，用来检查窗口是否自动伸缩。\\n", count: 20)
    let layoutTSV = "word\tmeaning\tphonetic\nshort\tn. 短释义\tʃɔːt\n" + longWord + "\t" + longMeaning + "\t" + String(repeating: "fəˈnɛtɪk", count: 20) + "\nmediumlength\tv. 测试用单词\t"
    try layoutStore.importWords(data: Data(layoutTSV.utf8), filename: "layout.tsv")
    let testPanel = CardPanel(contentRect: NSRect(x: -10000, y: -10000, width: 244, height: 190),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    testPanel.isReleasedWhenClosed = false
    defer { testPanel.close() }
    var readingFrames: [[String: CGRect]] = []
    var latestReading: [String: CGRect] = [:]
    let host = glassCardHost(MiniCardView(store: layoutStore, speak: { _ in }, settings: {}, hide: {}, togglePin: {}, toggleMini: {},
                                        inspectLayout: { latestReading = $0 }))
    testPanel.contentView = host
    testPanel.setContentSize(CardLayout.miniSize)
    let stableFrame = testPanel.frame
    for _ in 0..<12 {
        layoutStore.next(); layoutStore.revealed.toggle()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        host.layoutSubtreeIfNeeded()
        try check(cardFeedbackHost(host).bounds.size == CardLayout.miniSize,
                  "玻璃外壳内的实际内容必须填满迷你卡片，不裁剪或增加留白")
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        try check(latestReading.count == 3 && latestReading.values.allSatisfy({ $0.width > 0 }),
                  "每次切词后都应保留单词行、发音按钮、释义三个完整布局区域")
        readingFrames.append(latestReading)
        try check(testPanel.frame == stableFrame, "长短词切换或释义展开不能改变窗口位置和尺寸")
    }
    try check(readingFrames.count >= 3, "必须取得实际单词行、发音按钮和释义区域的布局测量")
    let baselineReading = readingFrames.last!
    for frames in readingFrames.suffix(6) {
        for name in ["word", "speaker", "meaning"] {
            try check(frames[name]?.minY == baselineReading[name]?.minY && frames[name]?.height == baselineReading[name]?.height,
                      "阅读区域不得随长短音标及释义展开上下跳动：\(name)")
        }
        try check(frames["speaker"] == baselineReading["speaker"], "发音按钮不能随单词长短移动")
    }
    let settingsHost = glassCardHost(SettingsView(store: layoutStore, back: {}, importWords: {}, exportProgress: {}, manageMastered: {}, quit: {}))
    let statisticsHost = glassCardHost(StatisticsView(store: layoutStore, exportCSV: { _, _ in }))
    let originalGlassEnabled = GlassAppearanceState.shared.enabled, originalGlassIntensity = GlassAppearanceState.shared.intensity
    defer { GlassAppearanceState.shared.apply(enabled: originalGlassEnabled, intensity: originalGlassIntensity) }
    for (root, size) in [(settingsHost, CardLayout.settingsSize), (statisticsHost, NSSize(width: 900, height: 740))] {
        testPanel.contentView = root; testPanel.setContentSize(size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02)); root.layoutSubtreeIfNeeded()
        guard let glassHost = root as? LiquidCardHost else { throw TestFailure.failed("全部页面必须使用统一的液态玻璃容器") }
        if #available(macOS 26.0, *) {
            try check(glassHost.materialView is NSGlassEffectView, "设置和统计必须使用真实NSGlassEffectView")
        }
        let originalContent = glassHost.cardContentView, frame = testPanel.frame
        for amount in [0.0, 0.35, 1.0, 0.65] {
            GlassAppearanceState.shared.apply(enabled: true, intensity: amount)
            glassHost.apply(enabled: true, intensity: amount); root.layoutSubtreeIfNeeded()
            try check(root.bounds.size == size && originalContent.bounds.size == size && testPanel.frame == frame,
                      "调节玻璃程度不能改变窗口尺寸、位置或裁剪阅读内容")
            try check(glassHost.cardContentView === originalContent, "程度调节不能重建内容或丢失输入状态")
        }
        GlassAppearanceState.shared.apply(enabled: false, intensity: 0.65)
        glassHost.apply(enabled: false, intensity: 0.65); root.layoutSubtreeIfNeeded()
        try check(glassHost.materialView?.isHidden == true && originalContent.superview === root && originalContent.bounds.size == size,
                  "关闭效果后必须保留原内容与全部功能")
        GlassAppearanceState.shared.apply(enabled: true, intensity: 0.65)
        glassHost.apply(enabled: true, intensity: 0.65); root.layoutSubtreeIfNeeded()
        try check(glassHost.materialView?.isHidden == false && glassHost.cardContentView === originalContent && originalContent.bounds.size == size,
                  "重新开启必须恢复液态玻璃，并保留同一份内容和固定布局")
    }
    // Deep black glass must survive every slider value and a light/dark round trip.
    if #available(macOS 26.0, *), let darkHost = settingsHost as? LiquidCardHost,
       let nativeGlass = darkHost.materialView as? NSGlassEffectView {
        let originalAppearance = darkHost.appearance
        defer { darkHost.appearance = originalAppearance }
        darkHost.appearance = NSAppearance(named: .darkAqua)
        for amount in [0.0, 0.30, 0.65, 1.0] {
            GlassAppearanceState.shared.apply(enabled: true, intensity: amount)
            darkHost.apply(enabled: true, intensity: amount, force: true)
            try check(nativeGlass.tintColor == nil && nativeGlass.style == .clear,
                      "深色必须保留旧版无灰色染色的clear玻璃外壳")
            try check(GlassAppearanceState.shared.readingOpacity(dark: true) >= 0.82,
                      "最高通透度也不能让黑色阅读底面发白")
        }
        darkHost.appearance = NSAppearance(named: .aqua)
        darkHost.apply(enabled: true, intensity: 0.65, force: true)
        try check(nativeGlass.tintColor != nil, "浅色玻璃应保持现有染色")
        darkHost.appearance = NSAppearance(named: .darkAqua)
        darkHost.apply(enabled: true, intensity: 0.65, force: true)
        try check(nativeGlass.tintColor == nil, "切回深色必须去掉浅色染色")
        GlassAppearanceState.shared.apply(enabled: true, intensity: 0.65)
        try check(abs(GlassAppearanceState.shared.readingOpacity(dark: true) - 0.862) < 0.01 &&
                  abs(GlassAppearanceState.shared.readingOpacity(dark: false) - 0.33) < 0.01,
                  "深色保留旧版至少82%黑色底面，浅色保持原样")
        print("DARK_GLASS_TEST_OK: 旧版黑色玻璃底面、全程通透度、深浅色往返、浅色保持")
    }
    var glassSettings = Settings(); glassSettings.glassEnabled = false; glassSettings.glassIntensity = 0.35
    let glassEncoded = try JSONEncoder().encode(glassSettings)
    let glassDecoded = try JSONDecoder().decode(Settings.self, from: glassEncoded)
    try check(glassDecoded.glassEnabled == false && glassDecoded.glassIntensity == 0.35 && oldPreferences.glassEnabled,
              "玻璃开关和程度必须保存，旧配置缺少字段时应保持开启")
    print("GLASS_UI_TEST_OK: 全页面原生液态玻璃、程度变化与开关不丢内容、不改变位置、偏好保存")
    try check(restored.todayNewCount == 1 && restored.todayReviewCount == 0, "首次评分应只计入新学")
    restored.saved.settings.dailyNewGoal = 1; restored.settingsChanged()
    try check(restored.current == nil && restored.dailyProgress == 1, "达到每日新词目标应停止发新词")
    restored.setMode(.review)
    try check(restored.current == nil && restored.dueCount == 0, "未到期时复习不得混入新词或提前复习")
    restored.saved.settings.dailyNewGoal = 30; restored.setMode(.newWords)
    guard let basic = restored.current else { throw TestFailure.failed("没有基础词可排除") }
    restored.markMastered()
    try check(restored.saved.mastered.contains(basic.id) && restored.todayNewCount == 1, "标记已掌握不应占每日新词名额")
    try check(!restored.newWords.contains(where: { $0.id == basic.id }), "已掌握词必须退出新词队列")
    restored.undo()
    try check(!restored.saved.mastered.contains(basic.id) && restored.current?.id == basic.id, "已掌握操作必须可以撤回")
    restored.markMastered()
    let masteredReload = WordStore(folder: folder, resource: Bundle.main.resourceURL, clock: { now })
    try check(masteredReload.saved.mastered.contains(basic.id), "已掌握状态必须跨重启保留")
    restored.restoreMastered(basic.id)
    try check(restored.newWords.contains(where: { $0.id == basic.id }), "恢复已掌握词应重回新学队列")
    try check(try restored.importWords(data: Data(tsv.utf8), filename: "我的词表.tsv") == 1, "自建词库应可保存")
    let reloaded = WordStore(folder: folder, resource: Bundle.main.resourceURL, clock: { now })
    try check(reloaded.selectedBook?.name == "我的词表" && reloaded.current?.word == "subtle", "自建词库和选中状态应跨重启保留")
    let backup = folder.appendingPathComponent("export.json")
    try reloaded.export(to: backup)
    try check((try Data(contentsOf: backup)).count > 100, "导出文件应包含学习记录和自建词库")

    let travelFolder = folder.appendingPathComponent("travel")
    var travelTime = now
    let travel = WordStore(folder: travelFolder, resource: Bundle.main.resourceURL, clock: { travelTime })
    let reviewWord = travel.current!
    travel.revealed = true; travel.rate(.forgot)
    travel.setMode(.review)
    try check(travel.current == nil && travel.todayReviewGoal == 1, "十分钟后的新词复习应进入今日计划，但不能提前展示")
    travelTime = now.addingTimeInterval(601); travel.next()
    try check(travel.current?.id == reviewWord.id && travel.todayNewCount == 1, "到期复习只能展示对应的已学词")
    travel.revealed = true; travel.rate(.forgot)
    try check(travel.todayReviewCount == 1 && travel.todayReviewGoal == 1 && travel.dueCount == 0,
              "不认识也算复习过一个不同词；再次复习任务不会重复增加今日计划词数")
    travelTime = now.addingTimeInterval(1200); travel.next()
    try check(travel.current == nil, "复习不认识后的9分59秒不能提前出词")
    travelTime = now.addingTimeInterval(1201); travel.next()
    try check(travel.current?.id == reviewWord.id && travel.dueCount == 1 && travel.todayReviewCount == 1 && travel.todayReviewGoal == 1,
              "不认识后的10分钟必须重新到期，复习过的计数仍按不同词去重")
    travel.revealed = true; travel.rate(.knew)
    try check(travel.todayReviewCount == 1 && travel.todayNewCount == 1 && travel.todayCount == 1, "同一个词的新学和复习应分别计数，总词数不能重复")
    try check(travel.saved.studyEvents.filter { $0.kind == .rated && $0.mode == .review }.count == 2,
              "同词复习不认识再认识，复习词数不重复，但评分次数累计两次")
    try check(travel.dailyProgress == 1 && travel.current == nil, "完成到期复习后应结束队列并显示完成进度")
    travelTime = now.addingTimeInterval(2 * 86400); travel.refreshDay()
    try check(travel.todayNewCount == 0 && travel.todayReviewCount == 0 && travel.dueCount == 1, "跨日必须刷新每日统计并保留到期复习")
    travel.markMastered()
    try check(travel.dueCount == 0 && travel.current == nil, "已掌握词必须退出到期复习队列")

    let migrationFolder = folder.appendingPathComponent("migration")
    try FileManager.default.createDirectory(at: migrationFolder, withIntermediateDirectories: true)
    var legacy = SavedData(); legacy.version = 1
    legacy.reviews[reviewWord.id] = first; legacy.dailyWords[WordStore.dateKey(now)] = [reviewWord.id]
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    var object = try JSONSerialization.jsonObject(with: encoder.encode(legacy)) as! [String: Any]
    for key in ["dailyNewWords", "dailyReviewWords", "mastered", "reviewPlans"] { object.removeValue(forKey: key) }
    var oldSettings = object["settings"] as! [String: Any]
    oldSettings.removeValue(forKey: "mode"); oldSettings.removeValue(forKey: "dailyNewGoal"); object["settings"] = oldSettings
    try JSONSerialization.data(withJSONObject: object).write(to: migrationFolder.appendingPathComponent("progress.json"))
    let migrated = WordStore(folder: migrationFolder, resource: Bundle.main.resourceURL, clock: { now })
    try check(migrated.saved.version == 3 && migrated.saved.reviews[reviewWord.id] == first, "旧版学习记录必须完整迁移")
    try check(migrated.todayNewCount == 1 && migrated.saved.settings.dailyNewGoal == 30, "旧版今日学习量必须保留并补齐默认目标")
    try check(FileManager.default.fileExists(atPath: migrationFolder.appendingPathComponent("progress.backup.json").path), "迁移必须保留旧版记录备份")
    for (key, rating) in [(UInt16(18), Rating.forgot), (19, .vague), (20, .knew), (83, .forgot), (84, .vague), (85, .knew)] {
        try check(CardShortcut.action(for: key) == .rate(rating), "数字与小键盘快捷键应按按钮对应评分")
    }
    try check(CardShortcut.action(for: 21) == .mastered && CardShortcut.action(for: 49) == .reveal, "4 应标记已掌握，空格应揭晓释义")

    let novelty = EnglishVoice(identifier: "com.apple.speech.synthesis.voice.Albert", locale: "en_US")
    let bahh = EnglishVoice(identifier: "com.apple.speech.synthesis.voice.Bahh", locale: "en_US")
    let robotic = EnglishVoice(identifier: "com.apple.eloquence.en-US.Eddy", locale: "en_US")
    let us = EnglishVoice(identifier: "com.apple.voice.compact.en-US.Samantha", locale: "en_US")
    let uk = EnglishVoice(identifier: "com.apple.voice.compact.en-GB.Daniel", locale: "en_GB")
    let enhanced = EnglishVoice(identifier: "com.apple.voice.enhanced.en-US.Samantha", locale: "en-US")
    let voices = [novelty, bahh, robotic, uk, us]
    try check(EnglishVoice.select(from: voices, british: false)?.identifier == us.identifier, "美音应选 Samantha，不能误选排在最前的搞怪声音")
    try check(EnglishVoice.select(from: voices.reversed(), british: true)?.identifier == uk.identifier, "英音应选 Daniel，不受系统列表顺序影响")
    try check(EnglishVoice.select(from: voices + [enhanced], british: false)?.identifier == enhanced.identifier, "同口音优先使用增强语音，兼容横线格式语言代码")
    try check(EnglishVoice.select(from: [novelty, bahh, robotic], british: false) == nil, "没有正常语音时不能退回音效或机器语音")
    try check(EnglishVoice.select(from: [bahh, uk], british: false)?.identifier == uk.identifier, "缺少美音时应使用正常英音而非音效")
    for british in [false, true] {
        if let installed = EnglishVoice.installed(british: british) {
            try check(EnglishVoice(identifier: installed.rawValue, locale: "en").isNatural, "本机所选发音必须是正常英语语音")
            print("VOICE_OK: \(british ? "英音" : "美音") \(installed.rawValue)")
        }
    }

    var randomTime = now
    let randomFolder = folder.appendingPathComponent("random-order")
    let randomStore = WordStore(folder: randomFolder, resource: Bundle.main.resourceURL, clock: { randomTime }, randomIndex: { $0 - 1 })
    try randomStore.importWords(data: Data("word\tmeaning\nalpha\t甲\nbeta\t乙\ngamma\t丙".utf8), filename: "random.tsv")
    try check(randomStore.current?.id == "gamma", "随机选择应使用抽签结果，而不是总取字母最前的词")
    var randomIDs = Set<String>()
    for _ in 0..<3 { randomIDs.insert(randomStore.current!.id); randomStore.next() }
    try check(randomIDs == ["alpha", "beta", "gamma"], "随机一轮内不应重复展示已看过的词")
    randomStore.saved.mastered.insert("gamma"); randomStore.next()
    for _ in 0..<6 {
        try check(randomStore.current?.id != "gamma", "随机出词必须排除已掌握词")
        randomStore.next()
    }
    randomStore.revealed = true; let dueID = randomStore.current!.id; randomStore.rate(.forgot)
    randomStore.setMode(.review)
    try check(randomStore.current == nil, "随机复习不应混入未到期词或新词")
    randomTime = now.addingTimeInterval(601); randomStore.next()
    try check(randomStore.current?.id == dueID, "随机复习只应抽取已到期词")
    randomStore.setMode(.newWords); randomStore.restoreMastered("gamma"); randomStore.setWordOrder(.alphabetical)
    try check(randomStore.current?.id == "alpha", "用户应能切回字母顺序")
    let orderReload = WordStore(folder: randomFolder, resource: Bundle.main.resourceURL, clock: { randomTime })
    try check(orderReload.saved.settings.wordOrder == .alphabetical, "出词顺序必须跨重启保存")
    try runStatisticsTests(folder: folder, resource: Bundle.main.resourceURL)
    try runFeedbackTests(folder: folder, resource: Bundle.main.resourceURL)
    print("PASS: 学习统计、正常英语发音选择、单词/音标/释义固定布局、菜单栏下方默认位置、随机顺序/不重复/掌握排除/到期复习/顺序保存、迷你窗口固定、旧记录迁移、每日计划、掌握撤回、快捷键、导入导出")
}
