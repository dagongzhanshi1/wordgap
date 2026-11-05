import AppKit
import Carbon

struct EnglishVoice {
    let identifier: String
    let locale: String

    // Apple also ships joke voices and robotic Eloquence voices. Neither is a
    // suitable fallback for learning pronunciation, even if its locale is English.
    var isNatural: Bool {
        identifier.hasPrefix("com.apple.voice.") ||
        ["Alex", "Samantha", "Daniel", "Karen", "Moira", "Tessa"].contains {
            identifier == "com.apple.speech.synthesis.voice." + $0
        }
    }
    var quality: Int {
        if identifier.contains(".premium.") { return 2 }
        if identifier.contains(".enhanced.") { return 1 }
        return 0
    }

    static func select(from voices: [EnglishVoice], british: Bool) -> EnglishVoice? {
        let locale = british ? "en_GB" : "en_US"
        let preferred = british ? "Daniel" : "Samantha"
        return voices.filter { $0.isNatural && $0.locale.hasPrefix("en") }.sorted {
            let a = $0.locale.replacingOccurrences(of: "-", with: "_")
            let b = $1.locale.replacingOccurrences(of: "-", with: "_")
            if (a == locale) != (b == locale) { return a == locale }
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            if $0.identifier.hasSuffix("." + preferred) != $1.identifier.hasSuffix("." + preferred) {
                return $0.identifier.hasSuffix("." + preferred)
            }
            return $0.identifier < $1.identifier
        }.first
    }

    static func installed(british: Bool) -> NSSpeechSynthesizer.VoiceName? {
        let voices = NSSpeechSynthesizer.availableVoices.map {
            EnglishVoice(identifier: $0.rawValue,
                         locale: NSSpeechSynthesizer.attributes(forVoice: $0)[.localeIdentifier] as? String ?? "")
        }
        return select(from: voices, british: british).map { NSSpeechSynthesizer.VoiceName(rawValue: $0.identifier) }
    }
}

final class CardHotKey {
    static let signature: OSType = 0x57474150 // WGAP
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let identifier: UInt32
    private let keyCode: UInt32
    private let modifiers: UInt32
    var onPressed: (() -> Void)?
    init(id: UInt32 = 1, keyCode: UInt32 = UInt32(kVK_ANSI_K), modifiers: UInt32 = UInt32(cmdKey)) {
        identifier = id; self.keyCode = keyCode; self.modifiers = modifiers
    }

    @discardableResult
    func register() -> OSStatus {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            let owner = Unmanaged<CardHotKey>.fromOpaque(context).takeUnretainedValue()
            guard result == noErr, id.signature == CardHotKey.signature, id.id == owner.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            owner.onPressed?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return status }
        let registered = RegisterEventHotKey(keyCode, modifiers,
                                            EventHotKeyID(signature: Self.signature, id: identifier),
                                            GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr { unregister() }
        return registered
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil
    }
    deinit { unregister() }
}
