import AppKit
import QuartzCore

func runCardAudioTests(folder: URL, resource: URL?) throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure.failed(message) }
    }
    var time: TimeInterval = 0, feedbackPlaying = false
    var scheduled: [(TimeInterval, () -> Void)] = [], spoken: [String] = []
    let queue = CardPronunciationQueue(feedbackIsPlaying: { feedbackPlaying }, clock: { time },
        schedule: { delay, action in scheduled.append((time + delay, action)) })
    func advance(to end: TimeInterval) throws {
        var count = 0
        while let next = scheduled.enumerated().filter({ $0.element.0 <= end }).min(by: { $0.element.0 < $1.element.0 }) {
            count += 1
            try check(count < 100, "声音请求不得形成无限重试")
            let job = scheduled.remove(at: next.offset); time = job.0; job.1()
        }
        time = end
    }
    queue.request { spoken.append("old") }
    feedbackPlaying = true
    try advance(to: 0.1)
    try check(spoken.isEmpty, "换词后必须先给评分提示音留出播放机会")
    queue.request { spoken.append("latest") }
    try advance(to: 0.2)
    try check(spoken.isEmpty, "提示音播放期间自动或手动发音都不能重叠")
    feedbackPlaying = false; queue.feedbackDidFinish()
    try advance(to: 0.239)
    try check(spoken.isEmpty, "提示音结束后仍应留40毫秒间隔")
    try advance(to: 0.241)
    try check(spoken == ["latest"], "连续换词只朗读最后一个词，不能排队补读旧词")
    queue.request { spoken.append("cancelled") }; queue.cancel()
    try advance(to: 0.3)
    try check(spoken == ["latest"], "收起卡片或进入设置后应取消待播放的单词")
    queue.request { spoken.append("without feedback") }
    try advance(to: 0.3)
    try check(spoken == ["latest", "without feedback"], "提示音关闭时不应额外延迟朗读")

    let store = WordStore(folder: folder.appendingPathComponent("audio-order"), resource: resource)
    try store.importWords(data: Data("word\tmeaning\nalpha\t甲\nbeta\t乙\ngamma\t丙\ndelta\t丁".utf8), filename: "audio.tsv")
    store.onWordChanged = {
        let word = store.current?.word, presentation = store.presentationID
        queue.request { if store.presentationID == presentation, let word { spoken.append(word) } }
    }
    store.onAnswerFeedback = { _ in feedbackPlaying = true }
    let before = store.current?.id
    store.revealMeaning(); store.rate(.knew)
    try check(store.current?.id != before, "声音等待不能延迟评分后的换词")
    try advance(to: 0.4)
    try check(spoken.count == 2, "真实评分回调的先换词、后提示音顺序不能抢先发音")
    store.skipWord(); let latest = store.current?.word
    feedbackPlaying = false; queue.feedbackDidFinish()
    try advance(to: 0.441)
    try check(spoken.last == latest && spoken.count == 3, "提示音结束时只能朗读当前最新卡片")

    let speech = NSSpeechSynthesizer()
    speech.volume = CardAudioLevels.pronunciation
    try check(abs(speech.volume - 0.75) < 0.001, "英语朗读音量应为75%，不改变系统音量")

    // Exercise real NSSound completion with silent copies, without grading real words or emitting test sounds.
    guard let resource else { throw TestFailure.failed("音频资源缺失") }
    let silentFolder = folder.appendingPathComponent("silent-feedback")
    try FileManager.default.createDirectory(at: silentFolder, withIntermediateDirectories: true)
    for kind in AnswerFeedback.allCases {
        let name = "feedback-\(kind.rawValue).wav"
        var data = try Data(contentsOf: resource.appendingPathComponent(name)), offset = 12, silenced = false
        while offset + 8 <= data.count {
            let size = (0..<4).reduce(0) { $0 | (Int(data[offset + 4 + $1]) << (8 * $1)) }
            let end = offset + 8 + size
            try check(end <= data.count, "提示音WAV资源应完整")
            if String(data: data[offset..<offset + 4], encoding: .ascii) == "data" {
                data.replaceSubrange(offset + 8..<end, with: Data(count: size)); silenced = true; break
            }
            offset = end + size % 2
        }
        try check(silenced, "必须只将测试副本的PCM采样置零")
        try data.write(to: silentFolder.appendingPathComponent(name))
    }
    let feedback = AnswerFeedbackController(resource: silentFolder), host = NSView(frame: NSRect(x: 0, y: 0, width: 244, height: 190))
    try check(feedback.sounds.values.allSatisfy { abs($0.volume - 0.70) < 0.001 }, "四种提示音均应调至70%")
    let liveQueue = CardPronunciationQueue(feedbackIsPlaying: { feedback.isSoundPlaying })
    var finishedAt: TimeInterval?, startedAt: TimeInterval?
    feedback.onSoundFinished = { finishedAt = CACurrentMediaTime(); liveQueue.feedbackDidFinish() }
    liveQueue.request { startedAt = CACurrentMediaTime() }
    feedback.show(.forgot, in: host, soundEnabled: true)
    try check(feedback.isSoundPlaying && startedAt == nil, "真实提示音应先播放，朗读请求必须等待")
    let deadline = Date().addingTimeInterval(2)
    while startedAt == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    try check(finishedAt != nil && startedAt != nil && startedAt! - finishedAt! >= 0.035,
              "必须在NSSound实际播放完成回调之后，才启动朗读")
    liveQueue.request { startedAt = nil }; liveQueue.cancel()
    feedback.show(.mastered, in: host, soundEnabled: true); feedback.clear()
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    try check(!feedback.isSoundPlaying && startedAt != nil, "淡出结束必须解除声音占用，取消的朗读不能复活")
    print("CARD_AUDIO_TEST_OK: 真实提示音完成后朗读/40毫秒间隔/快速换词只读最新/收起取消/无提示音即时朗读/音量70%与75%")
}
