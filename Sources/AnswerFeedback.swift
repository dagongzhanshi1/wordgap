import AppKit
import QuartzCore

enum AnswerFeedback: String, CaseIterable {
    case forgot, vague, knew, mastered
    init(_ rating: Rating) {
        switch rating { case .forgot: self = .forgot; case .vague: self = .vague; case .knew: self = .knew }
    }
    var color: NSColor {
        switch self {
        case .forgot: return NSColor.systemRed
        case .vague: return NSColor.systemOrange
        case .knew: return NSColor.systemBlue
        case .mastered: return NSColor.systemPurple
        }
    }
}

private final class FeedbackLine: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AnswerFeedbackController: NSObject, NSSoundDelegate {
    static let duration: TimeInterval = 0.12
    let sounds: [AnswerFeedback: NSSound]
    private let alternateSounds: [AnswerFeedback: NSSound]
    private let line = FeedbackLine()
    private var playing: NSSound?
    private var fading: NSSound?
    private var fadeTimer: Timer?
    private var fadeStarted: CFTimeInterval = 0
    private var fadeVolume: Float = 0
    var onSoundFinished: (() -> Void)?
    var isSoundPlaying: Bool { playing != nil || fading != nil }

    init(resource: URL? = Bundle.main.resourceURL) {
        var loaded: [AnswerFeedback: NSSound] = [:], alternates: [AnswerFeedback: NSSound] = [:]
        if let resource {
            for kind in AnswerFeedback.allCases {
                if let sound = NSSound(contentsOf: resource.appendingPathComponent("feedback-\(kind.rawValue).wav"), byReference: false) {
                    sound.volume = CardAudioLevels.feedback; loaded[kind] = sound
                    if let alternate = sound.copy() as? NSSound { alternates[kind] = alternate }
                }
            }
        }
        sounds = loaded
        alternateSounds = alternates
        super.init()
        for sound in Array(loaded.values) + Array(alternates.values) { sound.delegate = self }
        line.wantsLayer = true; line.layer?.cornerRadius = 1.5; line.layer?.opacity = 0
    }

    func show(_ kind: AnswerFeedback, in host: NSView, soundEnabled: Bool) {
        if line.superview !== host {
            line.removeFromSuperview(); host.addSubview(line, positioned: .above, relativeTo: nil)
        }
        let width = min(80, max(0, host.bounds.width - 16))
        let y = host.isFlipped ? host.bounds.maxY - 5 : host.bounds.minY + 2
        line.frame = NSRect(x: host.bounds.midX - width / 2, y: y, width: width, height: 3)
        if let layer = line.layer {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.removeAllAnimations(); layer.backgroundColor = kind.color.cgColor; layer.opacity = 0
            CATransaction.commit()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85; fade.toValue = 0; fade.duration = Self.duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "answer-feedback")
        }
        stopSound()
        if soundEnabled, let primary = sounds[kind] {
            let sound = primary === fading ? (alternateSounds[kind] ?? primary) : primary
            sound.volume = CardAudioLevels.feedback; sound.currentTime = 0; playing = sound
            if !sound.play() { playing = nil; notifyIfQuiet() }
        }
    }

    func stopSound() {
        guard let sound = playing else { return }
        fadeTimer?.invalidate(); fading?.stop()
        playing = nil; fading = sound; fadeVolume = sound.volume; fadeStarted = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.008, repeats: true) { [weak self] _ in self?.advanceSoundFade() }
        fadeTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func advanceSoundFade() {
        let fraction = min(1, (CACurrentMediaTime() - fadeStarted) / 0.035)
        fading?.volume = fadeVolume * Float(0.5 + 0.5 * cos(.pi * fraction))
        if fraction >= 1 {
            fading?.stop(); fading = nil; fadeTimer?.invalidate(); fadeTimer = nil
            notifyIfQuiet()
        }
    }
    func sound(_ sound: NSSound, didFinishPlaying successfully: Bool) {
        // A stopped fading voice may finish after a newer voice has started.
        guard playing === sound, !sound.isPlaying else { return }
        playing = nil; notifyIfQuiet()
    }
    private func notifyIfQuiet() { if !isSoundPlaying { onSoundFinished?() } }
    func clear() { line.layer?.removeAllAnimations(); line.layer?.opacity = 0; stopSound() }
    deinit { fadeTimer?.invalidate(); playing?.stop(); fading?.stop() }
}
