import Foundation
import Combine

final class WordStore: ObservableObject {
    @Published var saved = SavedData()
    @Published var books: [Book] = []
    @Published var allBooks: [Book] = []
    @Published var current: Word?
    @Published var revealed = false
    @Published var notice = ""
    @Published var fileError = ""
    private let folder: URL
    private let resource: URL
    private let clock: () -> Date
    private let randomIndex: (Int) -> Int
    private var lastUndo: (word: Word, snapshot: SavedData, eventID: UUID)?
    private var visited = Set<String>()
    private var observedDay = ""
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastTick: Date?
    private var wasTracking = false
    private var lastInteraction: Date?
    private var focusSession: StudySession?
    private var lastTimeSave: Date?
    private var wordFocusSeconds: Double = 0
    private var recallSeconds: Double?
    private var didReveal = false
    private var deferredQuickTasks = Set<UUID>()
    var onWordChanged: (() -> Void)?
    var onAnswerFeedback: ((AnswerFeedback) -> Void)?
    private(set) var presentationID = UUID()

    init(folder: URL? = nil, resource: URL? = nil, clock: @escaping () -> Date = { Date() }, randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WordGap")
        self.resource = resource ?? Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        self.clock = clock
        self.randomIndex = randomIndex
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        load(); loadBooks()
        if !books.contains(where: { $0.id == saved.settings.bookID }), let first = books.first { saved.settings.bookID = first.id }
        migrateLegacyData()
        observedDay = todayKey
        next()
    }

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    var todayKey: String { Self.dateKey(clock()) }
    var selectedBook: Book? { books.first { $0.id == saved.settings.bookID } }
    var bookIDs: Set<String> { Set(selectedBook?.words.map(\.id) ?? []) }
    var mode: StudyMode { saved.settings.mode }
    var todayCount: Int { Set(saved.dailyWords[todayKey] ?? []).count }
    var todayNewCount: Int { Set(saved.dailyNewWords[todayKey] ?? []).intersection(bookIDs).count }
    var todayReviewCount: Int { Set(saved.dailyReviewWords[todayKey] ?? []).intersection(bookIDs).subtracting(saved.mastered).count }
    var masteredCount: Int { saved.mastered.intersection(bookIDs).count }
    var learnedCount: Int { Set(saved.reviews.keys).intersection(bookIDs).subtracting(saved.mastered).count }
    var processedCount: Int { learnedCount + masteredCount }
    var newWords: [Word] { (selectedBook?.words ?? []).filter { saved.reviews[$0.id] == nil && !saved.mastered.contains($0.id) } }
    var pendingQuickTasks: [QuickStudyTask] { saved.quickStudyTasks.filter { $0.completedAt == nil && $0.bookID == saved.settings.bookID && bookIDs.contains($0.wordID) } }
    var currentQuickTask: QuickStudyTask? { pendingQuickTasks.first { $0.wordID == current?.id } }
    var effectiveNewGoal: Int {
        let base = min(saved.settings.dailyNewGoal, todayNewCount + newWords.count)
        let todayIDs = Set(saved.dailyNewWords[todayKey] ?? [])
        let pending = Set(pendingQuickTasks.map(\.wordID)).subtracting(todayIDs).count
        let completed = saved.quickStudyTasks.contains { $0.bookID == saved.settings.bookID && $0.completedAt.map(Self.dateKey) == todayKey }
        return max(base, pending > 0 || completed ? todayNewCount + pending : 0)
    }
    var todayPendingNewCount: Int {
        let queued = Set(pendingQuickTasks.map(\.wordID))
        let countedToday = Set(saved.dailyNewWords[todayKey] ?? [])
        let uncountedQuickWords = queued.subtracting(countedToday).count
        let slots = max(0, saved.settings.dailyNewGoal - todayNewCount - uncountedQuickWords)
        let available = newWords.filter { !queued.contains($0.id) }.count
        return queued.count + min(slots, available)
    }
    var todayNewSummary: String { "今日待新学 \(todayPendingNewCount)" }
    var newCountHelp: String {
        "今天还需主动学习的词数，包含快捷加词待学任务。今日已新学 \(todayNewCount) 个；设置目标 \(saved.settings.dailyNewGoal) 个；快捷加词待学 \(pendingQuickTasks.count) 个。额外加词可超出目标；词库不足时按实际可学数量安排。揭晓并按1／2／3评分后才完成，跳过不算完成。"
    }
    var newStudyProgress: Double {
        let remaining = todayPendingNewCount
        let target = max(effectiveNewGoal, todayNewCount + remaining)
        return target == 0 ? 1 : Double(target - remaining) / Double(target)
    }
    var dueWords: [Word] {
        (selectedBook?.words ?? []).filter {
            !saved.mastered.contains($0.id) && (saved.reviews[$0.id]?.due ?? .distantFuture) <= clock()
        }.sorted { saved.reviews[$0.id]!.due < saved.reviews[$1.id]!.due }
    }
    var dueCount: Int { dueWords.count }
    var todayPendingReviewCount: Int {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock()))!
        return (selectedBook?.words ?? []).filter {
            !saved.mastered.contains($0.id) && (saved.reviews[$0.id]?.due ?? .distantFuture) < tomorrow
        }.count
    }
    var todayReviewSummary: String { "今日待复习 \(todayPendingReviewCount)" }
    private var planKey: String { todayKey + "|" + saved.settings.bookID }
    var todayReviewGoal: Int {
        Set(saved.reviewPlans[planKey] ?? []).intersection(bookIDs).subtracting(saved.mastered).count
    }
    var dailyProgress: Double {
        if mode == .newWords {
            return newStudyProgress
        }
        let remaining = todayPendingReviewCount
        let target = max(todayReviewGoal, remaining)
        return target == 0 ? 1 : Double(target - remaining) / Double(target)
    }
    var canUndo: Bool { lastUndo != nil }
    var masteredWords: [Word] {
        (selectedBook?.words ?? []).filter { saved.mastered.contains($0.id) }.sorted { $0.word < $1.word }
    }
    var archivedBooks: [Book] { allBooks.filter { saved.archivedBookDates[$0.id] != nil } }
    var emptyTitle: String {
        if mode == .newWords && !pendingQuickTasks.isEmpty { return "加词仍待学习" }
        if selectedBook == nil { return "还没有可用词库" }
        if mode == .newWords {
            return newWords.isEmpty ? "这个词库的新词已学完" : "今天的新词目标已完成"
        }
        return "当前没有到期的复习词"
    }
    var emptyDetail: String {
        if mode == .newWords && !pendingQuickTasks.isEmpty { return "暂时跳过不会算学完。按 ⌘K 重新打开，优先学这些词。" }
        if selectedBook == nil { return "打开偏好设置，导入新词库或恢复已删除词库。" }
        if mode == .newWords { return "今天已新学 \(todayNewCount) 词，可切换到复习。" }
        if let date = (selectedBook?.words ?? []).filter({ !saved.mastered.contains($0.id) })
            .compactMap({ saved.reviews[$0.id]?.due }).filter({ $0 > clock() }).min() {
            let formatter = DateFormatter(); formatter.dateFormat = "M月d日 HH:mm"
            return "下次复习：" + formatter.string(from: date)
        }
        return "新学并评分后，单词会按间隔进入复习。"
    }

    private func load() {
        let url = folder.appendingPathComponent("progress.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { saved = try decoder.decode(SavedData.self, from: Data(contentsOf: url)) }
        catch {
            let preserved = folder.appendingPathComponent("progress-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: preserved)
            if let data = try? Data(contentsOf: folder.appendingPathComponent("progress.backup.json")),
               let recovered = try? decoder.decode(SavedData.self, from: data) {
                saved = recovered; fileError = "已从备份恢复学习记录。"
            } else { fileError = "学习记录无法读取，原文件已保留。请先备份后再继续。" }
        }
    }

    private func migrateLegacyData() {
        var changed = false
        if saved.version < 2 {
            var firstDay: [String: String] = [:]
            for day in saved.dailyWords.keys.sorted() {
                for id in saved.dailyWords[day] ?? [] where firstDay[id] == nil { firstDay[id] = day }
            }
            for (day, ids) in saved.dailyWords {
                saved.dailyNewWords[day] = ids.filter { firstDay[$0] == day }
                saved.dailyReviewWords[day] = ids.filter { firstDay[$0] != day }
            }
            changed = true
        }
        if saved.statisticsSince == nil { saved.statisticsSince = clock(); changed = true }
        if saved.version < 3 { saved.version = 3; changed = true }
        if changed { persist() }
    }

    private func loadBooks() {
        let titles = [("advanced", "进阶词库")]
        allBooks = titles.compactMap { id, name in
            guard let data = try? Data(contentsOf: resource.appendingPathComponent(id + ".json")),
                  let words = try? decoder.decode([Word].self, from: data), !words.isEmpty else { return nil }
            return Book(id: id, name: name, words: words, isCustom: false)
        } + saved.customBooks
        allBooks = allBooks.map { book in
            var result = book
            let ids = Set(book.words.map { QuickWordInput.normalized($0.word) })
            result.words += (saved.quickWords[book.id] ?? []).filter { !ids.contains(QuickWordInput.normalized($0.word)) }
            return result
        }
        books = allBooks.filter { saved.archivedBookDates[$0.id] == nil }
        if allBooks.isEmpty { fileError = "没有找到词库文件。请重新打开完整的词隙.app。" }
    }

    @discardableResult func persist() -> Bool {
        commitStudyTime()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("progress.json")
            if let previous = try? Data(contentsOf: url), (try? decoder.decode(SavedData.self, from: previous)) != nil {
                try previous.write(to: folder.appendingPathComponent("progress.backup.json"), options: .atomic)
            }
            try encoder.encode(saved).write(to: url, options: .atomic)
            fileError = ""; return true
        } catch { fileError = "记录保存失败：" + error.localizedDescription; return false }
    }

    private func updateReviewPlan() {
        guard selectedBook != nil else { return }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock()))!
        var plan = Set(saved.reviewPlans[planKey] ?? [])
        plan.formUnion((selectedBook?.words ?? []).filter {
            !saved.mastered.contains($0.id) &&
            (saved.reviews[$0.id]?.due ?? .distantFuture) < tomorrow
        }.map(\.id))
        plan.formUnion(Set(saved.dailyReviewWords[todayKey] ?? []).intersection(bookIDs))
        saved.reviewPlans[planKey] = plan.sorted()
        saved.newGoalHistory[planKey] = effectiveNewGoal
        saved.reviewGoalHistory[planKey] = todayReviewGoal
    }

    func refreshDay() {
        guard observedDay != todayKey else { return }
        observedDay = todayKey; visited = []; lastUndo = nil; notice = "新的一天，学习进度已刷新"
        next(); persist()
    }

    func selectBook(_ id: String) {
        saved.settings.bookID = id; visited = []; lastUndo = nil
        next(); persist()
    }
    func setMode(_ value: StudyMode) {
        guard mode != value else { return }
        saved.settings.mode = value; visited = []; lastUndo = nil; notice = "已切换到" + value.label
        next(); persist()
    }
    func setWordOrder(_ value: WordOrder) {
        guard saved.settings.wordOrder != value else { return }
        saved.settings.wordOrder = value; visited = []; lastUndo = nil
        next(); persist(); notice = "已切换到" + value.label
    }
    func settingsChanged() {
        saved.settings.dailyNewGoal = min(500, max(1, saved.settings.dailyNewGoal))
        saved.newGoalHistory[planKey] = effectiveNewGoal
        let blocked = mode == .newWords && todayNewCount >= saved.settings.dailyNewGoal
        if blocked && currentQuickTask == nil || current == nil { next() }
        persist(); onWordChanged?()
    }

    func next(now: Date? = nil) {
        updateReviewPlan()
        let time = now ?? clock()
        if mode == .newWords, let task = pendingQuickTasks.first(where: { !deferredQuickTasks.contains($0.id) }),
           let word = selectedBook?.words.first(where: { $0.id == task.wordID }) {
            presentQuickWord(word); return
        }
        let pool: [Word]
        if mode == .newWords {
            let queued = Set(pendingQuickTasks.map(\.wordID))
            pool = todayNewCount < saved.settings.dailyNewGoal ? newWords.filter { !queued.contains($0.id) } : []
        } else {
            pool = (selectedBook?.words ?? []).filter {
                !saved.mastered.contains($0.id) && (saved.reviews[$0.id]?.due ?? .distantFuture) <= time
            }.sorted { saved.reviews[$0.id]!.due < saved.reviews[$1.id]!.due }
        }
        var remaining = pool.filter { !visited.contains($0.id) }
        if remaining.isEmpty && !pool.isEmpty {
            visited = []; remaining = pool.filter { $0.id != current?.id }
            if remaining.isEmpty { remaining = pool }
        }
        if remaining.isEmpty { current = nil }
        else if saved.settings.wordOrder == .random {
            current = remaining[min(remaining.count - 1, max(0, randomIndex(remaining.count)))]
        } else {
            current = remaining.min { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        }
        revealed = false
        wordFocusSeconds = 0; recallSeconds = nil; didReveal = false
        if let current { visited.insert(current.id) }
        presentationID = UUID()
        onWordChanged?()
    }

    func rate(_ rating: Rating, now: Date? = nil) {
        guard let word = current, revealed, currentQuickTask != nil || !saved.mastered.contains(word.id) else { return }
        commitStudyTime()
        let time = now ?? clock(), day = Self.dateKey(time), old = saved
        let quickTask = currentQuickTask
        let isNew = quickTask != nil || saved.reviews[word.id] == nil
        let goal = effectiveNewGoal
        let eventID = UUID()
        lastUndo = (word, old, eventID)
        let previous = saved.reviews[word.id]
        if let quickTask, let index = saved.quickStudyTasks.firstIndex(where: { $0.id == quickTask.id }) {
            saved.quickStudyTasks[index].completedAt = time; saved.mastered.remove(word.id)
        }
        saved.reviews[word.id] = Review.applying(rating, previous: quickTask == nil ? saved.reviews[word.id] : nil, now: time)
        if quickTask != nil { saved.reviews[word.id]?.count = (previous?.count ?? 0) + 1 }
        recordEvent(.rated, word: word, at: time, id: eventID, mode: isNew ? .newWords : .review,
                    rating: rating, previous: previous, result: saved.reviews[word.id])
        saved.newGoalHistory[day + "|" + saved.settings.bookID] = goal
        func adding(_ id: String, to values: [String]?) -> [String] { Array(Set((values ?? []) + [id])).sorted() }
        saved.dailyWords[day] = adding(word.id, to: saved.dailyWords[day])
        if isNew { saved.dailyNewWords[day] = adding(word.id, to: saved.dailyNewWords[day]) }
        else { saved.dailyReviewWords[day] = adding(word.id, to: saved.dailyReviewWords[day]) }
        updateReviewPlan()
        guard persist() else { saved = old; lastUndo = nil; return }
        switch rating {
        case .forgot: notice = "已加入复习，10 分钟后再见"
        case .vague: notice = "已标记模糊，30 分钟后再复习"
        case .knew:
            notice = "已记住，\(Int(saved.reviews[word.id]!.due.timeIntervalSince(time) / 86400)) 天后再复习"
        }
        next(now: time)
        onAnswerFeedback?(AnswerFeedback(rating))
    }

    func markMastered() {
        guard let word = current else { return }
        guard currentQuickTask == nil else { notice = "这次加词请先揭晓，再按 1／2／3 学一次。"; return }
        commitStudyTime()
        let old = saved, id = UUID(); lastUndo = (word, old, id)
        saved.mastered.insert(word.id)
        recordEvent(.mastered, word: word, id: id)
        guard persist() else { saved = old; lastUndo = nil; return }
        notice = "已掌握：该词不再参与新学或复习"
        next()
        onAnswerFeedback?(.mastered)
    }
    func restoreMastered(_ id: String) {
        guard saved.mastered.contains(id) else { return }
        commitStudyTime()
        let old = saved; saved.mastered.remove(id)
        if let word = selectedBook?.words.first(where: { $0.id == id }) { recordEvent(.restored, word: word) }
        guard persist() else { saved = old; return }
        lastUndo = nil; notice = "已恢复到学习队列"
        if current == nil { next() }
    }
    func undo() {
        guard let undo = lastUndo else { return }
        let old = saved, snapshot = undo.snapshot
        let originalRecall = saved.studyEvents.first { $0.id == undo.eventID }?.recallSeconds
        saved.reviews = snapshot.reviews; saved.dailyWords = snapshot.dailyWords
        saved.dailyNewWords = snapshot.dailyNewWords; saved.dailyReviewWords = snapshot.dailyReviewWords
        saved.reviewPlans = snapshot.reviewPlans; saved.mastered = snapshot.mastered
        saved.quickStudyTasks = snapshot.quickStudyTasks
        saved.studyEvents.removeAll { $0.id == undo.eventID }
        saved.newGoalHistory[planKey] = effectiveNewGoal
        saved.reviewGoalHistory[planKey] = todayReviewGoal
        guard persist() else { saved = old; return }
        current = undo.word; revealed = true; lastUndo = nil; notice = "已撤回上次操作"
        recallSeconds = originalRecall; didReveal = true
        presentationID = UUID()
        onWordChanged?()
    }

    // Detailed history is append-only except for explicitly undone scores/mastery.
    // Daily summaries are no longer pruned after 180 days.
    func interact() { lastInteraction = clock() }

    private func recordEvent(_ kind: StudyEventKind, word: Word, at: Date? = nil, id: UUID = UUID(),
                             mode: StudyMode? = nil, rating: Rating? = nil, previous: Review? = nil, result: Review? = nil) {
        interact()
        let time = at ?? clock()
        if var session = focusSession { session.ended = time; focusSession = session }
        saved.studyEvents.append(StudyEvent(id: id, time: time, day: Self.dateKey(time), wordID: word.id,
            word: word.word, bookID: saved.settings.bookID, bookName: selectedBook?.name ?? "词库",
            kind: kind, mode: mode ?? self.mode, rating: rating, previousStage: previous?.stage,
            nextStage: result?.stage, nextDue: result?.due, recallSeconds: kind == .rated ? recallSeconds : nil,
            sessionID: focusSession?.id))
    }

    func revealMeaning() {
        guard let word = current else { return }
        interact()
        if !revealed && !didReveal {
            didReveal = true
            recallSeconds = wordFocusSeconds >= 1 ? wordFocusSeconds : nil
            recordEvent(.revealed, word: word)
            persist()
        }
        revealed.toggle()
    }
    func skipWord() {
        if let task = currentQuickTask { deferredQuickTasks.insert(task.id) }
        if let word = current { recordEvent(.skipped, word: word); persist() }
        next()
    }

    func existingQuickWord(_ text: String) -> Word? {
        guard let term = QuickWordInput.term(text) else { return nil }
        let normalized = QuickWordInput.normalized(term)
        let ordered = (selectedBook.map { [$0] } ?? []) + books.filter { $0.id != saved.settings.bookID }
        return ordered.lazy.compactMap { $0.words.first { QuickWordInput.normalized($0.word) == normalized } }.first
    }
    @discardableResult func addQuickWord(_ candidate: Word) throws -> Bool {
        guard let term = QuickWordInput.term(candidate.word), !candidate.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              candidate.meaning.count <= 2000 else { throw QuickWordError.message("请输入有效英文词和释义。") }
        pauseStudyTiming()
        let old = saved, found = existingQuickWord(term)
        var word = found ?? candidate
        word.id = found?.id ?? QuickWordInput.normalized(term); word.word = found?.word ?? term
        if selectedBook == nil {
            let book = Book(id: "quick-" + UUID().uuidString, name: "随手生词", words: [], isCustom: true)
            saved.customBooks.append(book); saved.settings.bookID = book.id; loadBooks()
        }
        let bookID = saved.settings.bookID
        if selectedBook?.words.contains(where: { QuickWordInput.normalized($0.word) == QuickWordInput.normalized(term) }) != true {
            saved.quickWords[bookID, default: []].append(word)
        }
        if !saved.quickStudyTasks.contains(where: { $0.bookID == bookID && $0.wordID == word.id && $0.completedAt == nil }) {
            saved.quickStudyTasks.append(QuickStudyTask(wordID: word.id, bookID: bookID, createdAt: clock()))
        }
        saved.settings.mode = .newWords
        guard persist() else { saved = old; loadBooks(); throw QuickWordError.message(fileError) }
        loadBooks(); deferredQuickTasks = []; lastUndo = nil
        notice = found == nil ? "尚未收录：已添加，并加入今日新学" : "词库已有：已加入今日新学，先主动学一次"
        presentQuickWord(word)
        return found != nil
    }
    private func presentQuickWord(_ word: Word) {
        current = word; revealed = false; wordFocusSeconds = 0; recallSeconds = nil; didReveal = false
        presentationID = UUID(); onWordChanged?()
    }
    func resumeQuickStudy() {
        deferredQuickTasks = []
        if !pendingQuickTasks.isEmpty { saved.settings.mode = .newWords; next(); persist() }
    }
    func recordPronunciation() {
        if let word = current { recordEvent(.pronounced, word: word); persist() }
    }

    func startStudyTiming() {
        pauseStudyTiming()
        guard current != nil else { return }
        let time = clock()
        interact(); lastTick = time; wasTracking = true
        focusSession = StudySession(id: UUID(), bookID: saved.settings.bookID, day: Self.dateKey(time),
                                    started: time, ended: time, seconds: 0)
    }

    func tickStudyTime(isActive: Bool) {
        let now = clock(), previous = lastTick
        defer { lastTick = now; wasTracking = isActive }
        guard isActive, wasTracking, current != nil, let previous, let interaction = lastInteraction,
              now >= previous, now.timeIntervalSince(interaction) <= 90 else {
            if focusSession != nil { flushStudyTime(); focusSession = nil }
            return
        }
        // A sleeping computer or stalled timer must not turn into hours of study.
        guard now.timeIntervalSince(previous) <= 2.5 else { flushStudyTime(); focusSession = nil; return }
        var cursor = previous
        while cursor < now {
            let day = Self.dateKey(cursor)
            if focusSession?.day != day || focusSession?.bookID != saved.settings.bookID {
                flushStudyTime()
                focusSession = StudySession(id: UUID(), bookID: saved.settings.bookID, day: day,
                                            started: cursor, ended: cursor, seconds: 0)
            }
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: cursor))!
            let end = min(now, tomorrow), seconds = end.timeIntervalSince(cursor)
            var session = focusSession!
            session.seconds += seconds; session.ended = end; focusSession = session
            if !revealed { wordFocusSeconds += seconds }
            cursor = end
        }
        if lastTimeSave == nil || now.timeIntervalSince(lastTimeSave!) >= 30 { flushStudyTime(); lastTimeSave = now }
    }
    private func commitStudyTime() {
        guard let session = focusSession else { return }
        if let index = saved.studySessions.firstIndex(where: { $0.id == session.id }) { saved.studySessions[index] = session }
        else if session.seconds > 0 || saved.studyEvents.contains(where: { $0.sessionID == session.id }) { saved.studySessions.append(session) }
    }
    func flushStudyTime() { commitStudyTime(); persist() }
    func pauseStudyTiming() {
        if focusSession != nil { flushStudyTime() }
        focusSession = nil; lastTick = nil; wasTracking = false
    }
    func statistics(bookID: String? = nil) -> StudyStatistics {
        StudyStatistics(saved: saved, books: books, bookID: bookID, now: clock())
    }
    func deleteBook(_ id: String) {
        guard let book = books.first(where: { $0.id == id }) else { return }
        pauseStudyTiming()
        let old = saved
        saved.archivedBookDates[id] = clock()
        if saved.settings.bookID == id { saved.settings.bookID = books.first(where: { $0.id != id })?.id ?? "" }
        guard persist() else { saved = old; return }
        loadBooks(); visited = []; lastUndo = nil; next()
        notice = "已删除「\(book.name)」，学习记录保留；可在已删除词库中恢复。"
    }
    func restoreBook(_ id: String) {
        guard saved.archivedBookDates[id] != nil else { return }
        let old = saved
        saved.archivedBookDates.removeValue(forKey: id)
        if selectedBook == nil { saved.settings.bookID = id }
        guard persist() else { saved = old; return }
        loadBooks(); visited = []; lastUndo = nil; next()
        notice = "词库已恢复，原学习进度仍保留。"
    }
    @discardableResult func importWords(data: Data, filename: String) throws -> Int {
        let words = try WordImporter.parse(data, filename: filename)
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let book = Book(id: "custom-" + UUID().uuidString, name: name, words: words, isCustom: true)
        let old = saved
        saved.customBooks.append(book); saved.settings.bookID = book.id
        guard persist() else { saved = old; throw CocoaError(.fileWriteUnknown) }
        loadBooks(); visited = []; lastUndo = nil; next(); notice = "已导入 \(words.count) 个词，重复词已合并"
        return words.count
    }
    func export(to url: URL) throws { try encoder.encode(saved).write(to: url, options: .atomic) }
}
