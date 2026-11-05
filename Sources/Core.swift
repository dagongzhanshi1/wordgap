import Foundation
import Combine

struct Word: Codable, Identifiable, Equatable {
    var id: String
    var word: String
    var phonetic: String
    var meaning: String
    var example: String
    var exampleTranslation: String
    var frequency: Int
    var definitionSource: String? = nil
}

struct QuickStudyTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var wordID: String
    var bookID: String
    var createdAt: Date
    var completedAt: Date? = nil
}

struct Book: Codable, Identifiable {
    var id: String
    var name: String
    var words: [Word]
    var isCustom: Bool
}

enum Rating: String, Codable, Equatable {
    case forgot, vague, knew
    var label: String {
        switch self { case .forgot: return "不认识"; case .vague: return "模糊"; case .knew: return "认识" }
    }
}

struct Review: Codable, Equatable {
    var stage: Int = 0
    var due: Date
    var last: Date
    var count: Int = 0
    var rating: Rating

    static func applying(_ rating: Rating, previous: Review?, now: Date) -> Review {
        var stage = previous?.stage ?? 0
        let interval: TimeInterval
        switch rating {
        case .forgot: stage = 0; interval = 600
        case .vague: stage = max(0, stage - 1); interval = 1800
        case .knew:
            let days = [1, 3, 7, 14, 30, 60, 120]
            stage = min(stage + 1, days.count)
            interval = Double(days[stage - 1]) * 86400
        }
        return Review(stage: stage, due: now.addingTimeInterval(interval), last: now,
                      count: (previous?.count ?? 0) + 1, rating: rating)
    }
}

enum StudyMode: String, Codable, CaseIterable {
    case newWords, review
    var label: String { self == .newWords ? "新学" : "复习" }
}

enum WordOrder: String, Codable, CaseIterable {
    case random, alphabetical
    var label: String { self == .random ? "随机顺序" : "字母顺序" }
}

enum CardAction: Equatable { case close, reveal, skip, mastered, speak, rate(Rating) }
enum CardShortcut {
    static func action(for keyCode: UInt16) -> CardAction? {
        switch keyCode {
        case 18, 83: return .rate(.forgot)
        case 19, 84: return .rate(.vague)
        case 20, 85: return .rate(.knew)
        case 21, 86: return .mastered
        case 23, 87: return .speak
        case 49: return .reveal
        case 124: return .skip
        case 53: return .close
        default: return nil
        }
    }
}

struct Settings: Codable {
    var bookID = "advanced"
    var autoRotate = true
    var rotateSeconds = 120
    var autoSpeak = false
    var feedbackSound = false
    var appearance = AppAppearance.system
    var pinned = false
    var british = false
    var mode = StudyMode.newWords
    var dailyNewGoal = 30
    var miniMode = true
    var wordOrder = WordOrder.random
    var glassEnabled = true
    var glassIntensity: Double = 0.65

    enum CodingKeys: String, CodingKey {
        case bookID, autoRotate, rotateSeconds, autoSpeak, feedbackSound, appearance, pinned, british, mode, dailyNewGoal, miniMode, wordOrder, glassEnabled, glassIntensity
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookID = try c.decodeIfPresent(String.self, forKey: .bookID) ?? "advanced"
        autoRotate = try c.decodeIfPresent(Bool.self, forKey: .autoRotate) ?? true
        rotateSeconds = try c.decodeIfPresent(Int.self, forKey: .rotateSeconds) ?? 120
        autoSpeak = try c.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? false
        feedbackSound = try c.decodeIfPresent(Bool.self, forKey: .feedbackSound) ?? false
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        british = try c.decodeIfPresent(Bool.self, forKey: .british) ?? false
        mode = try c.decodeIfPresent(StudyMode.self, forKey: .mode) ?? .newWords
        dailyNewGoal = min(500, max(1, try c.decodeIfPresent(Int.self, forKey: .dailyNewGoal) ?? 30))
        miniMode = try c.decodeIfPresent(Bool.self, forKey: .miniMode) ?? true
        wordOrder = try c.decodeIfPresent(WordOrder.self, forKey: .wordOrder) ?? .random
        glassEnabled = try c.decodeIfPresent(Bool.self, forKey: .glassEnabled) ?? true
        let amount = try c.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? 0.65
        glassIntensity = amount.isFinite ? min(1, max(0, amount)) : 0.65
    }
}

struct SavedData: Codable {
    var version = 3
    var settings = Settings()
    var reviews: [String: Review] = [:]
    var dailyWords: [String: [String]] = [:]
    var customBooks: [Book] = []
    var dailyNewWords: [String: [String]] = [:]
    var dailyReviewWords: [String: [String]] = [:]
    var reviewPlans: [String: [String]] = [:]
    var mastered: Set<String> = []
    var statisticsSince: Date?
    var studyEvents: [StudyEvent] = []
    var studySessions: [StudySession] = []
    var newGoalHistory: [String: Int] = [:]
    var reviewGoalHistory: [String: Int] = [:]
    var archivedBookDates: [String: Date] = [:]
    var quickWords: [String: [Word]] = [:]
    var quickStudyTasks: [QuickStudyTask] = []

    enum CodingKeys: String, CodingKey {
        case version, settings, reviews, dailyWords, customBooks, dailyNewWords, dailyReviewWords, reviewPlans, mastered
        case statisticsSince, studyEvents, studySessions, newGoalHistory, reviewGoalHistory, archivedBookDates
        case quickWords, quickStudyTasks
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        reviews = try c.decodeIfPresent([String: Review].self, forKey: .reviews) ?? [:]
        dailyWords = try c.decodeIfPresent([String: [String]].self, forKey: .dailyWords) ?? [:]
        customBooks = try c.decodeIfPresent([Book].self, forKey: .customBooks) ?? []
        dailyNewWords = try c.decodeIfPresent([String: [String]].self, forKey: .dailyNewWords) ?? [:]
        dailyReviewWords = try c.decodeIfPresent([String: [String]].self, forKey: .dailyReviewWords) ?? [:]
        reviewPlans = try c.decodeIfPresent([String: [String]].self, forKey: .reviewPlans) ?? [:]
        mastered = try c.decodeIfPresent(Set<String>.self, forKey: .mastered) ?? []
        statisticsSince = try c.decodeIfPresent(Date.self, forKey: .statisticsSince)
        studyEvents = try c.decodeIfPresent([StudyEvent].self, forKey: .studyEvents) ?? []
        studySessions = try c.decodeIfPresent([StudySession].self, forKey: .studySessions) ?? []
        newGoalHistory = try c.decodeIfPresent([String: Int].self, forKey: .newGoalHistory) ?? [:]
        reviewGoalHistory = try c.decodeIfPresent([String: Int].self, forKey: .reviewGoalHistory) ?? [:]
        archivedBookDates = try c.decodeIfPresent([String: Date].self, forKey: .archivedBookDates) ?? [:]
        quickWords = try c.decodeIfPresent([String: [Word]].self, forKey: .quickWords) ?? [:]
        quickStudyTasks = try c.decodeIfPresent([QuickStudyTask].self, forKey: .quickStudyTasks) ?? []
    }
}

enum ImportError: LocalizedError {
    case tooLarge, empty, invalidEncoding
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "文件太大，请使用 10 MB 以内的 CSV 或 TSV。"
        case .empty: return "没有读到有效词条。前两列需要是单词和中文释义。"
        case .invalidEncoding: return "文件不是 UTF-8 文本，请另存为 UTF-8 CSV 或 TSV。"
        }
    }
}

enum WordImporter {
    static func rows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], fields: [String] = [], field = ""
        var quoted = false, i = text.startIndex
        while i < text.endIndex {
            let ch = text[i], next = text.index(after: i)
            if ch == "\"" {
                if quoted && next < text.endIndex && text[next] == "\"" {
                    field.append("\""); i = text.index(after: next); continue
                }
                if quoted { quoted = false }
                else if field.trimmingCharacters(in: .whitespaces).isEmpty { quoted = true }
                else { field.append(ch) }
            } else if ch == delimiter && !quoted {
                fields.append(field); field = ""
            } else if (ch == "\n" || ch == "\r\n" || ch == "\r") && !quoted {
                fields.append(field); rows.append(fields); fields = []; field = ""
                if ch == "\r" && next < text.endIndex && text[next] == "\n" {
                    i = text.index(after: next); continue
                }
            } else { field.append(ch) }
            i = next
        }
        if !field.isEmpty || !fields.isEmpty { fields.append(field); rows.append(fields) }
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    static func parse(_ data: Data, filename: String) throws -> [Word] {
        guard data.count <= 10 * 1024 * 1024 else { throw ImportError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw ImportError.invalidEncoding }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let delimiter: Character = filename.lowercased().hasSuffix(".tsv") || text.prefix(500).contains("\t") ? "\t" : ","
        var source = rows(text, delimiter: delimiter)
        guard let first = source.first else { throw ImportError.empty }
        let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let hasHeader = headers.contains("word") || headers.contains("单词")
        let mappings = [["word", "单词"], ["meaning", "translation", "释义", "中文释义"],
                        ["phonetic", "音标"], ["example", "例句"],
                        ["exampletranslation", "example_translation", "例句翻译"]]
        let positions: [Int?] = mappings.enumerated().map { offset, names in
            hasHeader ? headers.firstIndex(where: { names.contains($0) }) : offset
        }
        if hasHeader { source.removeFirst() }
        var seen = Set<String>(), words: [Word] = []
        for row in source {
            func value(_ column: Int) -> String {
                guard let index = positions[column], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\n", with: "\n")
            }
            let word = value(0), meaning = value(1), id = word.lowercased()
            guard !word.isEmpty, !meaning.isEmpty, word.count <= 100, seen.insert(id).inserted else { continue }
            words.append(Word(id: id, word: word, phonetic: value(2), meaning: meaning,
                              example: value(3), exampleTranslation: value(4), frequency: words.count))
            if words.count >= 20000 { break }
        }
        guard !words.isEmpty else { throw ImportError.empty }
        return words
    }
}

