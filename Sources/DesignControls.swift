import AppKit
import SwiftUI

private final class BackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct NativeWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = BackdropView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

final class GlassAppearanceState: ObservableObject {
    static let shared = GlassAppearanceState()
    @Published private(set) var enabled = true
    @Published private(set) var intensity: Double = 0.65
    func readingOpacity(dark: Bool) -> Double {
        guard enabled else { return 1 }
        // Older dark glass used an 82% charcoal reading plane. Keep that depth
        // while the slider varies transparency, so a bright desktop cannot wash it out.
        return dark ? 0.94 - 0.12 * intensity : 0.72 - 0.60 * intensity
    }
    var surfaceOpacity: Double { enabled ? 0.24 - 0.20 * intensity : 1 }
    func apply(enabled: Bool, intensity: Double) {
        let amount = intensity.isFinite ? min(1, max(0, intensity)) : 0.65
        if self.enabled != enabled { self.enabled = enabled }
        if self.intensity != amount { self.intensity = amount }
    }
}

struct WordGapWindowBackdrop: View {
    @ObservedObject private var glass = GlassAppearanceState.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Group {
            if !glass.enabled || reduceTransparency || contrast == .increased { AppPalette.background }
            else if #available(macOS 26.0, *) { Color(AppPalette.nativeGlassBackground).opacity(glass.readingOpacity(dark: colorScheme == .dark)) }
            else { NativeWindowMaterial() }
        }.ignoresSafeArea()
    }
}

// Content stays in the same host while strength changes, preserving focus and layout.
final class LiquidCardHost: NSView {
    let cardContentView: NSView
    private(set) var materialView: NSView?
    private var lastEnabled: Bool?
    private var lastIntensity: Double?
    init(content: NSView) {
        cardContentView = content
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear; glass.cornerRadius = 14
            materialView = glass
        } else {
            let blur = BackdropView()
            blur.material = .underWindowBackground; blur.blendingMode = .behindWindow; blur.state = .active
            materialView = blur
        }
        if let materialView { materialView.autoresizingMask = [.width, .height]; addSubview(materialView) }
        apply(enabled: GlassAppearanceState.shared.enabled, intensity: GlassAppearanceState.shared.intensity)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func apply(enabled: Bool, intensity: Double, force: Bool = false) {
        guard let materialView else { return }
        let amount = min(1, max(0, intensity))
        let active = enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency &&
            !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        guard force || lastEnabled != active || lastIntensity != amount else { return }
        lastEnabled = active; lastIntensity = amount
        if #available(macOS 26.0, *), let glass = materialView as? NSGlassEffectView {
            // Restore the untinted clear shell from the earlier dark version.
            // Its black reading plane supplies depth without a second gray tint.
            glass.tintColor = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? nil : AppPalette.nativeBackground.withAlphaComponent(0.18 * (1 - amount))
            if active {
                if glass.contentView !== cardContentView {
                    cardContentView.removeFromSuperview(); glass.contentView = cardContentView
                    cardContentView.frame = glass.bounds
                }
            } else if glass.contentView != nil {
                glass.contentView = nil; addSubview(cardContentView); cardContentView.frame = bounds
            } else if cardContentView.superview == nil {
                addSubview(cardContentView); cardContentView.frame = bounds
            }
        } else if cardContentView.superview == nil {
            addSubview(cardContentView); cardContentView.frame = bounds
        }
        materialView.isHidden = !active
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = active ? nil : AppPalette.nativeBackground.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(enabled: GlassAppearanceState.shared.enabled, intensity: GlassAppearanceState.shared.intensity, force: true)
    }
}

func glassCardHost<Content: View>(_ content: Content) -> NSView {
    LiquidCardHost(content: fixedCardHost(content))
}

struct ChoiceStrip<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(String, Value)]
    var label: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.1 } label: {
                    Text(option.0).font(.system(size: 11, weight: selection == option.1 ? .semibold : .regular))
                        .foregroundStyle(selection == option.1 ? AppPalette.ink : AppPalette.muted)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background {
                            if selection == option.1 {
                                RoundedRectangle(cornerRadius: 7).fill(AppPalette.paper.opacity(0.16))
                                    .modifier(WordGapGlassSurface(tint: AppPalette.accent.opacity(0.04), fallback: AppPalette.paper, radius: 7))
                            }
                        }.contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                    .accessibilityValue(selection == option.1 ? "已选择" : "未选择")
                    .accessibilityAddTraits(selection == option.1 ? .isSelected : [])
            }
        }.padding(2).background {
            RoundedRectangle(cornerRadius: 9).fill(AppPalette.paper.opacity(0.08))
                .modifier(WordGapGlassSurface(tint: nil, fallback: AppPalette.background, radius: 9))
        }
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(AppPalette.hairline.opacity(0.22), lineWidth: 0.5))
            .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

struct SelectionMenu<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(String, Value)]
    var label: String
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button(options[index].0) { selection = options[index].1 }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first(where: { $0.1 == selection })?.0 ?? label).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.muted)
            }.font(.system(size: 11)).foregroundStyle(AppPalette.ink)
                .frame(height: 16)
        }.menuStyle(.button).menuIndicator(.hidden).buttonStyle(UniformMenuButtonStyle())
            .tint(AppPalette.ink).accessibilityLabel(label)
    }
}

struct UniformMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11)).foregroundStyle(AppPalette.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .modifier(QuietSurface(radius: 9))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SettingsActionRow: View {
    var title: String
    var subtitle = ""
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(AppPalette.ink)
                    if !subtitle.isEmpty { Text(subtitle).font(.system(size: 10)).foregroundStyle(AppPalette.muted) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.muted)
            }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

func cardFeedbackHost(_ root: NSView) -> NSView {
    (root as? LiquidCardHost)?.cardContentView ?? root
}

struct StudyModeSwitch: View {
    @Binding var selection: StudyMode
    var compact = false
    var body: some View {
        HStack(spacing: 0) {
            modeButton(.newWords)
            modeButton(.review)
        }
        .frame(height: compact ? 18 : 24)
        .background(AppPalette.paper.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(AppPalette.hairline.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("新学或复习")
    }
    private func modeButton(_ mode: StudyMode) -> some View {
        Button { selection = mode } label: {
            Text(mode.label).font(.system(size: compact ? 10 : 12, weight: selection == mode ? .semibold : .regular))
                .foregroundStyle(selection == mode ? AppPalette.ink : AppPalette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selection == mode {
                        Capsule().fill(AppPalette.paper.opacity(0.16))
                            .modifier(WordGapGlassSurface(tint: nil, fallback: AppPalette.paper, radius: 9))
                    }
                }
                .contentShape(Capsule())
        }.buttonStyle(.plain)
            .help(mode == .newWords ? "新学 · 卡片内 ⌘1" : "复习 · 卡片内 ⌘2")
            .accessibilityValue(selection == mode ? "已选择" : "未选择")
            .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }
}

// A single reading plane avoids nested white cards competing with the word.
struct ReadingSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            Rectangle().fill(AppPalette.hairline.opacity(contrast == .increased ? 0.8 : 0.22))
                .frame(height: 0.5).allowsHitTesting(false)
        }
    }
}

// Only small actions receive raised glass; the reading plane stays continuous.
struct WordGapGlassSurface: ViewModifier {
    var tint: Color?
    var fallback: Color
    var radius: CGFloat = 8
    @ObservedObject private var glass = GlassAppearanceState.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass.enabled, !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(fallback, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AppPalette.hairline.opacity(contrast == .increased ? 1 : 0.35), lineWidth: contrast == .increased ? 1 : 0.5))
        }
    }
}

struct AnswerButtonStyle: ButtonStyle {
    var rating: Rating
    var radius: CGFloat = 8
    private var fill: Color {
        switch rating { case .forgot: return AppPalette.forgot; case .vague: return AppPalette.vague; case .knew: return AppPalette.paper }
    }
    private var ink: Color {
        switch rating { case .forgot: return AppPalette.forgotInk; case .vague: return AppPalette.vagueInk; case .knew: return AppPalette.knewInk }
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(ink)
            .background {
                // Draw glyphs above the material; a gentle backplate quiets the desktop underneath.
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill.opacity(0.30))
                    .modifier(WordGapGlassSurface(tint: ink.opacity(0.06), fallback: fill, radius: radius))
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct InstantIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct QuietSurface: ViewModifier {
    var radius: CGFloat = 10
    @ObservedObject private var glass = GlassAppearanceState.shared
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppPalette.paper.opacity(glass.surfaceOpacity))
                .modifier(WordGapGlassSurface(tint: nil, fallback: AppPalette.paper, radius: radius))
        }
    }
}
