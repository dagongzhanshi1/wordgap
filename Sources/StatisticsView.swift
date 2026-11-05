import SwiftUI
import Charts

private let statsInk = AppPalette.ink
private let statsMuted = AppPalette.muted
private let statsGreen = AppPalette.accent
private let statsReview = AppPalette.review
private let statsPaper = AppPalette.statisticsBackground

struct StatisticsView: View {
    @ObservedObject var store: WordStore
    var exportCSV: (String, String) -> Void
    @State private var range = StatisticsRange.month
    @State private var scope = "all"
    @State private var tab = 0
    @State private var search = ""
    @State private var eventFilter = "all"
    private var stats: StudyStatistics {
        store.statistics(bookID: scope == "all" || !store.books.contains(where: { $0.id == scope }) ? nil : scope)
    }

    init(store: WordStore, exportCSV: @escaping (String, String) -> Void) {
        self.store = store; self.exportCSV = exportCSV
        _scope = State(initialValue: store.selectedBook?.id ?? "all")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("学习统计").font(.system(size: 20, weight: .semibold))
                        Text("日 / 周记录、学习趋势与逐次明细").font(.system(size: 11)).foregroundStyle(statsMuted)
                    }
                    Spacer()
                    SelectionMenu(selection: $scope, options: [("全部词库", "all")] + store.books.map { ($0.name, $0.id) }, label: "统计词库")
                        .frame(width: 150)
                    Menu {
                        Button("按日汇总…") { exportCSV(stats.dailyCSV(range), "词隙-每日统计.csv") }
                        Button("完整操作明细…") { exportCSV(stats.eventsCSV(range), "词隙-学习明细.csv") }
                        Button("专注片段…") { exportCSV(stats.sessionsCSV(range), "词隙-专注片段.csv") }
                    } label: {
                        HStack(spacing: 8) {
                            Text("导出CSV")
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }.font(.system(size: 11)).foregroundStyle(statsInk).frame(height: 16)
                    }.menuStyle(.button).menuIndicator(.hidden).buttonStyle(UniformMenuButtonStyle()).tint(statsInk)
                        .frame(width: 106).accessibilityLabel("导出CSV")
                }.frame(maxWidth: .infinity)
                HStack(spacing: 20) {
                    ChoiceStrip(selection: $tab, options: [("概览", 0), ("日 / 周记录", 1), ("单词与复习", 2), ("学习明细", 3)], label: "统计页面")
                        .frame(maxWidth: 430)
                    Spacer()
                    SelectionMenu(selection: $range, options: StatisticsRange.allCases.map { ($0.label, $0) }, label: "时间范围")
                        .frame(width: 128)
                }
            }.padding(.horizontal, 24).padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(AppPalette.hairline.opacity(0.22)).frame(height: 0.5) }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if tab == 0 { overview }
                    else if tab == 1 { dailyAndWeekly }
                    else if tab == 2 { wordsAndReview }
                    else { eventDetails }
                    methodology
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.foregroundStyle(statsInk).background { WordGapWindowBackdrop() }.tint(AppPalette.accent)
            .onChange(of: store.books.map(\.id)) { ids in
                if scope != "all" && !ids.contains(scope) { scope = "all" }
            }
    }

    private var overview: some View {
        let s = stats, total = s.totals(range), today = s.day(s.today)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 0) {
                Text("今日").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("新学 \(today.newCount) 词   复习 \(today.reviewCount) 词   评分 \(today.attempts) 次   专注 \(StudyStatistics.duration(today.seconds))")
                    .font(.system(size: 12)).monospacedDigit()
            }.padding(16).modifier(QuietSurface(radius: 12))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                metric("新学词数", String(total.newCount), note: "各日新学词数之和")
                metric("复习词数", String(total.reviewCount), note: "同词隔天复习分别计入")
                metric("评分次数", String(total.attempts), note: "新学 \(total.newAttempts) · 复习 \(total.reviewAttempts)")
                metric("不同单词", String(total.distinctCount), note: "所选期间跨日去重")
                metric("专注时长", StudyStatistics.duration(total.seconds), note: "\(total.sessions) 个前台学习片段")
                metric("学习天数", "\(total.activeDays) / \(total.days.count)", note: "有评分或掌握操作的日期")
                metric("连续学习", "\(s.currentStreak) 天", note: "历史最长 \(s.longestStreak) 天")
                metric("复习认识率", StudyStatistics.percent(total.reviewRecognitionRate), note: "复习认识次数 ÷ 复习评分次数")
            }
            section("学习量趋势", subtitle: "每日去重 · 新学与复习分别统计") {
                HStack(spacing: 18) { legend("新学", statsGreen); legend("复习", statsReview) }
                Chart(total.days) { day in
                    BarMark(x: .value("日期", day.date, unit: .day), y: .value("新学", day.newCount))
                        .foregroundStyle(statsGreen)
                    BarMark(x: .value("日期", day.date, unit: .day), y: .value("复习", day.reviewCount))
                        .foregroundStyle(statsReview)
                }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) { AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
                    .chartYAxis { AxisMarks(position: .leading) }.frame(height: 200)
                Text("日均 \(String(format: "%.1f", total.dailyAverage)) 词（含未学习日） · 学习日均 \(String(format: "%.1f", total.activeDayAverage)) 词 · 单日最高 \(total.days.map(\.uniqueCount).max() ?? 0) 词")
                    .font(.system(size: 11)).foregroundStyle(statsMuted)
            }
            weekComparison(s)
            section("学习日历", subtitle: "最近 13 周 · 悬停查看每天的数据") { heatmap(s) }
            HStack(alignment: .top, spacing: 16) {
                section("评分分布", subtitle: "\(total.attempts) 次有效评分，撤回不计入") {
                    distribution("认识", total.count(.knew), total.attempts, statsGreen)
                    distribution("模糊", total.count(.vague), total.attempts, statsReview)
                    distribution("不认识", total.count(.forgot), total.attempts, Color(red: 0.74, green: 0.45, blue: 0.39))
                    Text("总认识率 \(StudyStatistics.percent(total.recognitionRate)) · 此为自评结果")
                        .font(.system(size: 11)).foregroundStyle(statsMuted)
                }
                section("学习节奏", subtitle: range.label) {
                    pair("新词目标达标", "\(total.goalsMet) / \(total.goalsRecorded) 个有目标记录的日期")
                    pair("复习目标达标", "\(total.reviewGoalsMet) / \(total.reviewGoalsRecorded) 个有复习目标的日期")
                    pair("揭晓前专注中位数", total.medianRecall.map { String(format: "%.1f 秒", $0) } ?? "—")
                    pair("每片段平均时长", total.sessions > 0 ? StudyStatistics.duration(total.seconds / Double(total.sessions)) : "—")
                    pair("掌握操作", "\(total.events.filter { $0.kind == .mastered }.count) 次")
                    pair("跳过 / 发音", "\(total.events.filter { $0.kind == .skipped }.count) / \(total.events.filter { $0.kind == .pronounced }.count) 次")
                }
            }
            section("学习时段", subtitle: "按评分时间统计，使用本地时区") {
                let hours = Dictionary(grouping: total.rated, by: { StudyStatistics.calendar.component(.hour, from: $0.time) })
                Chart(0..<24, id: \.self) { hour in
                    BarMark(x: .value("小时", hour), y: .value("评分次数", hours[hour]?.count ?? 0)).foregroundStyle(statsGreen)
                }.chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) }.frame(height: 135)
            }
            section("每周学习节奏", subtitle: "各星期的日均不同单词数；分母包含对应星期的未学习日") {
                let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
                Chart(0..<7, id: \.self) { index in
                    let matches = total.days.filter { (StudyStatistics.calendar.component(.weekday, from: $0.date) + 5) % 7 == index }
                    let average = matches.isEmpty ? 0 : Double(matches.reduce(0) { $0 + $1.uniqueCount }) / Double(matches.count)
                    BarMark(x: .value("星期", weekdays[index]), y: .value("日均不同单词", average)).foregroundStyle(statsGreen)
                }.frame(height: 145)
            }
        }
    }

    private func weekComparison(_ s: StudyStatistics) -> some View {
        let this = s.thisWeek, last = s.lastWeekSameDays
        return section("本周与上周同期", subtitle: "周一至今天，与上周相同天数比较") {
            HStack(spacing: 24) {
                comparison("新学", this.newCount, last.newCount)
                comparison("复习", this.reviewCount, last.reviewCount)
                comparison("评分", this.attempts, last.days.contains(where: \.hasDetails) ? last.attempts : nil)
                comparison("专注分钟", Int(this.seconds / 60), last.days.contains(where: \.hasDetails) ? Int(last.seconds / 60) : nil)
            }
            Text("本周学习 \(this.activeDays) 天 · 上周同期 \(last.activeDays) 天。今天尚未结束；上周同日为完整日。评分和专注时长仅统计已采集的明细，采集首日可能不完整。")
                .font(.system(size: 11)).foregroundStyle(statsMuted)
        }
    }

    private func heatmap(_ s: StudyStatistics) -> some View {
        let start = StudyStatistics.calendar.date(byAdding: .day, value: -84, to: s.weekStart(s.today))!
        let maximum = max(1, s.days(from: start, through: s.today).map(\.uniqueCount).max() ?? 1)
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.system(size: 9)).frame(height: 17) }
            }.foregroundStyle(statsMuted)
            ForEach(0..<13, id: \.self) { week in
                VStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let date = StudyStatistics.calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)!
                        let day = s.day(date), future = date > s.today
                        RoundedRectangle(cornerRadius: 3)
                            .fill(future || day.uniqueCount == 0 ? statsPaper : statsGreen.opacity(0.22 + 0.78 * Double(day.uniqueCount) / Double(maximum)))
                            .frame(width: 17, height: 17)
                            .help(future ? "尚未到来" : "\(day.day)\n新学 \(day.newCount) · 复习 \(day.reviewCount)\n不同单词 \(day.uniqueCount) · 评分 \(day.attempts)\n专注 \(StudyStatistics.duration(day.seconds))")
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("颜色按当日不同单词数表示。")
                Text("新学后又复习同一词，当日只算一个不同单词。")
                Text("当前连续天数可延续到昨日；今天完成学习后续上。")
            }.font(.system(size: 11)).foregroundStyle(statsMuted).frame(maxWidth: 270, alignment: .leading)
        }
    }

    private var dailyAndWeekly: some View {
        let s = stats
        return VStack(alignment: .leading, spacing: 20) {
            section("按周汇总", subtitle: "周一开始 · 首尾周仅汇总所选范围内的日期") {
                tableHeader([("日期范围", 158), ("新学", 50), ("复习", 50), ("评分", 50), ("学习日", 58), ("专注", 105)])
                ForEach(s.weeks(range)) { week in
                    let total = week.totals
                    HStack(spacing: 12) {
                        cell(StudyStatistics.label(total.days.first!.date) + " – " + StudyStatistics.label(total.days.last!.date), 158)
                        cell(String(total.newCount), 50); cell(String(total.reviewCount), 50)
                        cell(total.days.contains(where: \.hasDetails) ? String(total.attempts) : "—", 50); cell("\(total.activeDays)/\(total.days.count)", 58)
                        cell(total.days.contains(where: \.hasDetails) ? StudyStatistics.duration(total.seconds) : "—", 105)
                        Spacer(minLength: 0)
                    }.font(.system(size: 12)).padding(.vertical, 7)
                    Divider()
                }
            }
            section("按日记录", subtitle: "包含未学习日 · 历史学习量不会因后来掌握或恢复而减少") {
                tableHeader([("日期", 72), ("新学", 38), ("复习", 38), ("不同词", 48), ("评分", 38), ("认识率", 58), ("专注", 88), ("新词目标", 70), ("复习目标", 70)])
                LazyVStack(spacing: 0) {
                    ForEach(s.days(range).reversed()) { day in
                        HStack(spacing: 12) {
                            cell(StudyStatistics.label(day.date, format: "MM/dd E"), 72)
                            cell(String(day.newCount), 38); cell(String(day.reviewCount), 38)
                            cell(String(day.uniqueCount), 48); cell(day.hasDetails ? String(day.attempts) : "—", 38)
                            cell(StudyStatistics.percent(day.attempts > 0 ? Double(day.knew) / Double(day.attempts) : nil), 58)
                            cell(day.hasDetails ? StudyStatistics.duration(day.seconds) : "—", 88)
                            cell(day.newGoal.map { "\(day.newCount)/\($0)" } ?? "—", 70)
                            cell(day.reviewGoal.map { "\(day.reviewCount)/\($0)" } ?? "—", 70)
                            Spacer(minLength: 0)
                        }.font(.system(size: 11)).padding(.vertical, 9)
                            .foregroundStyle(day.active ? statsInk : statsMuted)
                        Divider()
                    }
                }
            }
            section("专注片段", subtitle: "最近 30 个片段 · 切走应用、收起卡片或空闲后暂停计时") {
                let sessions = s.sessions(range)
                if sessions.isEmpty { empty("还没有专注片段。打开卡片开始背词后会自动记录。") }
                ForEach(Array(sessions.prefix(30))) { session in
                    let count = s.events.filter { $0.sessionID == session.id && $0.kind == .rated }.count
                    HStack {
                        Text(StudyStatistics.label(session.started, format: "MM/dd HH:mm") + " – " + StudyStatistics.label(session.ended, format: "HH:mm"))
                        Spacer(); Text("评分 \(count) 次"); Text(StudyStatistics.duration(session.seconds)).frame(width: 115, alignment: .trailing)
                    }.font(.system(size: 12)).padding(.vertical, 5)
                }
            }
        }
    }

    private var wordsAndReview: some View {
        let s = stats
        return VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                metric("已学待复习", String(s.learned), note: "有复习记录，未标记掌握")
                metric("已完全掌握", String(s.mastered), note: "由你手动排除")
                metric("尚未学习", String(s.remaining), note: "词库共 \(s.scopedIDs.count) 个不同词")
                metric("当前到期", String(s.overdue), note: "已到复习时间，含逾期")
            }
            section("词库进度", subtitle: "认识评分不等于完全掌握，二者分别计算") {
                let progress = s.scopedIDs.isEmpty ? 0 : Double(s.learned + s.mastered) / Double(s.scopedIDs.count)
                ProgressView(value: progress).tint(statsGreen)
                Text("已处理 \(s.learned + s.mastered) / \(s.scopedIDs.count) · \(StudyStatistics.percent(progress))").font(.system(size: 12))
                Text("当前保留的累计评分计数 \(s.lifetimeReviewCount) 次（含旧版） · 最近自评：认识 \(s.latestRatingCount(.knew)) / 模糊 \(s.latestRatingCount(.vague)) / 不认识 \(s.latestRatingCount(.forgot)) 词")
                    .font(.system(size: 11)).foregroundStyle(statsMuted)
                HStack { ForEach(0..<8, id: \.self) { stage in
                    VStack(spacing: 8) { Text(String(s.stages[stage])).font(.system(size: 20, weight: .semibold)).monospacedDigit(); Text("阶段 \(stage)").font(.system(size: 10)).foregroundStyle(statsMuted) }.frame(maxWidth: .infinity)
                }}.padding(.top, 12)
            }
            section("接下来 7 天的复习", subtitle: "按当前下次复习日期的快照；已删除词库不参与排程，评分后安排会变化") {
                HStack(spacing: 10) {
                    ForEach(Array(s.upcoming.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 9) {
                            Text(index == 0 ? "今天＋逾期" : StudyStatistics.label(item.date)).font(.system(size: 11)).foregroundStyle(statsMuted)
                            Text(String(item.count)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        }.frame(maxWidth: .infinity).padding(.vertical, 12).modifier(QuietSurface(radius: 9))
                    }
                }
            }
            section("易错单词", subtitle: "所选时间范围 · 优先按不认识次数、模糊次数排列") {
                let words = s.difficult(range)
                if words.isEmpty { empty("还没有记录到不认识或模糊的评分。旧版没有逐次评分历史。") }
                tableHeader([("单词", 180), ("不认识", 60), ("模糊", 50), ("认识", 50), ("总评分", 60), ("最后评分", 130)])
                ForEach(Array(words.prefix(50))) { word in
                    HStack(spacing: 12) {
                        Text(word.word).font(.system(size: 13, weight: .medium)).frame(width: 180, alignment: .leading).lineLimit(1).help(word.word)
                        cell(String(word.forgot), 60); cell(String(word.vague), 50); cell(String(word.knew), 50)
                        cell(String(word.events.count), 60); cell(StudyStatistics.label(word.last, format: "MM/dd HH:mm"), 130)
                        Spacer(minLength: 0)
                    }.font(.system(size: 12)).padding(.vertical, 8)
                    Divider()
                }
                if words.count > 50 { Text("显示前 50 个，完整评分明细可导出 CSV。").font(.system(size: 11)).foregroundStyle(statsMuted) }
            }
        }
    }

    private var eventDetails: some View {
        let all = stats.totals(range).events
        let filtered = all.filter {
            (eventFilter == "all" || $0.kind.rawValue == eventFilter) &&
            (search.isEmpty || $0.word.localizedCaseInsensitiveContains(search))
        }.sorted { $0.time > $1.time }
        return section("逐次学习明细", subtitle: "\(filtered.count) 条符合筛选 · 页面显示最近 200 条，CSV 导出所选范围的全部明细") {
            HStack {
                TextField("搜索单词", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                SelectionMenu(selection: $eventFilter, options: [("全部操作", "all")] + StudyEventKind.allCases.map { ($0.label, $0.rawValue) }, label: "操作筛选").frame(width: 145)
                Spacer()
            }
            if filtered.isEmpty { empty("所选范围没有明细。详细记录从本次升级后开始采集。") }
            tableHeader([("时间", 112), ("单词", 175), ("操作", 46), ("模式", 44), ("评分", 58), ("新阶段", 50), ("揭晓用时", 75)])
            LazyVStack(spacing: 0) {
                ForEach(Array(filtered.prefix(200))) { event in
                    HStack(spacing: 12) {
                        cell(StudyStatistics.label(event.time, format: "MM/dd HH:mm:ss"), 112)
                        Text(event.word).frame(width: 175, alignment: .leading).lineLimit(1).help("\(event.word) · \(event.bookName)")
                        cell(event.kind.label, 46); cell(event.kind == .rated ? event.mode.label : "—", 44)
                        cell(event.rating?.label ?? "—", 58); cell(event.nextStage.map(String.init) ?? "—", 50)
                        cell(event.recallSeconds.map { String(format: "%.1f 秒", $0) } ?? "—", 75)
                        Spacer(minLength: 0)
                    }.font(.system(size: 11)).padding(.vertical, 9)
                    Divider()
                }
            }
        }
    }

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("统计口径").font(.system(size: 11, weight: .semibold))
            Text("旧版日记录已保留。逐次评分、发音、跳过、专注时长和目标历史从 \(stats.trackingLabel) 开始记录；升级当天的明细可能只覆盖部分时间，无法补出旧版未记录的数据。")
            Text("词数按天去重，次数按操作累计。同词当天新学后复习，新学 / 复习各计一次，不同单词仅计一个；跨日累计会重复计词。撤回移除对应评分或掌握事件，不删除真实专注时间。认识率是自评认识次数的占比，并非客观测试正确率。")
            Text("专注时间仅在单词卡片位于前台并有可学单词时估算；切到其他应用、设置或统计页时暂停，90 秒没有卡片交互也会暂停，休眠不计入。揭晓用时是第一次揭晓前累计的前台专注时间，少于 1 秒无样本。")
            Text("每周从周一开始；本周对比上周同期，保持天数一致。缺少评分样本或旧版时长以 — 表示。日词数按所选词库的单词归属统计，同词跨词库共享学习状态；评分、明细和专注按实际使用的词库统计。多词库的目标达标需选择单一词库，避免把不完整目标相加。统计选项及全部词库汇总仅包含现有词库；已删除词库恢复后可继续查看历史。全部数据只存在本机，不再按 180 天自动裁剪。")
        }.font(.system(size: 11)).foregroundStyle(statsMuted).lineSpacing(4).padding(.top, 4)
    }

    private func section<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) { Text(title).font(.system(size: 14, weight: .semibold)); Spacer() }
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(statsMuted) }
            content()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).modifier(QuietSurface(radius: 13))
    }
    private func metric(_ title: String, _ value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11)).foregroundStyle(statsMuted)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 10)).foregroundStyle(statsMuted).lineLimit(2).frame(height: 28, alignment: .topLeading)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).modifier(QuietSurface(radius: 12))
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8); Text(title).font(.system(size: 11)).foregroundStyle(statsMuted) }
    }
    private func pair(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(statsMuted); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 11))
    }
    private func distribution(_ title: String, _ count: Int, _ total: Int, _ color: Color) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(count) 次 · \(StudyStatistics.percent(total > 0 ? Double(count) / Double(total) : nil))").monospacedDigit() }.font(.system(size: 11))
            ProgressView(value: total > 0 ? Double(count) / Double(total) : 0).tint(color)
        }
    }
    private func comparison(_ title: String, _ current: Int, _ previous: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(statsMuted)
            Text(String(current)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            Text("上周同期 " + (previous.map(String.init) ?? "—")).font(.system(size: 10)).foregroundStyle(statsMuted)
            Text(previous.map { $0 > 0 ? String(format: "%+.1f%%", Double(current - $0) / Double($0) * 100) : "上期为 0，未计算变化率" } ?? "上期没有详细记录")
                .font(.system(size: 10)).foregroundStyle(statsMuted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func tableHeader(_ columns: [(String, CGFloat)]) -> some View {
        HStack(spacing: 12) { ForEach(columns.indices, id: \.self) { i in cell(columns[i].0, columns[i].1) }; Spacer(minLength: 0) }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(statsMuted).padding(.vertical, 7)
    }
    private func cell(_ value: String, _ width: CGFloat) -> some View {
        Text(value).monospacedDigit().frame(width: width, alignment: .leading).lineLimit(1).help(value)
    }
    private func empty(_ value: String) -> some View {
        Text(value).font(.system(size: 12)).foregroundStyle(statsMuted).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
    }
}
