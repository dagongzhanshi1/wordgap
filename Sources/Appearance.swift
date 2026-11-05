import AppKit
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
    var nativeAppearance: NSAppearance? {
        switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) }
    }
    func apply(to application: NSApplication, windows: [NSWindow]) {
        let native = nativeAppearance
        application.appearance = native
        for window in windows {
            window.appearance = native
            window.contentView?.appearance = native
            window.contentView?.needsDisplay = true
        }
    }
}

enum AppPalette {
    private static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        }
    }
    static let nativeBackground = adaptive((0.965, 0.972, 0.985), (0.105, 0.112, 0.128))
    static let nativeGlassBackground = adaptive((0.965, 0.972, 0.985), (0.025, 0.028, 0.032))
    static let background = Color(nativeBackground)
    static let ink = Color(adaptive((0.10, 0.12, 0.16), (0.95, 0.96, 0.98)))
    static let muted = Color(adaptive((0.39, 0.42, 0.47), (0.70, 0.73, 0.78)))
    static let paper = Color(adaptive((1, 1, 1), (0.16, 0.17, 0.195)))
    static let accent = Color(adaptive((0.05, 0.38, 0.94), (0.35, 0.63, 1)))
    static let onAccent = Color.white
    static let forgot = Color(adaptive((0.985, 0.93, 0.94), (0.25, 0.17, 0.19)))
    static let vague = Color(adaptive((0.985, 0.962, 0.91), (0.26, 0.23, 0.17)))
    static let forgotInk = Color(adaptive((0.57, 0.37, 0.39), (0.91, 0.74, 0.76)))
    static let vagueInk = Color(adaptive((0.51, 0.43, 0.29), (0.89, 0.82, 0.66)))
    static let knewInk = Color(adaptive((0.04, 0.29, 0.68), (0.36, 0.65, 0.98)))
    static let hairline = Color(adaptive((0.73, 0.76, 0.81), (0.36, 0.39, 0.45)))
    static let statisticsBackground = background
    static let review = Color(adaptive((0.75, 0.47, 0.09), (0.96, 0.71, 0.30)))
}
