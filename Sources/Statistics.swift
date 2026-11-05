import Foundation

enum StudyEventKind: String, Codable, CaseIterable {
    case rated, mastered, restored, skipped, revealed, pronounced
    var label: String {
        switch self {
        case .rated: return "评分"
        case .mastered: return "掌握"
        case .restored: return "恢复"
        case .skipped: return "跳过"
        case .revealed: return "揭晓"
        case .pronounced: return "发音"
        }
    }
}

struct StudyEvent: Codable, Identifiable {
    var id: UUID
    var time: Date
    var day: String
    var wordID: String
    var word: String
    var bookID: String
    var bookName: String
    var kind: StudyEventKind
    var mode: StudyMode
    var rating: Rating?
    var previousStage: Int?
    var nextStage: Int?
    var nextDue: Date?
    var recallSeconds: Double?
    var sessionID: UUID?
}

struct StudySession: Codable, Identifiable {
    var id: UUID
    var bookID: String
    var day: String
    var started: Date
    var ended: Date
    var seconds: Double
}

enum StatisticsRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, all = 0
    var id: Int { rawValue }
    var label: String { self == .all ? "全部记录" : "近 \(rawValue) 天" }
}

struct StudyDay: Identifiable {
    var day: String
    var date: Date
    var newIDs: Set<String>
    var reviewIDs: Set<String>
    var wordIDs: Set<String>
    var events: [StudyEvent]
    var seconds: Double
    var sessionCount: Int
    var newGoal: Int?
    var reviewGoal: Int?
    var hasDetails: Bool
    var id: String { day }
    var newCount: Int { newIDs.count }
    var reviewCount: Int { reviewIDs.count }
    var uniqueCount: Int { wordIDs.count }
    var rated: [StudyEvent] { events.filter { $0.kind == .rated } }
    var attempts: Int { rated.count }
    var knew: Int { rated.filter { $0.rating == .knew }.count }
    var vague: Int { rated.filter { $0.rating == .vague }.count }
    var forgot: Int { rated.filter { $0.rating == .forgot }.count }
    var masteryCount: Int { events.filter { $0.kind == .mastered }.count }
    var active: Bool { uniqueCount > 0 || masteryCount > 0 }
    var goalMet: Bool { if let goal = newGoal { return goal > 0 && newCount >= goal }; return false }
    var reviewGoalMet: Bool { if let goal = reviewGoal { return goal > 0 && reviewCount >= goal }; return false }
}

struct StudyTotals {
    var days: [StudyDay]
    var newCount: Int { days.reduce(0) { $0 + $1.newCount } }
    var reviewCount: Int { days.reduce(0) { $0 + $1.reviewCount } }
    var wordCount: Int { days.reduce(0) { $0 + $1.uniqueCount } }
    var distinctCount: Int { days.reduce(into: Set<String>()) { $0.formUnion($1.wordIDs) }.count }
    var activeDays: Int { days.filter(\.active).count }
    var events: [StudyEvent] { days.flatMap(\.events) }
    var rated: [StudyEvent] { events.filter { $0.kind == .rated } }
    var attempts: Int { rated.count }
    var reviewAttempts: Int { rated.filter { $0.mode == .review }.count }
    var newAttempts: Int { attempts - reviewAttempts }
    var seconds: Double { days.reduce(0) { $0 + $1.seconds } }
    var sessions: Int { days.reduce(0) { $0 + $1.sessionCount } }
    var dailyAverage: Double { days.isEmpty ? 0 : Double(wordCount) / Double(days.count) }
    var activeDayAverage: Double { activeDays == 0 ? 0 : Double(wordCount) / Double(activeDays) }
    var goalsRecorded: Int { days.filter { ($0.newGoal ?? 0) > 0 }.count }
    var goalsMet: Int { days.filter(\.goalMet).count }
    var reviewGoalsRecorded: Int { days.filter { ($0.reviewGoal ?? 0) > 0 }.count }
    var reviewGoalsMet: Int { days.filter(\.reviewGoalMet).count }
    func count(_ rating: Rating, reviewOnly: Bool = false) -> Int {
        rated.filter { $0.rating == rating && (!reviewOnly || $0.mode == .review) }.count
    }
    var recognitionRate: Double? { attempts == 0 ? nil : Double(count(.knew)) / Double(attempts) }
    var reviewRecognitionRate: Double? { reviewAttempts == 0 ? nil : Double(count(.knew, reviewOnly: true)) / Double(reviewAttempts) }
    var medianRecall: Double? {
        let values = rated.compactMap(\.recallSeconds).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
}

struct StudyWeek: Identifiable {
    var start: Date
    var totals: StudyTotals
    var id: Date { start }
}

struct DifficultWord: Identifiable {
    var word: String
    var wordID: String
    var events: [StudyEvent]
    var id: String { wordID }
    var forgot: Int { events.filter { $0.rating == .forgot }.count }
    var vague: Int { events.filter { $0.rating == .vague }.count }
    var knew: Int { events.filter { $0.rating == .knew }.count }
    var last: Date { events.map(\.time).max() ?? .distantPast }
}

struct StudyStatistics {
    let saved: SavedData
    let books: [Book]
    let bookID: String?
    let now: Date
    let scopedIDs: Set<String>
    let events: [StudyEvent]
    let sessions: [StudySession]
    let eventDays: [String: [StudyEvent]]
    let sessionDays: [String: [StudySession]]

    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone.current; c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        return c
    }
    static func date(_ day: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }
    static func label(_ date: Date, format: String = "M/d") -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.calendar = calendar; f.dateFormat = format; return f.string(from: date)
    }
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) 秒" }
        if s < 3600 { return "\(s / 60) 分 \(s % 60) 秒" }
        return "\(s / 3600) 小时 \(s % 3600 / 60) 分"
    }
    static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
    }

    init(saved: SavedData, books: [Book], bookID: String?, now: Date) {
        let activeBooks = books.filter { saved.archivedBookDates[$0.id] == nil }
        self.saved = saved; self.books = activeBooks; self.bookID = bookID; self.now = now
        let chosen = activeBooks.filter { bookID == nil || $0.id == bookID }
        let chosenBookIDs = Set(chosen.map(\.id))
        scopedIDs = Set(chosen.flatMap { $0.words.map(\.id) })
        events = saved.studyEvents.filter { chosenBookIDs.contains($0.bookID) }
        sessions = saved.studySessions.filter { chosenBookIDs.contains($0.bookID) }
        eventDays = Dictionary(grouping: events, by: \.day)
        sessionDays = Dictionary(grouping: sessions, by: \.day)
    }
    var today: Date { Self.calendar.startOfDay(for: now) }
    var firstDay: Date {
        let keys = Set(saved.dailyWords.keys).union(saved.dailyNewWords.keys).union(saved.dailyReviewWords.keys)
            .union(eventDays.keys).union(sessionDays.keys)
        return min(today, keys.compactMap(Self.date).min() ?? today)
    }
    var trackingLabel: String { saved.statisticsSince.map { Self.label($0, format: "yyyy年M月d日 HH:mm") } ?? "未开始" }
    func day(_ date: Date) -> StudyDay {
        let key = WordStore.dateKey(date), dayEvents = eventDays[key] ?? [], daySessions = sessionDays[key] ?? []
        // Old versions only saved word IDs, so historic attribution uses current
        // book membership. New event details retain the actual book and timestamp.
        func ids(_ source: [String: [String]]) -> Set<String> {
            let values = Set(source[key] ?? [])
            return values.intersection(scopedIDs)
        }
        var newIDs = ids(saved.dailyNewWords), reviewIDs = ids(saved.dailyReviewWords), wordIDs = ids(saved.dailyWords)
        newIDs.formUnion(dayEvents.filter { $0.kind == .rated && $0.mode == .newWords }.map(\.wordID))
        reviewIDs.formUnion(dayEvents.filter { $0.kind == .rated && $0.mode == .review }.map(\.wordID))
        wordIDs.formUnion(newIDs); wordIDs.formUnion(reviewIDs)
        let goalKeys = Set(books.filter { bookID == nil || $0.id == bookID }.map { key + "|" + $0.id })
        let goals = saved.newGoalHistory.filter { goalKeys.contains($0.key) }
        let reviewGoals = saved.reviewGoalHistory.filter { goalKeys.contains($0.key) }
        let showGoals = bookID != nil || books.count == 1
        return StudyDay(day: key, date: Self.calendar.startOfDay(for: date), newIDs: newIDs, reviewIDs: reviewIDs,
            wordIDs: wordIDs, events: dayEvents, seconds: daySessions.reduce(0) { $0 + $1.seconds },
            sessionCount: daySessions.filter { session in session.seconds > 0 || dayEvents.contains(where: { $0.sessionID == session.id }) }.count,
            newGoal: !showGoals || goals.isEmpty ? nil : goals.values.reduce(0, +),
            reviewGoal: !showGoals || reviewGoals.isEmpty ? nil : reviewGoals.values.reduce(0, +),
            hasDetails: saved.statisticsSince.map { key >= WordStore.dateKey($0) } ?? false)
    }
    func days(from start: Date, through end: Date) -> [StudyDay] {
        guard start <= end else { return [] }
        var result: [StudyDay] = [], cursor = Self.calendar.startOfDay(for: start)
        let limit = Self.calendar.startOfDay(for: end)
        while cursor <= limit {
            result.append(day(cursor))
            guard let next = Self.calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
    func days(_ range: StatisticsRange) -> [StudyDay] {
        let start = range == .all ? firstDay : Self.calendar.date(byAdding: .day, value: 1 - range.rawValue, to: today)!
        return days(from: start, through: today)
    }
    func totals(_ range: StatisticsRange) -> StudyTotals { StudyTotals(days: days(range)) }
    func weekStart(_ date: Date) -> Date { Self.calendar.dateInterval(of: .weekOfYear, for: date)!.start }
    var thisWeek: StudyTotals { StudyTotals(days: days(from: weekStart(today), through: today)) }
    var lastWeekSameDays: StudyTotals {
        let start = Self.calendar.date(byAdding: .day, value: -7, to: weekStart(today))!
        return StudyTotals(days: days(from: start, through: Self.calendar.date(byAdding: .day, value: -7, to: today)!))
    }
    func weeks(_ range: StatisticsRange) -> [StudyWeek] {
        Dictionary(grouping: days(range), by: { weekStart($0.date) }).map {
            StudyWeek(start: $0.key, totals: StudyTotals(days: $0.value))
        }.sorted { $0.start > $1.start }
    }
    var currentStreak: Int {
        var date = today, count = 0
        if !day(date).active { date = Self.calendar.date(byAdding: .day, value: -1, to: date)! }
        while date >= firstDay && day(date).active {
            count += 1; date = Self.calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }
    var longestStreak: Int {
        var longest = 0, current = 0
        for day in days(.all) { current = day.active ? current + 1 : 0; longest = max(longest, current) }
        return longest
    }
    var learned: Int { Set(saved.reviews.keys).intersection(scopedIDs).subtracting(saved.mastered).count }
    var lifetimeReviewCount: Int { saved.reviews.filter { scopedIDs.contains($0.key) }.values.reduce(0) { $0 + $1.count } }
    func latestRatingCount(_ rating: Rating) -> Int {
        saved.reviews.filter { scopedIDs.contains($0.key) && !saved.mastered.contains($0.key) && $0.value.rating == rating }.count
    }
    var mastered: Int { saved.mastered.intersection(scopedIDs).count }
    var remaining: Int { max(0, scopedIDs.count - learned - mastered) }
    private var retainedReviews: [String: Review] { saved.reviews.filter { scopedIDs.contains($0.key) && !saved.mastered.contains($0.key) } }
    var due: [Review] {
        let activeIDs = Set(books.filter { saved.archivedBookDates[$0.id] == nil && (bookID == nil || $0.id == bookID) }.flatMap { $0.words.map(\.id) })
        return retainedReviews.filter { activeIDs.contains($0.key) }.map(\.value)
    }
    var overdue: Int { due.filter { $0.due <= now }.count }
    var stages: [Int] { (0...7).map { stage in retainedReviews.values.filter { $0.stage == stage }.count } }
    var upcoming: [(date: Date, count: Int)] {
        (0..<7).map { offset in
            let date = Self.calendar.date(byAdding: .day, value: offset, to: today)!
            let next = Self.calendar.date(byAdding: .day, value: 1, to: date)!
            return (date, due.filter { offset == 0 ? $0.due < next : $0.due >= date && $0.due < next }.count)
        }
    }
    func difficult(_ range: StatisticsRange) -> [DifficultWord] {
        let rated = totals(range).rated
        return Dictionary(grouping: rated, by: \.wordID).map {
            DifficultWord(word: $0.value.last?.word ?? $0.key, wordID: $0.key, events: $0.value)
        }.filter { $0.forgot + $0.vague > 0 }.sorted {
            if $0.forgot != $1.forgot { return $0.forgot > $1.forgot }
            if $0.vague != $1.vague { return $0.vague > $1.vague }
            if $0.events.count != $1.events.count { return $0.events.count > $1.events.count }
            return $0.word < $1.word
        }
    }
    func sessions(_ range: StatisticsRange) -> [StudySession] {
        let keys = Set(days(range).map(\.day))
        return sessions.filter { session in keys.contains(session.day) && (session.seconds > 0 || events.contains(where: { $0.sessionID == session.id })) }
            .sorted { $0.started > $1.started }
    }
    private static func csv(_ value: String) -> String {
        let guarded = ["=", "+", "-", "@"].contains(String(value.prefix(1))) ? "'" + value : value
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func csvRows(_ rows: [[String]]) -> String {
        "\u{FEFF}" + rows.map { $0.map(csv).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    func dailyCSV(_ range: StatisticsRange) -> String {
        let header = ["日期", "新学词数", "复习词数", "当日不同单词", "评分次数", "新学评分次数", "复习评分次数", "认识", "模糊", "不认识", "认识率", "掌握操作次数", "专注秒数", "学习片段", "新词目标", "新词目标完成", "复习目标", "复习目标完成", "详细记录覆盖"]
        return Self.csvRows([header] + days(range).map { d in
            let detail = d.hasDetails
            return [d.day, String(d.newCount), String(d.reviewCount), String(d.uniqueCount),
                detail ? String(d.attempts) : "", detail ? String(d.rated.filter { $0.mode == .newWords }.count) : "",
                detail ? String(d.rated.filter { $0.mode == .review }.count) : "", detail ? String(d.knew) : "",
                detail ? String(d.vague) : "", detail ? String(d.forgot) : "",
                d.attempts > 0 ? String(format: "%.4f", Double(d.knew) / Double(d.attempts)) : "",
                detail ? String(d.masteryCount) : "", detail ? String(format: "%.1f", d.seconds) : "",
                detail ? String(d.sessionCount) : "", d.newGoal.map(String.init) ?? "",
                (d.newGoal ?? 0) == 0 ? "" : (d.goalMet ? "是" : "否"), d.reviewGoal.map(String.init) ?? "",
                (d.reviewGoal ?? 0) == 0 ? "" : (d.reviewGoalMet ? "是" : "否"), detail ? "详见采集起始时间" : "仅旧版词数"]
        })
    }
    func eventsCSV(_ range: StatisticsRange) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = Self.calendar.timeZone
        let rows = totals(range).events.sorted { $0.time < $1.time }.map { e in
            [e.id.uuidString, f.string(from: e.time), e.day, e.word, e.bookName, e.bookID, e.kind.label,
             e.mode.label, e.rating?.label ?? "", e.previousStage.map(String.init) ?? "",
             e.nextStage.map(String.init) ?? "", e.nextDue.map { f.string(from: $0) } ?? "",
             e.recallSeconds.map { String(format: "%.1f", $0) } ?? "", e.sessionID?.uuidString ?? ""]
        }
        return Self.csvRows([["事件ID", "时间（含时区）", "记录日期", "单词", "词库", "词库ID", "操作", "模式", "评分", "原阶段", "新阶段", "下次复习", "揭晓前专注秒数", "片段ID"]] + rows)
    }
    func sessionsCSV(_ range: StatisticsRange) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = Self.calendar.timeZone
        let rows = sessions(range).reversed().map { session -> [String] in
            let ratings = events.filter { $0.sessionID == session.id && $0.kind == .rated }
            let name = books.first { $0.id == session.bookID }?.name ?? session.bookID
            return [session.id.uuidString, session.day, f.string(from: session.started), f.string(from: session.ended),
                name, session.bookID, String(format: "%.1f", session.seconds), String(ratings.count),
                String(ratings.filter { $0.mode == .newWords }.count), String(ratings.filter { $0.mode == .review }.count),
                String(Set(ratings.map(\.wordID)).count), String(ratings.filter { $0.rating == .knew }.count),
                String(ratings.filter { $0.rating == .vague }.count), String(ratings.filter { $0.rating == .forgot }.count)]
        }
        return Self.csvRows([["片段ID", "日期", "开始时间（含时区）", "结束时间（含时区）", "词库", "词库ID", "专注秒数", "评分次数", "新学评分", "复习评分", "不同评分单词", "认识", "模糊", "不认识"]] + rows)
    }
}
