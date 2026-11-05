import SwiftUI

private let ink = AppPalette.ink
private let muted = AppPalette.muted
private let paper = AppPalette.paper
private let accent = AppPalette.accent
private let reviewCountHelp = "今天结束前仍需复习的不同单词数，包含已到期及今天稍后到期的词。选不认识或模糊后，只要下次仍在今天，就继续计入；选认识排到明天或更晚，或标记掌握后，才移出今日待复习。未到期的词不会提前出现。"

struct CardView: View {
    @ObservedObject var store: WordStore
    var speak: (String) -> Void
    var settings: () -> Void
    var hide: () -> Void
    var togglePin: () -> Void
    var toggleMini: () -> Void
    var statistics: () -> Void = {}
    var confusions: ConfusionController? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("词隙").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Button("今日 \(store.todayCount) 词", action: statistics).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted).help("查看学习统计").accessibilityLabel("学习统计")
                Button(action: toggleMini) { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .buttonStyle(.plain).foregroundStyle(muted).help("切换迷你模式 · ⌘M").accessibilityLabel("切换迷你模式")
                Button(action: togglePin) {
                    Image(systemName: store.saved.settings.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).foregroundStyle(store.saved.settings.pinned ? accent : muted)
                    .help("始终显示在其他窗口上方；普通卡片位置可拖动").accessibilityLabel(store.saved.settings.pinned ? "取消始终置顶" : "始终置顶")
                Button(action: hide) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(muted).help("收起卡片").accessibilityLabel("收起卡片")
            }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 10)

            Divider().overlay(ink.opacity(0.04))

            HStack {
                Menu {
                    ForEach(store.books) { book in
                        Button("\(book.name) · \(book.words.count) 词") { store.selectBook(book.id) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(store.selectedBook?.name ?? "选择词库")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.font(.system(size: 12)).foregroundStyle(muted)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("切换词库")
                Spacer()
                Text("进度 \(store.processedCount)/\(store.selectedBook?.words.count ?? 0)")
                    .font(.system(size: 11)).foregroundStyle(muted)
                    .help("已学 \(store.learnedCount) 个，已掌握 \(store.masteredCount) 个")
            }.padding(.horizontal, 24).padding(.top, 10)

            VStack(spacing: 7) {
                StudyModeSwitch(selection: Binding(get: { store.mode }, set: { store.setMode($0) }))
                HStack {
                    Text(store.todayNewSummary).help(store.newCountHelp)
                    Spacer()
                    Text(store.todayReviewSummary + " · 到期 \(store.dueCount)")
                        .help(reviewCountHelp)
                }.font(.system(size: 11)).foregroundStyle(muted)
                ProgressView(value: store.dailyProgress).tint(accent)
                    .accessibilityLabel(store.mode.label + "进度")
            }.padding(.horizontal, 24).padding(.top, 10)

            if let word = store.current {
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.word).font(.system(size: 31, weight: .semibold)).tracking(-0.7)
                        .minimumScaleFactor(0.5).lineLimit(2).foregroundStyle(ink)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        if !word.phonetic.isEmpty {
                            Text("/\(word.phonetic)/").font(.system(size: 13)).foregroundStyle(muted)
                                .textSelection(.enabled)
                        }
                        Button { speak(word.word) } label: {
                            Image(systemName: "speaker.wave.2").font(.system(size: 14))
                        }.buttonStyle(.plain).foregroundStyle(accent).help("朗读单词 · 5 / ⌘P")
                            .accessibilityLabel("朗读单词，快捷键5")
                        Spacer()
                    }
                }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 12)

                ZStack {
                    if store.revealed {
                        if let confusions {
                            ConfusionMeaningView(controller: confusions, word: word, compact: false, speak: speak)
                        } else { WordDefinitionReader(word: word, compact: false, inset: 12, speak: speak) }
                    } else {
                        Text("空格揭晓词义").font(.system(size: 14)).foregroundStyle(muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.modifier(ReadingSurface()).frame(minHeight: 130, maxHeight: .infinity).padding(.horizontal, 24)

                VStack(spacing: 12) {
                    if store.revealed {
                        HStack(spacing: 8) {
                            ratingButton(.forgot, shortcut: "1")
                            ratingButton(.vague, shortcut: "2")
                            ratingButton(.knew, shortcut: "3")
                        }
                    } else {
                        Button { store.revealMeaning() } label: {
                            HStack { Spacer(); Text("显示释义").font(.system(size: 14, weight: .medium)); Spacer() }
                                .frame(height: 42)
                                .modifier(WordGapGlassSurface(tint: accent.opacity(0.10), fallback: paper, radius: 10)).foregroundStyle(accent)
                        }.buttonStyle(.plain).accessibilityLabel("显示释义")
                    }
                    HStack {
                        Button { store.undo() } label: {
                            Label("撤回", systemImage: "arrow.uturn.backward").font(.system(size: 11))
                        }.buttonStyle(.plain).disabled(!store.canUndo).foregroundStyle(muted)
                            .help("撤回上一次评分 · ⌘Z")
                        Spacer()
                        Button("已掌握  4") { store.markMastered() }
                            .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                            .help("完全掌握：退出新学和复习，可撤回或在设置中恢复")
                            .accessibilityLabel("已掌握，快捷键4")
                        Spacer()
                        Button { store.skipWord() } label: { Text("跳过  →").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(muted).help("跳过不计入学习 · →")
                    }
                }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 12)
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Text(store.emptyTitle).foregroundStyle(ink).font(.system(size: 17, weight: .semibold))
                    Text(store.emptyDetail).foregroundStyle(muted).font(.system(size: 12)).multilineTextAlignment(.center).lineSpacing(4)
                    Button(store.mode == .newWords ? "去复习" : "去新学") {
                        store.setMode(store.mode == .newWords ? .review : .newWords)
                    }.buttonStyle(.borderedProminent).tint(accent)
                    Button("调整每日新词目标", action: settings).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted)
                }.padding(24)
                Spacer()
            }

            Divider()
            HStack(spacing: 8) {
                Text(store.fileError.isEmpty ? (store.notice.isEmpty ? "每天一点，在间隙里记住" : store.notice) : store.fileError)
                    .font(.system(size: 10)).foregroundStyle(store.fileError.isEmpty ? muted : .red)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: settings) { Image(systemName: "slider.horizontal.3").font(.system(size: 13)) }
                    .buttonStyle(.plain).foregroundStyle(muted).help("偏好设置与词表导入").accessibilityLabel("偏好设置")
            }.padding(.horizontal, 24).padding(.vertical, 10)
        }.background { WordGapWindowBackdrop() }.tint(accent)
            .ignoresSafeArea(.container, edges: .top)
    }

    private func ratingButton(_ rating: Rating, shortcut: String) -> some View {
        Button { store.rate(rating) } label: {
            VStack(spacing: 3) {
                Text(rating.label).font(.system(size: 13, weight: .regular))
                Text(shortcut).font(.system(size: 9)).opacity(0.55)
            }.frame(maxWidth: .infinity).frame(height: 48)
        }.buttonStyle(AnswerButtonStyle(rating: rating, radius: 10)).accessibilityLabel(rating.label)
    }
}

private struct MiniFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct MiniFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppPalette.muted)
            .contentShape(Rectangle())
    }
}

struct MiniCardView: View {
    @ObservedObject var store: WordStore
    var speak: (String) -> Void
    var settings: () -> Void
    var hide: () -> Void
    var togglePin: () -> Void
    var toggleMini: () -> Void
    var statistics: () -> Void = {}
    var inspectLayout: (([String: CGRect]) -> Void)? = nil
    var confusions: ConfusionController? = nil

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 4) {
                HStack(spacing: 9) {
                    Menu {
                        ForEach(store.books) { book in
                            Button(book.name) { store.selectBook(book.id) }
                        }
                    } label: { Text("词隙").font(.system(size: 10, weight: .semibold)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(ink).tint(ink).accessibilityLabel("切换词库")
                    Button("今日 \(store.todayCount)", action: statistics).buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(muted).help("查看学习统计").accessibilityLabel("学习统计")
                    Spacer(minLength: 0)
                    icon(store.saved.settings.pinned ? "pin.fill" : "pin", label: store.saved.settings.pinned ? "取消始终置顶" : "在当前位置始终置顶", action: togglePin)
                        .foregroundStyle(store.saved.settings.pinned ? accent : muted)
                    icon("slider.horizontal.3", label: "偏好设置", action: settings)
                    icon("arrow.up.left.and.arrow.down.right", label: "展开普通卡片", action: toggleMini).help("展开普通卡片 · ⌘M")
                    icon("xmark", label: "收起卡片", action: hide)
                }.frame(height: 12)
                HStack(spacing: 10) {
                    StudyModeSwitch(selection: Binding(get: { store.mode }, set: { store.setMode($0) }), compact: true).frame(width: 92)
                    Spacer(minLength: 0)
                    Text(store.mode == .newWords ? store.todayNewSummary : store.todayReviewSummary)
                        .font(.system(size: 10)).foregroundStyle(muted)
                        .help((store.mode == .review ? reviewCountHelp : store.newCountHelp) + "\n总进度 \(store.processedCount)/\(store.selectedBook?.words.count ?? 0) · 到期 \(store.dueCount)")
                }.frame(height: 18)
            }.frame(height: 34)
            if let word = store.current {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(word.word).font(.system(size: 20, weight: .semibold)).tracking(-0.35)
                            .lineLimit(1).minimumScaleFactor(0.8).allowsTightening(true).truncationMode(.tail)
                            .help(word.phonetic.isEmpty ? word.word : "\(word.word) /\(word.phonetic)/")
                            .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                        if !word.phonetic.isEmpty {
                            Text("/\(word.phonetic)/")
                                .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1).truncationMode(.tail)
                                .help("/\(word.phonetic)/")
                                .frame(minWidth: 0, maxWidth: 64, alignment: .leading).layoutPriority(-1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: CardLayout.miniWordHeight)
                        .background(readingFrame("word"))
                    icon("speaker.wave.2", label: "朗读单词，快捷键5", action: { speak(word.word) }).foregroundStyle(accent).help("朗读单词 · 5 / ⌘P")
                        .frame(width: 14, height: CardLayout.miniWordHeight)
                        .background(readingFrame("speaker"))
                }.frame(height: CardLayout.miniWordHeight)
                VStack(spacing: 2) {
                    ZStack {
                        if store.revealed {
                            if let confusions {
                                ConfusionMeaningView(controller: confusions, word: word, compact: true, speak: speak)
                            } else { WordDefinitionReader(word: word, compact: true, speak: speak) }
                        } else {
                            Button { store.revealMeaning() } label: {
                                Text("空格揭晓词义").font(.system(size: 11, weight: .regular)).foregroundStyle(muted)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }.buttonStyle(.plain).accessibilityLabel("显示释义")
                        }
                    }.modifier(ReadingSurface()).frame(height: CardLayout.miniMeaningHeight).help("超长释义可按 ↑ / ↓ 翻看").background(readingFrame("meaning"))
                    HStack(spacing: 5) {
                        rating(.forgot, key: "1")
                        rating(.vague, key: "2")
                        rating(.knew, key: "3")
                    }.background { if confusions != nil { readingFrame("ratings") } }
                    footerControls
                }
            } else {
                VStack(spacing: 7) {
                    Text(store.emptyTitle).font(.system(size: 12, weight: .medium))
                    Text(store.emptyDetail).font(.system(size: 10)).foregroundStyle(muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                footerControls
            }
        }.padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(ink).background { WordGapWindowBackdrop() }.tint(accent)
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: "mini-reading")
            .onPreferenceChange(MiniFrameKey.self) { inspectLayout?($0) }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .overlay(alignment: .bottom) {
                if !store.fileError.isEmpty {
                    Text(store.fileError).font(.system(size: 10)).foregroundStyle(.red)
                        .padding(5).frame(maxWidth: .infinity).background(paper)
                }
            }
    }

    private var footerControls: some View {
        HStack(spacing: 5) {
            Button { store.undo() } label: {
                Text("撤回").frame(maxWidth: .infinity)
            }.disabled(!store.canUndo).help(store.canUndo ? "撤回 · ⌘Z" : "暂无可撤回的操作")
            Button { store.markMastered() } label: {
                Text("掌握 4").frame(maxWidth: .infinity)
            }.disabled(store.current == nil).accessibilityLabel("已掌握，快捷键4")
            Button { store.skipWord() } label: {
                Text("跳过 →").frame(maxWidth: .infinity)
            }.disabled(store.current == nil)
        }.buttonStyle(MiniFooterButtonStyle()).font(.system(size: 9)).frame(height: CardLayout.miniFooterHeight)
    }

    @ViewBuilder private func readingFrame(_ name: String) -> some View {
        if inspectLayout != nil {
            GeometryReader { proxy in
                Color.clear.preference(key: MiniFrameKey.self, value: [name: proxy.frame(in: .named("mini-reading"))])
            }
        }
    }

    private func icon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10)) }
            .buttonStyle(InstantIconStyle()).accessibilityLabel(label).help(label)
    }
    private func rating(_ value: Rating, key: String) -> some View {
        Button { store.rate(value) } label: {
            HStack(spacing: 4) {
                Text(value.label).font(.system(size: 10, weight: .regular))
                Text(key).font(.system(size: 8)).monospacedDigit().opacity(0.75)
            }.frame(maxWidth: .infinity).frame(height: CardLayout.miniRatingHeight)
        }.buttonStyle(AnswerButtonStyle(rating: value, radius: 6)).disabled(!store.revealed).opacity(store.revealed ? 1 : 0.55)
            .accessibilityLabel(value.label).help("空格揭晓后按 " + key + " 评分")
    }
}

struct SettingsActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .modifier(WordGapGlassSurface(tint: accent.opacity(0.08), fallback: paper, radius: 8))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                configuration.label.foregroundStyle(ink)
                Spacer(minLength: 8)
                Capsule().fill(configuration.isOn ? accent : muted.opacity(0.24))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(Color.white.opacity(0.85)).frame(width: 14, height: 14)
                            .modifier(WordGapGlassSurface(tint: nil, fallback: .white, radius: 7)).padding(2)
                    }
            }.frame(minHeight: 26).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
            }
    }
}

struct SettingsView: View {
    @ObservedObject var store: WordStore
    @State private var dailyGoalText = ""
    @FocusState private var editingDailyGoal: Bool
    var back: () -> Void
    var importWords: () -> Void
    var exportProgress: () -> Void
    var manageMastered: () -> Void
    var statistics: () -> Void = {}
    var quit: () -> Void
    var manageBooks: () -> Void = {}
    var previewGlass: () -> Void = {}
    var quickAdd: () -> Void = {}
    var confusions: ConfusionController? = nil
    @State private var glassDirty = false
    @State private var draggingGlass = false
    @State private var glassSave: DispatchWorkItem?

    func binding<T>(_ path: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { store.saved.settings[keyPath: path] }, set: { store.saved.settings[keyPath: path] = $0; store.settingsChanged() })
    }

    private func setDailyGoal(_ value: Int) {
        let goal = min(500, max(1, value))
        dailyGoalText = String(goal)
        guard goal != store.saved.settings.dailyNewGoal else { return }
        store.saved.settings.dailyNewGoal = goal; store.settingsChanged()
    }
    private func commitDailyGoal() {
        let value = Int(dailyGoalText.trimmingCharacters(in: .whitespacesAndNewlines))
        setDailyGoal(value ?? store.saved.settings.dailyNewGoal)
    }
    private func adjustDailyGoal(_ amount: Int) {
        let typed = Int(dailyGoalText.trimmingCharacters(in: .whitespacesAndNewlines))
        let base = min(500, max(1, typed ?? store.saved.settings.dailyNewGoal))
        setDailyGoal(base + amount)
    }
    private func changeGlassIntensity(_ value: Double) {
        store.saved.settings.glassIntensity = min(1, max(0, value))
        glassDirty = true
        GlassAppearanceState.shared.apply(enabled: store.saved.settings.glassEnabled, intensity: store.saved.settings.glassIntensity)
        previewGlass()
        glassSave?.cancel()
        if !draggingGlass {
            let save = DispatchWorkItem { commitGlassSettings() }
            glassSave = save; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: save)
        }
    }
    private func commitGlassSettings() {
        glassSave?.cancel(); glassSave = nil
        guard glassDirty else { return }
        glassDirty = false; store.settingsChanged()
    }

    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { commitDailyGoal(); commitGlassSettings(); back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24).foregroundStyle(ink)
                }.buttonStyle(.plain).accessibilityLabel("返回单词卡片")
                Text("偏好设置").font(.system(size: 14, weight: .semibold))
                Spacer()
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            ChoiceStrip(selection: $page, options: [("学习", 0), ("卡片与声音", 1), ("数据与词库", 2)], label: "设置分类")
                .padding(.horizontal, 12).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if page == 0 { learningSettings }
                    else if page == 1 { cardAndSoundSettings }
                    else { dataSettings }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }.id(page)
        }.background { WordGapWindowBackdrop() }.foregroundStyle(ink).font(.system(size: 12))
            .tint(accent).controlSize(.small).toggleStyle(SettingsSwitchStyle())
            .ignoresSafeArea(.container, edges: .top)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .onAppear { dailyGoalText = String(store.saved.settings.dailyNewGoal) }
            .onChange(of: store.saved.settings.dailyNewGoal) { dailyGoalText = String($0) }
            .onChange(of: editingDailyGoal) { if !$0 { commitDailyGoal() } }
            .onChange(of: page) { _ in commitDailyGoal(); commitGlassSettings(); editingDailyGoal = false }
            .onDisappear { commitDailyGoal(); commitGlassSettings() }
    }

    private var learningSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("每日新学目标") {
                HStack(spacing: 8) {
                    Text("每天新学")
                    Spacer(minLength: 0)
                    goalStep(-20, symbol: "minus", label: "新学目标减20个")
                    TextField("词数", text: $dailyGoalText)
                        .textFieldStyle(.plain).multilineTextAlignment(.center)
                        .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        .frame(width: 54, height: 32)
                        .focused($editingDailyGoal).onSubmit { commitDailyGoal() }
                        .accessibilityLabel("每日新学单词数量").help("输入1–500，按回车或离开输入框保存")
                    goalStep(20, symbol: "plus", label: "新学目标加20个")
                    Text("词").foregroundStyle(muted)
                }
                HStack {
                    Text(store.todayNewSummary).help(store.newCountHelp)
                    Spacer()
                    Text(store.todayReviewSummary).help(reviewCountHelp)
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(muted)
                ProgressView(value: store.newStudyProgress)
                    .tint(accent)
                note("每次加减20词，也可直接输入。复习按到期数量安排。")
            }
            if let confusions { section("易混词辨析") { ConfusionPreference(controller: confusions) } }
            section("出词顺序") {
                ChoiceStrip(selection: Binding(get: { store.saved.settings.wordOrder }, set: { store.setWordOrder($0) }),
                            options: WordOrder.allCases.map { ($0.label, $0) }, label: "出词顺序")
                note("随机顺序不重复抽到本轮已看过的词；复习只出到期词。")
            }
            section("复习安排") {
                scheduleRow("不认识", "10分钟后")
                scheduleRow("模糊", "30分钟后")
                scheduleRow("认识", "逐步延长到1–120天")
                note("认识间隔：1、3、7、14、30、60、120天。")
            }
        }
    }

    private var cardAndSoundSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("卡片") {
                Toggle("迷你模式", isOn: binding(\.miniMode))
                Toggle("在当前位置始终置顶", isOn: binding(\.pinned))
                note("迷你卡片位于菜单栏单词下方；⌘K 显示 / 收起。")
            }
            section("外观") {
                ChoiceStrip(selection: binding(\.appearance), options: AppAppearance.allCases.map { ($0.label, $0) }, label: "外观模式")
            }
            section("液态玻璃") {
                Toggle("液态玻璃效果", isOn: binding(\.glassEnabled))
                HStack {
                    Text("玻璃程度")
                    Spacer()
                    Text("\(Int((store.saved.settings.glassIntensity * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(muted)
                }.font(.system(size: 11))
                Slider(value: Binding(get: { store.saved.settings.glassIntensity }, set: changeGlassIntensity), in: 0...1, step: 0.05) { editing in
                    draggingGlass = editing
                    if editing { glassSave?.cancel() } else { commitGlassSettings() }
                }.disabled(!store.saved.settings.glassEnabled).accessibilityLabel("液态玻璃程度")
                note("较低更厚实，较高更通透。背词、设置、管理和统计页同时生效。")
            }
            section("声音") {
                Toggle("每个单词自动发音", isOn: binding(\.autoSpeak))
                Toggle("评分提示音", isOn: binding(\.feedbackSound))
                ChoiceStrip(selection: binding(\.british), options: [("美音", false), ("英音", true)], label: "发音")
                note("提示音结束后再读下一词；5 / ⌘P 重播发音。")
            }
            section("菜单栏轮换") {
                Toggle("收起卡片后自动换词", isOn: binding(\.autoRotate))
                HStack {
                    Text("轮换间隔").foregroundStyle(muted)
                    Spacer()
                    SelectionMenu(selection: binding(\.rotateSeconds), options: [("30秒", 30), ("1分钟", 60), ("2分钟", 120), ("5分钟", 300), ("10分钟", 600)], label: "轮换间隔")
                        .frame(width: 126).disabled(!store.saved.settings.autoRotate)
                }
                note("卡片打开时暂停轮换，轮换不计入学习。")
            }
        }
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("学习数据") {
                SettingsActionRow(title: "打开学习统计", subtitle: "日 / 周记录、趋势、明细与CSV导出", action: statistics)
            }
            section("词库与单词") {
                SettingsActionRow(title: "快捷添加生词", subtitle: "⌘⇧K · 已有词复用，未收录词用 DeepSeek 补全", action: quickAdd)
                Divider().opacity(0.4)
                SettingsActionRow(title: "管理 / 删除词库", subtitle: "删除后可恢复，学习记录保留", action: manageBooks)
                Divider().opacity(0.4)
                SettingsActionRow(title: "导入词库", subtitle: "CSV / TSV，前两列为单词与释义", action: importWords)
                Divider().opacity(0.4)
                SettingsActionRow(title: "管理已掌握单词", subtitle: "当前词库已掌握 \(store.masteredCount) 词", action: manageMastered)
            }
            section("本机备份") {
                SettingsActionRow(title: "导出学习记录与词库", subtitle: "保存完整JSON备份", action: exportProgress)
                note("学习记录仅保存在本机；掌握的词不占每日新词名额。")
            }
            section("关于词隙") {
                note("免费使用 · 无内购 · 无账号\n词库：ECDICT / MIT · 发音：macOS系统语音")
                SettingsActionRow(title: "退出词隙", action: quit)
            }
        }
    }

    private func goalStep(_ amount: Int, symbol: String, label: String) -> some View {
        Button { adjustDailyGoal(amount) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26).contentShape(Rectangle()).modifier(QuietSurface(radius: 8))
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
    private func scheduleRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(muted) }.font(.system(size: 11))
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink)
            content()
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).modifier(QuietSurface())
    }
}

struct MasteredView: View {
    @ObservedObject var store: WordStore
    var back: () -> Void
    @State private var search = ""
    var results: [Word] {
        store.masteredWords.filter { search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) || $0.meaning.contains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24).foregroundStyle(accent)
                }.buttonStyle(.plain).accessibilityLabel("返回偏好设置")
                Text("已掌握单词").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(store.masteredCount) 词").foregroundStyle(muted).font(.system(size: 11))
            }
            TextField("搜索单词或释义", text: $search).textFieldStyle(.roundedBorder)
            Text("已掌握的词不会出现在新学或复习中。恢复后会回到原来的学习队列。")
                .font(.system(size: 11)).foregroundStyle(muted).lineSpacing(2)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(results) { word in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(word.word).font(.system(size: 14, weight: .medium))
                                Text(word.meaning).font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
                            }
                            Spacer()
                            Button("恢复") { store.restoreMastered(word.id) }.buttonStyle(SettingsActionButtonStyle())
                        }
                        Divider()
                    }
                    if results.isEmpty { Text("没有匹配的已掌握单词").font(.system(size: 12)).foregroundStyle(muted).padding(.top, 30) }
                }
            }
        }.padding(12).background { WordGapWindowBackdrop() }.foregroundStyle(ink).tint(accent)
            .ignoresSafeArea(.container, edges: .top)
    }
}
