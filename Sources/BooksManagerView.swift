import SwiftUI

struct BooksManagerView: View {
    @ObservedObject var store: WordStore
    var back: () -> Void
    var importWords: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24).foregroundStyle(AppPalette.accent)
                }.buttonStyle(.plain).accessibilityLabel("返回偏好设置")
                Text("词库管理").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("导入…", action: importWords).buttonStyle(SettingsActionButtonStyle())
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("删除后不再出词，学习记录与统计保留。词库会移入下方的「已删除词库」，可随时恢复。")
                        .font(.system(size: 11)).foregroundStyle(AppPalette.muted).lineSpacing(2)
                    Text("可用词库 · \(store.books.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.accent)
                    if store.books.isEmpty {
                        Text("没有可用词库，请导入新词库或恢复已删除词库。")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    ForEach(store.books) { book in
                        row(book, archived: false)
                    }
                    if !store.archivedBooks.isEmpty {
                        Divider()
                        Text("已删除词库 · \(store.archivedBooks.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.accent)
                        ForEach(store.archivedBooks) { book in row(book, archived: true) }
                    }
                    if !store.notice.isEmpty {
                        Text(store.notice).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    if !store.fileError.isEmpty { Text(store.fileError).font(.system(size: 11)).foregroundStyle(.red) }
                }.padding(12)
            }
        }.background { WordGapWindowBackdrop() }.foregroundStyle(AppPalette.ink).tint(AppPalette.accent)
            .ignoresSafeArea(.container, edges: .top)
    }

    private func row(_ book: Book, archived: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(book.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text("\(book.words.count.formatted()) 词 · " + (book.isCustom ? "导入词库" : "内置词库") +
                     (store.saved.settings.bookID == book.id ? " · 当前使用" : ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if let date = store.saved.archivedBookDates[book.id] {
                    Text("删除于 " + StudyStatistics.label(date, format: "M/d HH:mm"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if archived {
                Button("恢复") { store.restoreBook(book.id) }.buttonStyle(SettingsActionButtonStyle())
                    .accessibilityLabel("恢复词库：" + book.name)
            } else {
                Button("删除") { store.deleteBook(book.id) }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.red)
                    .accessibilityLabel("删除词库：" + book.name).help("移入已删除词库，保留学习记录")
            }
        }.padding(13).background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 10))
    }
}
