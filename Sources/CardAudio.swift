import AppKit
import QuartzCore

enum CardAudioLevels {
    static let feedback: Float = 0.70
    static let pronunciation: Float = 0.75
}

// Defer requests one main-loop turn so a score's feedback starts first.
// Keep only the latest word; resume on actual audio completion, without blocking UI.
final class CardPronunciationQueue {
    private let feedbackIsPlaying: () -> Bool
    private let clock: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var generation = UUID()
    private var pending: (() -> Void)?
    private var readyAfter: TimeInterval = 0

    init(feedbackIsPlaying: @escaping () -> Bool,
         clock: @escaping () -> TimeInterval = { CACurrentMediaTime() },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.feedbackIsPlaying = feedbackIsPlaying; self.clock = clock; self.schedule = schedule
    }

    func request(_ action: @escaping () -> Void) {
        generation = UUID(); pending = action; scheduleFlush()
    }
    func cancel() { generation = UUID(); pending = nil }
    func feedbackDidFinish() {
        readyAfter = clock() + 0.04
        scheduleFlush()
    }
    private func scheduleFlush() {
        guard pending != nil else { return }
        let token = generation
        schedule(max(0, readyAfter - clock())) { [weak self] in
            guard let self, self.generation == token, !self.feedbackIsPlaying(), let action = self.pending else { return }
            if self.clock() < self.readyAfter { self.scheduleFlush(); return }
            self.pending = nil; action()
        }
    }
}
