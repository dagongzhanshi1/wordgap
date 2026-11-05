import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Carbon

final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = WordStore()
    lazy var confusions = ConfusionController(library: { [weak self] in self?.store.selectedBook?.words ?? [] })
    var item: NSStatusItem!
    var panel: CardPanel!
    var timer: Timer?
    var keyboardMonitor: Any?
    var interactionMonitor: Any?
    var statisticsWindow: NSWindow?
    let cardHotKey = CardHotKey()
    let quickHotKey = CardHotKey(id:2,modifiers:UInt32(cmdKey | shiftKey))
    var quickAddModel: QuickAddModel?
    var quickAddVisible = false
    var quickAddNeedsFocus = false
    var cardShortcutStatus: OSStatus = -1
    var quickShortcutStatus: OSStatus = -1
    var settingsVisible = false
    var displayedMiniMode = false
    var regularCardFrame: NSRect?
    var miniPlacement = MiniCardPlacement()
    var cardContentInstalled = false
    var lastPinnedState: Bool?
    var speaker = NSSpeechSynthesizer()
    var lastRotation = Date()
    var pendingPanelOpen: DispatchWorkItem?
    var lastAutomaticPresentation: UUID?
    let answerFeedback = AnswerFeedbackController()
    lazy var pronunciationQueue = CardPronunciationQueue(feedbackIsPlaying: { [weak self] in
        self?.answerFeedback.isSoundPlaying ?? false
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.saved.settings.miniMode = true
        store.persist()
        installApplicationMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        item.button?.toolTip = "词隙 · 点击打开小卡片，右键打开菜单"
        panel = CardPanel(contentRect: NSRect(origin: .zero, size: CardLayout.regularSize),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        panel.title = "词隙"
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.setFrameAutosaveName("WordGapCard")
        panel.setContentSize(CardLayout.regularSize)
        if UserDefaults.standard.string(forKey: "NSWindow Frame WordGapCard") == nil { positionNearStatusItem() }
        store.onWordChanged = { [weak self] in
            guard let self else { return }
            self.updateStatus(); self.applySettings(); self.autoSpeakCurrentIfNeeded(); self.syncConfusions()
        }
        store.onAnswerFeedback = { [weak self] kind in
            guard let self, self.panel.isVisible, !self.settingsVisible, let host = self.panel.contentView else { return }
            self.speaker.stopSpeaking()
            self.answerFeedback.show(kind, in: cardFeedbackHost(host), soundEnabled: self.store.saved.settings.feedbackSound)
        }
        answerFeedback.onSoundFinished = { [weak self] in self?.pronunciationQueue.feedbackDidFinish() }
        updateStatus()
        showCardContent(); applySettings()
        cardHotKey.onPressed = { [weak self] in self?.toggleCard() }
        cardShortcutStatus = cardHotKey.register()
        if cardShortcutStatus != 0 {
            store.notice = "⌘K 注册失败，可能已被其他软件占用；仍可点击菜单栏打开卡片。"
        }
        quickHotKey.onPressed = { [weak self] in self?.openQuickAdd() }
        quickShortcutStatus = quickHotKey.register()
        if quickShortcutStatus != 0 { store.notice = "⌘⇧K 加词快捷键被占用，可从右键菜单打开快捷加词。" }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, !self.settingsVisible else { return event }
            // Do not steal keystrokes from an editable text field or another window.
            if let text = self.panel.firstResponder as? NSTextView, text.isEditable { return event }
            if event.isARepeat { return nil }
            self.store.interact()
            if self.store.revealed, let word = self.store.current, self.confusions.matches(word), self.confusions.handle(event) { return nil }
            let command = event.modifierFlags.contains(.command)
            if event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command] {
                if event.charactersIgnoringModifiers == "1" { self.newMode(); return nil }
                if event.charactersIgnoringModifiers == "2" { self.reviewMode(); return nil }
            }
            if command && event.charactersIgnoringModifiers == "p" { self.speakCurrent(); return nil }
            if command && event.charactersIgnoringModifiers == "z" { self.store.undo(); return nil }
            if command && event.charactersIgnoringModifiers == "m" { self.toggleMini(); return nil }
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            if self.displayedMiniMode && self.store.revealed && (event.keyCode == 125 || event.keyCode == 126) {
                self.scrollMiniMeaning(down: event.keyCode == 125)
                return nil
            }
            if let action = CardShortcut.action(for: event.keyCode) {
                switch action {
                case .close: self.hidePanel()
                case .reveal: self.store.revealMeaning()
                case .skip: self.store.skipWord()
                case .mastered: self.store.markMastered()
                case .speak: self.speakCurrent()
                case .rate(let rating):
                    if self.store.revealed { self.store.rate(rating) }
                }
                return nil
            }
            return event
        }
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
            if let self, self.panel.isKeyWindow, !self.settingsVisible { self.store.interact() }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.store.refreshDay()
            self.store.tickStudyTime(isActive: self.panel.isVisible && self.panel.isKeyWindow && NSApp.isActive && !self.settingsVisible)
            if self.panel.isVisible || !self.store.pendingQuickTasks.isEmpty { self.lastRotation = Date(); return }
            guard self.store.saved.settings.autoRotate else { return }
            if Date().timeIntervalSince(self.lastRotation) >= Double(self.store.saved.settings.rotateSeconds) {
                self.lastRotation = Date(); self.store.next()
            }
        }
        // Wait until the status item's title has established its menu-bar frame.
        // Keep the panel hidden until its first placement is below that word.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.miniPlacement = MiniCardPlacement()
            if !CommandLine.arguments.contains("--background") { self.showPanel() }
            self.recordQuickRuntime()
        }
    }

    func installApplicationMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "词隙")
        let card = NSMenuItem(title: "显示 / 收起单词卡片", action: #selector(toggleCard), keyEquivalent: "k")
        card.target = self; appMenu.addItem(card)
        let quick = NSMenuItem(title:"快捷加词…",action:#selector(openQuickAdd),keyEquivalent:"k"); quick.keyEquivalentModifierMask = [.command,.shift]; quick.target = self; appMenu.addItem(quick)
        let stats = NSMenuItem(title: "学习统计…", action: #selector(showStatistics), keyEquivalent: "")
        stats.target = self; appMenu.addItem(stats)
        let books = NSMenuItem(title: "管理 / 删除词库…", action: #selector(showBooksManager), keyEquivalent: "")
        books.target = self; appMenu.addItem(books)
        let prefs = NSMenuItem(title: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self; appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出词隙", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu; bar.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        // Native file dialogs and text fields route Command-V/A through this responder-chain menu.
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                       ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu; bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    func applySettings() {
        guard panel != nil else { return }
        store.saved.settings.appearance.apply(to: NSApp, windows: [panel, statisticsWindow].compactMap { $0 })
        GlassAppearanceState.shared.apply(enabled: store.saved.settings.glassEnabled, intensity: store.saved.settings.glassIntensity)
        for window in [panel, statisticsWindow].compactMap({ $0 }) {
            (window.contentView as? LiquidCardHost)?.apply(enabled: store.saved.settings.glassEnabled, intensity: store.saved.settings.glassIntensity)
        }
        if !store.saved.settings.feedbackSound { answerFeedback.stopSound() }
        if !store.saved.settings.autoSpeak { lastAutomaticPresentation = nil; pronunciationQueue.cancel(); speaker.stopSpeaking() }
        let level: NSWindow.Level = store.saved.settings.pinned ? .floating : .normal
        if panel.level != level { panel.level = level }
        if !settingsVisible && displayedMiniMode != store.saved.settings.miniMode {
            showCardContent()
            if panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        }
        if lastPinnedState != store.saved.settings.pinned && store.saved.settings.pinned && displayedMiniMode && !settingsVisible {
            positionNearStatusItem()
        }
        lastPinnedState = store.saved.settings.pinned
    }

    func updateStatus() {
        let word = store.current?.word ?? "单词"
        let title = word.count > 22 ? String(word.prefix(21)) + "…" : word
        if item?.button?.title != title { item?.button?.title = title }
        item?.button?.setAccessibilityLabel("词隙：" + word)
    }

    @discardableResult func positionNearStatusItem() -> Bool {
        guard let button = item?.button, let window = button.window, let screen = window.screen else { return false }
        window.contentView?.layoutSubtreeIfNeeded()
        let visible = screen.visibleFrame
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard CardLayout.isMenuBarAnchor(buttonRect, visible: visible) else {
            recordPlacement(anchor: buttonRect, visible: visible, state: "waiting")
            return false
        }
        let origin: NSPoint
        if displayedMiniMode && !settingsVisible {
            guard let placed = miniPlacement.origin(size: panel.frame.size, below: buttonRect, visible: visible, settlingTime: 0.20) else {
                recordPlacement(anchor: buttonRect, visible: visible, state: "settling")
                return false
            }
            origin = placed
        } else { origin = CardLayout.origin(size: panel.frame.size, below: buttonRect, visible: visible) }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        recordPlacement(anchor: buttonRect, visible: visible, state: "ready")
        return true
    }

    func recordPlacement(anchor: NSRect?, visible: NSRect, state: String) {
        func values(_ rect: NSRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height] }
        var diagnostic: [String: Any] = ["state": state, "visible": values(visible), "panel": values(panel.frame),
            "mini": displayedMiniMode, "time": ISO8601DateFormatter().string(from: Date())]
        if let anchor { diagnostic["anchor"] = values(anchor) }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WordGap")
        if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("placement-diagnostic.json"), options: .atomic)
        }
    }

    func showCardContent() {
        if quickAddVisible {
            quickAddModel?.cancel(); quickAddVisible = false; quickAddNeedsFocus = false
            // Release the input field editor so Space/1/2/3 immediately reach the study card.
            panel.makeFirstResponder(nil)
        }
        if cardContentInstalled && !settingsVisible && displayedMiniMode == store.saved.settings.miniMode { syncConfusions(); return }
        if cardContentInstalled && !settingsVisible && !displayedMiniMode { regularCardFrame = panel.frame }
        settingsVisible = false
        displayedMiniMode = store.saved.settings.miniMode
        panel.isMovableByWindowBackground = !displayedMiniMode
        // Mini/settings positions must not overwrite the user's regular card placement.
        panel.setFrameAutosaveName(displayedMiniMode ? "" : "WordGapCard")
        panel.setContentSize(displayedMiniMode ? CardLayout.miniSize : CardLayout.regularSize)
        if displayedMiniMode { positionNearStatusItem() }
        else if let frame = regularCardFrame { panel.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY)) }
        else { positionNearStatusItem() }
        let read: (String) -> Void = { [weak self] in self?.speak($0) }
        let settings: () -> Void = { [weak self] in self?.showSettings() }
        let hide: () -> Void = { [weak self] in self?.hidePanel() }
        let statistics: () -> Void = { [weak self] in self?.showStatistics() }
        let pin: () -> Void = { [weak self] in
            guard let self else { return }; self.store.saved.settings.pinned.toggle(); self.store.settingsChanged()
        }
        let mini: () -> Void = { [weak self] in self?.toggleMini() }
        let content: AnyView = displayedMiniMode
            ? AnyView(MiniCardView(store: store, speak: read, settings: settings, hide: hide, togglePin: pin, toggleMini: mini, statistics: statistics, confusions: confusions))
            : AnyView(CardView(store: store, speak: read, settings: settings, hide: hide, togglePin: pin, toggleMini: mini, statistics: statistics, confusions: confusions))
        panel.contentView = glassCardHost(content)
        cardContentInstalled = true
        if panel.isKeyWindow { store.startStudyTiming() }
        autoSpeakCurrentIfNeeded()
        syncConfusions()
    }

    func syncConfusions() { confusions.present(store.current, active: panel?.isVisible == true && !settingsVisible) }

    func showPanel(placementAttempt: Int = 0) {
        if displayedMiniMode && !settingsVisible && !positionNearStatusItem() {
            if placementAttempt < 40 {
                pendingPanelOpen?.cancel()
                let retry = DispatchWorkItem { [weak self] in self?.showPanel(placementAttempt: placementAttempt + 1) }
                pendingPanelOpen = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: retry)
                return
            }
            if let screen = item?.button?.window?.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                let fallback = NSRect(x: visible.maxX - 180, y: visible.maxY, width: 100, height: 24)
                panel.setFrameOrigin(CardLayout.origin(size: panel.frame.size, below: fallback, visible: visible, gap: 1))
                recordPlacement(anchor: nil, visible: visible, state: "fallback")
            }
        }
        pendingPanelOpen?.cancel(); pendingPanelOpen = nil
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if displayedMiniMode && !settingsVisible { positionNearStatusItem() }
        if !settingsVisible { store.startStudyTiming() }
        autoSpeakCurrentIfNeeded(force: true)
        lastRotation = Date()
        syncConfusions()
    }

    func showSettings() {
        quickAddModel?.cancel(); quickAddVisible = false
        pronunciationQueue.cancel(); speaker.stopSpeaking(); answerFeedback.clear()
        store.pauseStudyTiming()
        if !settingsVisible && !displayedMiniMode { regularCardFrame = panel.frame }
        let wasMini = displayedMiniMode
        settingsVisible = true
        displayedMiniMode = false
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("")
        panel.setContentSize(CardLayout.settingsSize)
        if wasMini { positionNearStatusItem() }
        panel.contentView = glassCardHost(SettingsView(store: store,
            back: { [weak self] in self?.showCardContent() },
            importWords: { [weak self] in self?.importWords() },
            exportProgress: { [weak self] in self?.exportProgress() },
            manageMastered: { [weak self] in self?.showMastered() },
            statistics: { [weak self] in self?.showStatistics() },
            quit: { NSApp.terminate(nil) },
            manageBooks: { [weak self] in self?.showBooksManager() },
            previewGlass: { [weak self] in self?.applySettings() },
            quickAdd: { [weak self] in self?.openQuickAdd() }, confusions: confusions))
        showPanel()
    }

    func showMastered() {
        settingsVisible = true
        panel.contentView = glassCardHost(MasteredView(store: store, back: { [weak self] in self?.showSettings() }))
        showPanel()
    }
    @objc func showBooksManager() {
        showSettings()
        panel.contentView = glassCardHost(BooksManagerView(store: store,
            back: { [weak self] in self?.showSettings() }, importWords: { [weak self] in self?.importWords() }))
    }

    func speakCurrent() { if let word = store.current { speak(word.word) } }
    func autoSpeakCurrentIfNeeded(force: Bool = false) {
        guard store.saved.settings.autoSpeak, panel.isVisible, !settingsVisible, let word = store.current else {
            pronunciationQueue.cancel()
            return
        }
        guard force || lastAutomaticPresentation != store.presentationID else { return }
        lastAutomaticPresentation = store.presentationID
        requestPronunciation(word.word, automatic: true)
    }
    func scrollMiniMeaning(down: Bool) {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews { if let scroll = find(child) { return scroll } }
            return nil
        }
        guard let root = panel.contentView, let scroll = find(root), let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let maximum = max(0, document.bounds.height - clip.bounds.height)
        let step = max(20, clip.bounds.height - 8) * (down ? 1.0 : -1.0) * (document.isFlipped ? 1.0 : -1.0)
        var point = clip.bounds.origin
        point.y = min(maximum, max(0, point.y + step))
        clip.scroll(to: point)
        scroll.reflectScrolledClipView(clip)
    }
    func speak(_ text: String) {
        requestPronunciation(text, automatic: false)
    }
    private func requestPronunciation(_ text: String, automatic: Bool) {
        speaker.stopSpeaking()
        let presentation = store.presentationID
        pronunciationQueue.request { [weak self] in
            guard let self, self.store.presentationID == presentation,
                  !automatic || (self.panel.isVisible && !self.settingsVisible && self.store.saved.settings.autoSpeak) else { return }
            self.playPronunciation(text)
        }
    }
    private func playPronunciation(_ text: String) {
        guard let voice = EnglishVoice.installed(british: store.saved.settings.british),
              speaker.setVoice(voice) else {
            store.notice = "请在系统设置 → 辅助功能 → 朗读内容中下载 Samantha 或 Daniel 英语语音。"
            return
        }
        speaker.rate = 150
        speaker.volume = CardAudioLevels.pronunciation
        if speaker.startSpeaking(text) { store.recordPronunciation() }
        else { store.notice = "未能播放，请在系统设置中检查英语语音。" }
    }

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if panel.isVisible { hidePanel() }
        else { if settingsVisible { showCardContent() }; showPanel() }
    }

    func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        let card = NSMenuItem(title: "显示 / 收起单词卡片", action: #selector(toggleCard), keyEquivalent: "k")
        card.target = self; menu.addItem(card)
        let quick = NSMenuItem(title:"快捷加词…",action:#selector(openQuickAdd),keyEquivalent:"k"); quick.keyEquivalentModifierMask = [.command,.shift]; quick.target = self; menu.addItem(quick)
        add("学习统计…", #selector(showStatistics))
        add("管理 / 删除词库…", #selector(showBooksManager))
        let mini = NSMenuItem(title: "迷你模式", action: #selector(toggleMini), keyEquivalent: "")
        mini.target = self; mini.state = store.saved.settings.miniMode ? .on : .off; menu.addItem(mini)
        add("下一个单词", #selector(nextWord))
        add("朗读当前单词", #selector(readWord))
        add("标记为已掌握", #selector(markMastered))
        add("新学", #selector(newMode))
        add("复习", #selector(reviewMode))
        menu.addItem(.separator())
        let bookMenu = NSMenu()
        for book in store.books {
            let entry = NSMenuItem(title: "\(book.name) · \(book.words.count) 词", action: #selector(changeBook(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = book.id
            entry.state = book.id == store.saved.settings.bookID ? .on : .off; bookMenu.addItem(entry)
        }
        let booksItem = NSMenuItem(title: "切换词库", action: nil, keyEquivalent: "")
        booksItem.submenu = bookMenu; menu.addItem(booksItem)
        add(store.saved.settings.autoRotate ? "暂停自动换词" : "开启自动换词", #selector(toggleRotation))
        add("偏好设置…", #selector(openSettings))
        add("导入词表…", #selector(importWords))
        add("导出学习记录…", #selector(exportProgress))
        menu.addItem(.separator())
        add("退出词隙", #selector(quit))
        item.menu = menu; item.button?.performClick(nil); item.menu = nil
    }

    @objc func openCard() { store.resumeQuickStudy(); showCardContent(); showPanel() }
    @objc func openQuickAdd() {
        if quickAddVisible { closeQuickAdd(); return }
        let input = QuickWordInput.capture()
        pronunciationQueue.cancel(); speaker.stopSpeaking(); answerFeedback.clear(); store.pauseStudyTiming()
        let model = QuickAddModel(store:store); quickAddModel = model
        model.prepare(input.text,origin:input.origin)
        model.onAdded = { [weak self] in self?.showCardContent(); self?.showPanel() }
        quickAddVisible = true; settingsVisible = true; quickAddNeedsFocus = true
        panel.isMovableByWindowBackground = false
        panel.setFrameAutosaveName(""); panel.setContentSize(CardLayout.miniSize)
        panel.contentView = glassCardHost(QuickAddView(model:model,cancel:{[weak self] in self?.closeQuickAdd()},inputReady:{[weak self] in self?.focusQuickAddInput()}))
        positionNearStatusItem(); showPanel()
        focusQuickAddInput()
    }
    func focusQuickAddInput() {
        guard quickAddVisible, quickAddNeedsFocus, let model = quickAddModel else { return }
        // SwiftUI may appear before activation finishes. Wait for both the native
        // field and key window, then focus once so subsequent edits keep their caret.
        DispatchQueue.main.async { [weak self, weak model] in
            guard let self, let model, self.quickAddModel === model,
                  self.quickAddVisible, self.quickAddNeedsFocus, self.panel.isKeyWindow else { return }
            if QuickAddInputFocus.focus(in: self.panel) { self.quickAddNeedsFocus = false }
        }
    }
    func closeQuickAdd() { quickAddModel?.cancel(); showCardContent(); hidePanel() }
    func recordQuickRuntime() {
        let values: [String:Any] = ["cardShortcutStatus":Int(cardShortcutStatus),"quickShortcutStatus":Int(quickShortcutStatus),"quickShortcut":"Command+Shift+K","visible":panel.isVisible,"key":panel.isKeyWindow,"appActive":NSApp.isActive,"app":Bundle.main.bundlePath]
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WordGap")
        if let data = try? JSONSerialization.data(withJSONObject:values,options:[.sortedKeys]) { try? data.write(to:folder.appendingPathComponent("quick-add-runtime.json"),options:.atomic) }
    }
    @objc func toggleCard() {
        if panel.isVisible { hidePanel() } else { openCard() }
    }
    func hidePanel() { if quickAddVisible { showCardContent() }; confusions.setActive(false); pendingPanelOpen?.cancel(); pendingPanelOpen = nil; pronunciationQueue.cancel(); answerFeedback.clear(); store.pauseStudyTiming(); panel.orderOut(nil); speaker.stopSpeaking() }
    @objc func toggleMini() {
        store.saved.settings.miniMode.toggle()
        store.settingsChanged()
    }
    @objc func nextWord() { store.skipWord() }
    @objc func readWord() { speakCurrent() }
    @objc func markMastered() { store.markMastered() }
    @objc func newMode() { store.setMode(.newWords) }
    @objc func reviewMode() { store.setMode(.review) }
    @objc func changeBook(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { store.selectBook(id) } }
    @objc func toggleRotation() { store.saved.settings.autoRotate.toggle(); store.settingsChanged(); lastRotation = Date() }
    @objc func openSettings() { showSettings() }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func importWords() {
        if !panel.isVisible { showPanel() }
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.message = "导入 UTF-8 CSV / TSV：单词、释义、音标、例句、例句翻译"
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK, let url = picker.url else { return }
            do { try self.store.importWords(data: Data(contentsOf: url), filename: url.lastPathComponent); self.showCardContent() }
            catch { self.alert("导入未完成", error.localizedDescription) }
        }
    }

    @objc func exportProgress() {
        if !panel.isVisible { showPanel() }
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSavePanel(); picker.allowedContentTypes = [.json]
        picker.nameFieldStringValue = "词隙学习备份.json"
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard let self, response == .OK, let url = picker.url else { return }
            do { try self.store.export(to: url); self.store.notice = "学习记录和自建词库已导出" }
            catch { self.alert("导出未完成", error.localizedDescription) }
        }
    }

    func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.beginSheetModal(for: panel)
    }

    @objc func showStatistics() {
        hidePanel()
        if statisticsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "词隙 · 学习统计"; window.isReleasedWhenClosed = false
            window.isOpaque = false; window.backgroundColor = .clear
            window.minSize = NSSize(width: 840, height: 560)
            window.setFrameAutosaveName("WordGapStatistics"); window.center()
            window.contentView = glassCardHost(StatisticsView(store: store, exportCSV: { [weak self] text, name in
                self?.exportStatistics(text, filename: name)
            }))
            statisticsWindow = window
            applySettings()
        }
        NSApp.activate(ignoringOtherApps: true)
        statisticsWindow?.makeKeyAndOrderFront(nil)
    }
    func exportStatistics(_ text: String, filename: String) {
        guard let window = statisticsWindow else { return }
        let picker = NSSavePanel(); picker.allowedContentTypes = [.commaSeparatedText]; picker.nameFieldStringValue = filename
        picker.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = picker.url else { return }
            do { try Data(text.utf8).write(to: url, options: .atomic) }
            catch {
                let alert = NSAlert(); alert.messageText = "统计导出失败"; alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: self?.statisticsWindow ?? window)
            }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        if quickAddVisible { focusQuickAddInput() }
        else if !settingsVisible { store.startStudyTiming() }
    }
    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { store.pauseStudyTiming() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hidePanel(); return false }
    func applicationWillTerminate(_ notification: Notification) {
        confusions.shutdown()
        pronunciationQueue.cancel()
        timer?.invalidate(); speaker.stopSpeaking()
        answerFeedback.clear()
        store.pauseStudyTiming()
        cardHotKey.unregister()
        quickHotKey.unregister(); quickAddModel?.cancel()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
    }
}
