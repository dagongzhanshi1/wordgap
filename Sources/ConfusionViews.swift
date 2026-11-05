import SwiftUI

struct WordDefinitionReader: View {
    let word: Word
    let compact: Bool
    var inset: CGFloat = 6
    var speak: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 7 : 14) {
                Text(word.meaning).font(.system(size: compact ? 10.5 : 15)).lineSpacing(compact ? 1 : 6)
                    .foregroundStyle(AppPalette.ink).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !word.example.isEmpty {
                    Divider()
                    if compact {
                        Text(word.example).font(.system(size: 11)).textSelection(.enabled)
                        if !word.exampleTranslation.isEmpty { Text(word.exampleTranslation).font(.system(size: 10)).foregroundStyle(AppPalette.muted) }
                        Button("朗读例句") { speak(word.example) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(AppPalette.accent)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Text(word.example).font(.system(size: 13)).lineSpacing(5).foregroundStyle(AppPalette.ink.opacity(0.85)).textSelection(.enabled)
                            Button { speak(word.example) } label: { Image(systemName: "speaker.wave.2") }
                                .buttonStyle(.plain).foregroundStyle(AppPalette.accent).accessibilityLabel("朗读例句")
                        }
                        if !word.exampleTranslation.isEmpty { Text(word.exampleTranslation).font(.system(size: 12)).foregroundStyle(AppPalette.muted).lineSpacing(4) }
                    }
                }
            }.padding(.vertical, inset)
        }
    }
}

struct ConfusionMeaningView: View {
    @ObservedObject var controller: ConfusionController
    let word: Word
    let compact: Bool
    var speak: (String) -> Void
    private var matching: Bool { controller.enabled && controller.matches(word) }
    var body: some View {
        if matching && controller.filtering { picker }
        else {
            VStack(spacing: compact ? 2 : 8) {
                WordDefinitionReader(word: word, compact: compact, inset: matching && controller.selected != nil ? 1 : (compact ? 6 : 12), speak: speak)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if matching, let item = controller.selected {
                    comparison(item)
                } else if matching && controller.loading {
                    Text("易混词准备中…").font(.system(size: compact ? 8 : 10)).foregroundStyle(AppPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
                } else if matching && !controller.error.isEmpty {
                    HStack { Text(controller.error).lineLimit(1); Spacer(minLength: 0); Button("重试") { controller.retry() }.buttonStyle(.plain) }
                        .font(.system(size: compact ? 8 : 10)).foregroundStyle(AppPalette.muted)
                } else if matching && controller.entry == nil {
                    Button("易混词 ⌘B") { controller.request() }.buttonStyle(.plain)
                        .font(.system(size: compact ? 8 : 10)).foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).help("按需生成易混词辨析，不会自动请求")
                } else if matching, let entry = controller.entry, entry.suggestions.isEmpty {
                    Text(ConfusionInput.noneMessage).font(.system(size: compact ? 8.5 : 11, weight: .medium))
                        .foregroundStyle(AppPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
                } else if matching, let entry = controller.entry, !entry.excluded.isEmpty {
                    HStack { Text("本词候选已排除"); Spacer(); Button("管理 ⌘B") { controller.toggleFilter() }.buttonStyle(.plain) }
                        .font(.system(size: compact ? 8 : 10)).foregroundStyle(AppPalette.muted)
                }
            }
        }
    }
    private func comparison(_ item: ConfusionSuggestion) -> some View {
        let retained = controller.entry?.chosen == item.id
        let detail = "AI 辨析 · \(item.word)：\(item.meaning)\n\(item.difference)\n⌘B 筛选，保留或排除"
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text("\(item.kind.title) · \(item.word)").font(.system(size: compact ? 8.5 : 11, weight: .medium)).foregroundStyle(AppPalette.accent).lineLimit(1)
                Spacer(minLength: 2)
                Button(retained ? "已保留 · 筛选" : "筛选 ⌘B") { controller.toggleFilter() }
                    .buttonStyle(.plain).font(.system(size: compact ? 8 : 10)).foregroundStyle(AppPalette.muted)
            }
            Text(item.difference).font(.system(size: compact ? 8.5 : 11, weight: .medium)).foregroundStyle(AppPalette.muted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, compact ? 2 : 6).frame(maxWidth: .infinity, alignment: .leading).help(detail)
    }
    private var picker: some View {
        VStack(spacing: compact ? 1 : 8) {
            if let item = controller.focused {
                HStack(spacing: 3) {
                    Text(item.word).font(.system(size: compact ? 10 : 14, weight: .medium)).foregroundStyle(AppPalette.accent).lineLimit(1).minimumScaleFactor(0.8)
                    Text(item.meaning).font(.system(size: compact ? 8.5 : 11)).lineLimit(1).foregroundStyle(AppPalette.muted)
                    Spacer(minLength: 0)
                    Text("\((controller.entry?.available.firstIndex { $0.id == item.id } ?? 0) + 1)/\(controller.entry?.available.count ?? 0)")
                        .font(.system(size: compact ? 8 : 10)).monospacedDigit().foregroundStyle(AppPalette.muted)
                }.help(item.word + " · " + item.meaning)
                ScrollView { Text(item.kind.title + " · " + item.difference).font(.system(size: compact ? 9 : 12, weight: .medium)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: compact ? 8 : 12) {
                    Button("保留 ↵") { controller.keep() }.foregroundStyle(AppPalette.accent)
                    Button("换一个 Tab") { controller.cycle() }
                    Button("排除 ⌫") { controller.exclude() }
                    Spacer(minLength: 0)
                    Button("返回") { controller.filtering = false }.help("返回词义 · ⌘B / Esc")
                }.buttonStyle(.plain).font(.system(size: compact ? 8 : 11)).foregroundStyle(AppPalette.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(controller.loading ? "正在准备候选…" : (controller.entry?.suggestions.isEmpty == false && controller.entry?.excluded.isEmpty == false ? "本词的候选已全部排除" : ConfusionInput.noneMessage))
                    .font(.system(size: compact ? 9 : 12)).foregroundStyle(AppPalette.muted)
                HStack {
                    if let entry = controller.entry, !entry.suggestions.isEmpty, !entry.excluded.isEmpty { Button("恢复本词候选") { controller.restoreCandidates() } }
                    Button("返回词义") { controller.filtering = false }
                }.buttonStyle(.plain).font(.system(size: compact ? 9 : 11)).foregroundStyle(AppPalette.accent)
            }
        }.padding(.vertical, compact ? 2 : 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ConfusionPreference: View {
    @ObservedObject var controller: ConfusionController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("启用易混词辨析", isOn: Binding(get: { controller.enabled }, set: controller.setEnabled))
            Text("揭晓后按⌘B才生成，不会自动请求；已有结果时按⌘B筛选。回车保留、Tab换一个、删除键排除。筛选结果在本机保存，不影响评分和复习。").font(.system(size: 10)).foregroundStyle(AppPalette.muted)
            Text("使用快捷加词中配置的 DeepSeek Key，按账户规则计费。按需发送当前词、释义和最多6个本机拼写候选；结果缓存复用，生成期间可照常背词。").font(.system(size: 10)).foregroundStyle(AppPalette.muted)
        }
    }
}
