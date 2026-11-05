import Foundation

func runStatisticsTests(folder: URL, resource: URL?) throws {
    func check(_ value: @autoclosure () -> Bool, _ reason: String) throws {
        if !value() { throw TestFailure.failed(reason) }
    }
    var time = StudyStatistics.date("2026-10-13")!.addingTimeInterval(9 * 3600)
    let start = time
    let store = WordStore(folder: folder.appendingPathComponent("detailed-statistics"), resource: resource, clock: { time })
    try store.importWords(data: Data("word\tmeaning\nalpha\t测试单词".utf8), filename: "statistics.tsv")
    let word = store.current!
    store.startStudyTiming()
    time = time.addingTimeInterval(1); store.tickStudyTime(isActive: true)
    store.revealMeaning(); store.rate(.forgot)
    try check(store.saved.studyEvents.filter { $0.kind == .rated }.count == 1, "新学必须记录一次真实评分")
    try check(store.statistics().totals(.week).medianRecall == 1, "揭晓用时应使用前台专注时间")
    try check(store.statistics(bookID: store.saved.settings.bookID).day(start).newGoal == 1 && store.statistics(bookID: store.saved.settings.bookID).day(start).goalMet,
              "词库剩余不足目标时，应记录实际可完成的新词目标")
    store.pauseStudyTiming()
    store.setMode(.review)
    time = time.addingTimeInterval(601); store.next()
    store.revealMeaning(); store.rate(.forgot)
    time = time.addingTimeInterval(601); store.next()
    store.startStudyTiming()
    time = time.addingTimeInterval(1); store.tickStudyTime(isActive: true)
    store.revealMeaning(); store.rate(.knew)
    let day = store.statistics().day(start), totals = store.statistics().totals(.week)
    try check(day.newCount == 1 && day.reviewCount == 1 && day.uniqueCount == 1 && day.attempts == 3,
              "当天同词新学后复习两次：新学1、复习1、不同词1、评分3，不能混淆词数与次数")
    try check(store.statistics(bookID: store.saved.settings.bookID).day(start).reviewGoalMet, "同词多次到期，复习目标也应按不同词计算达标")
    try check(store.statistics().day(start).newGoal == nil, "多个词库的全局目标不能把缺失的旧目标和不同词库新词量拼成虚假完成率")
    try check(totals.reviewAttempts == 2 && totals.reviewRecognitionRate == 0.5, "复习认识率只能使用复习评分作分母")
    try check(abs(totals.recognitionRate! - 1.0 / 3.0) < 0.0001, "总认识率必须使用全部有效评分")
    store.current = word
    store.recordPronunciation()
    time = time.addingTimeInterval(1); store.tickStudyTime(isActive: true)
    store.pauseStudyTiming()
    let seconds = store.statistics().totals(.week).seconds
    store.undo()
    try check(store.statistics().totals(.week).attempts == 2 && store.statistics().totals(.week).seconds == seconds,
              "撤回应移除对应评分，保留已发生的专注时间")
    try check(store.saved.studyEvents.contains { $0.kind == .pronounced }, "撤回评分不能删除后续发音操作")
    store.markMastered()
    try check(store.statistics().day(start).newCount == 1 && store.statistics().day(start).reviewCount == 1,
              "标记掌握不能减少真实历史学习和复习量")
    store.undo()
    try check(!store.saved.studyEvents.contains { $0.kind == .mastered }, "撤回掌握不能遗留掌握统计")

    let longAgo = WordStore.dateKey(StudyStatistics.calendar.date(byAdding: .day, value: -220, to: start)!)
    store.saved.dailyWords[longAgo] = [word.id]; store.saved.dailyNewWords[longAgo] = [word.id]
    store.revealed = true; store.rate(.knew)
    let reload = WordStore(folder: folder.appendingPathComponent("detailed-statistics"), resource: resource, clock: { time })
    try check(reload.saved.dailyWords[longAgo] == [word.id], "详细记录升级后不能再删除180天以前的日统计")
    try check(reload.saved.studyEvents.count == store.saved.studyEvents.count && reload.saved.studySessions.count == store.saved.studySessions.count,
              "操作明细和专注片段必须退出后仍可恢复")

    var midnight = StudyStatistics.date("2026-10-13")!.addingTimeInterval(86400 - 1)
    let timing = WordStore(folder: folder.appendingPathComponent("timing"), resource: resource, clock: { midnight })
    timing.startStudyTiming()
    midnight = midnight.addingTimeInterval(1); timing.tickStudyTime(isActive: true)
    midnight = midnight.addingTimeInterval(1); timing.tickStudyTime(isActive: true)
    timing.pauseStudyTiming()
    try check(timing.statistics().day(StudyStatistics.date("2026-10-13")!).seconds == 1 &&
              timing.statistics().day(StudyStatistics.date("2026-10-14")!).seconds == 1,
              "跨午夜必须把时间分到两天，不丢失边界前的一秒")
    timing.startStudyTiming()
    midnight = midnight.addingTimeInterval(1); timing.tickStudyTime(isActive: true)
    midnight = midnight.addingTimeInterval(60); timing.tickStudyTime(isActive: true)
    timing.pauseStudyTiming()
    try check(timing.statistics().totals(.week).seconds == 3, "休眠或定时器停顿不能累计虚假学习时间")
    timing.startStudyTiming()
    for _ in 0..<95 { midnight = midnight.addingTimeInterval(1); timing.tickStudyTime(isActive: true) }
    timing.pauseStudyTiming()
    try check(timing.statistics().totals(.week).seconds == 93, "90秒无交互后必须停止计时")
    let idleSeconds = timing.statistics().totals(.week).seconds
    for _ in 0..<3 { midnight = midnight.addingTimeInterval(1); timing.tickStudyTime(isActive: false) }
    try check(timing.statistics().totals(.week).seconds == idleSeconds, "卡片不在前台时不能记时")

    var fixture = SavedData(); fixture.statisticsSince = start
    let dates = ["2026-10-05": 2, "2026-10-06": 3, "2026-10-07": 100, "2026-10-12": 1, "2026-10-13": 2]
    for (day, count) in dates {
        let ids = (0..<count).map { "word\($0)" }
        fixture.dailyWords[day] = ids; fixture.dailyNewWords[day] = ids
    }
    let fixtureWords = (0..<100).map { index -> Word in
        var entry = word; entry.id = "word\(index)"; entry.word = entry.id; return entry
    }
    let fixtureBook = Book(id: "weekly-fixture", name: "周统计测试", words: fixtureWords, isCustom: true)
    let stats = StudyStatistics(saved: fixture, books: [fixtureBook], bookID: nil, now: start)
    try check(stats.thisWeek.newCount == 3 && stats.lastWeekSameDays.newCount == 5 && stats.lastWeekSameDays.days.count == 2,
              "周二不能拿本周两天与上周七天比较，必须比较同样天数")
    try check(stats.currentStreak == 2 && stats.longestStreak == 3, "连续学习与历史最长必须按自然日准确计算")
    try check(stats.days(.week).count == 7 && stats.days(.week).contains { !$0.active }, "每日趋势必须保留没有学习的零值日期")
    try check(WordStore.dateKey(stats.weekStart(StudyStatistics.date("2027-01-01")!)) == "2026-12-28",
              "跨年周必须从正确的周一开始")
    try check(stats.totals(.all).attempts == 0 && stats.totals(.all).recognitionRate == nil,
              "不能从旧版词数猜出评分次数或认识率")
    try check(!stats.day(StudyStatistics.date("2026-10-12")!).hasDetails, "升级前时长和评分应标为无明细")
    try check(stats.dailyCSV(.week).hasPrefix("\u{FEFF}"), "中文CSV应带UTF8 BOM")
    let rows = WordImporter.rows(stats.dailyCSV(.week), delimiter: ",")
    try check(rows.count == 8 && rows.allSatisfy { $0.count == 19 }, "每日CSV列数要一致并覆盖7个自然日")
    let exportRows = WordImporter.rows(store.statistics().eventsCSV(.all), delimiter: ",")
    try check(exportRows.count == store.saved.studyEvents.count + 1 && exportRows.allSatisfy { $0.count == 14 },
              "明细导出不能受页面200条显示限制，必须含全部字段")
    let sessionRows = WordImporter.rows(store.statistics().sessionsCSV(.all), delimiter: ",")
    try check(sessionRows.count == store.statistics().sessions(.all).count + 1 && sessionRows.allSatisfy { $0.count == 14 },
              "专注片段CSV必须完整包含时长、词库与评分明细汇总")
    let escaped = StudyStatistics.csvRows([["=SUM(1,2)", "a\"b", "多行\n内容"]])
    try check(escaped.contains("'=SUM(1,2)") && escaped.contains("a\"\"b"), "CSV必须转义引号并防止单词被当作公式")

    let legacyFolder = folder.appendingPathComponent("statistics-migration")
    try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
    fixture.version = 2
    fixture.settings.british = true; fixture.settings.miniMode = true
    fixture.mastered.insert("preserved")
    fixture.reviews[word.id] = Review.applying(.forgot, previous: nil, now: start)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    var json = try JSONSerialization.jsonObject(with: encoder.encode(fixture)) as! [String: Any]
    for key in ["statisticsSince", "studyEvents", "studySessions", "newGoalHistory", "reviewGoalHistory"] { json.removeValue(forKey: key) }
    try JSONSerialization.data(withJSONObject: json).write(to: legacyFolder.appendingPathComponent("progress.json"))
    let migrated = WordStore(folder: legacyFolder, resource: resource, clock: { start })
    try check(migrated.saved.version == 3 && migrated.saved.dailyWords == fixture.dailyWords && migrated.saved.mastered == fixture.mastered &&
              migrated.saved.reviews == fixture.reviews && migrated.saved.settings.british && migrated.saved.settings.miniMode,
              "2.0升级必须保留所有旧日统计、掌握、复习和显示设置")
    try check(migrated.saved.studyEvents.isEmpty && migrated.saved.statisticsSince == start, "旧记录只补齐起始时间，不能伪造逐次事件")

    let libraryFolder = folder.appendingPathComponent("library-lifecycle")
    let library = WordStore(folder: libraryFolder, resource: resource, clock: { start })
    try library.importWords(data: Data("word\tmeaning\nalpha\t测试词".utf8), filename: "library.tsv")
    let importedID = library.saved.settings.bookID
    library.revealMeaning(); library.rate(.forgot)
    let learnedBefore = library.saved.reviews, historyBefore = library.saved.dailyWords
    let eventCount = library.saved.studyEvents.count
    library.deleteBook(importedID)
    try check(library.books.allSatisfy { $0.id != importedID } && library.selectedBook?.id == "advanced",
              "删除当前导入词库后，应从队列移除并切换到剩余词库")
    try check(library.saved.reviews == learnedBefore && library.saved.dailyWords == historyBefore && library.saved.studyEvents.count == eventCount,
              "删除词库不能删除复习、日记录或操作明细")
    try check(library.statistics(bookID: importedID).scopedIDs.isEmpty && library.statistics().day(start).newCount == 0 &&
              library.statistics().events.isEmpty &&
              library.statistics().day(start).newGoal == library.saved.newGoalHistory[WordStore.dateKey(start) + "|advanced"],
              "已删除词库不应出现在统计汇总、明细或目标中")
    library.deleteBook("advanced")
    try check(library.books.isEmpty && library.current == nil && library.emptyTitle == "还没有可用词库",
              "删除最后一个词库应正确进入空状态，不再自动加载内置词库")
    let libraryReload = WordStore(folder: libraryFolder, resource: resource, clock: { start })
    try check(libraryReload.books.isEmpty && libraryReload.archivedBooks.count == 2, "删除状态必须在重启后仍保留")
    libraryReload.restoreBook(importedID)
    try check(libraryReload.selectedBook?.id == importedID && libraryReload.saved.reviews == learnedBefore,
              "恢复已删除导入词库后，必须恢复原有学习进度")
    try check(libraryReload.statistics().day(start).newCount == 1 && libraryReload.statistics().events.count == eventCount,
              "恢复词库后应重新显示保留的历史统计")
    libraryReload.restoreBook("advanced")
    try check(libraryReload.books.count == 2 && libraryReload.archivedBooks.isEmpty,
              "内置词库也应该可以删除和恢复，不改动应用资源文件")
    print("LIBRARY_TEST_OK: 删除导入/内置词库、切换、最后一个词库空状态、重启、恢复、保留学习统计、排程排除")
    print("STATISTICS_TEST_OK: 去重/次数/认识率、掌握与撤回、时长保留、跨午夜/休眠/空闲/后台、同进度周对比、连续天数、长期保存、CSV、旧记录迁移")
}
