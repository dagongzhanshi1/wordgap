import Foundation
import AppKit
import SwiftUI

enum CardLayout {
    static let regularSize = NSSize(width: 344, height: 520)
    static let settingsSize = NSSize(width: 344, height: 480)
    static let miniSize = NSSize(width: 244, height: 190)
    static let miniWordHeight: CGFloat = 27
    static let miniMeaningHeight: CGFloat = 70
    static let miniRatingHeight: CGFloat = 20
    static let miniFooterHeight: CGFloat = 11

    static func isMenuBarAnchor(_ anchor: NSRect, visible: NSRect) -> Bool {
        [anchor.minX, anchor.minY, anchor.width, anchor.height].allSatisfy { $0.isFinite } &&
        anchor.width > 0 && anchor.height > 0 && anchor.height <= 60 &&
        anchor.maxX > visible.minX && anchor.minX < visible.maxX &&
        anchor.minY >= visible.maxY - 40 && anchor.minY <= visible.maxY + 80
    }

    static func origin(size: NSSize, below anchor: NSRect, visible: NSRect, gap: CGFloat = 6) -> NSPoint {
        let margin: CGFloat = 8
        let x = max(visible.minX + margin, min(anchor.midX - size.width / 2,
                                              visible.maxX - size.width - margin))
        let top = min(anchor.minY - gap, visible.maxY - gap)
        let y = max(visible.minY + margin, top - size.height)
        return NSPoint(x: x, y: y)
    }
}

struct MiniCardPlacement {
    private var cardOrigin: NSPoint?
    private var pendingAnchor: NSRect?
    private var pendingVisible: NSRect?
    private var pendingSize: NSSize?
    private var pendingSince: TimeInterval = 0

    mutating func origin(size: NSSize, below anchor: NSRect, visible: NSRect,
                         settlingTime: TimeInterval = 0, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> NSPoint? {
        if let origin = cardOrigin, visible.contains(NSRect(origin: origin, size: size)) {
            return origin
        }
        guard CardLayout.isMenuBarAnchor(anchor, visible: visible) else { return nil }
        // A valid status-item frame can still be moving during menu-bar layout.
        // Settle only before locking a new position; later words keep the lock.
        if settlingTime > 0 {
            if pendingAnchor != anchor || pendingVisible != visible || pendingSize != size {
                pendingAnchor = anchor; pendingVisible = visible; pendingSize = size; pendingSince = now
                return nil
            }
            guard now - pendingSince >= settlingTime else { return nil }
        }
        let origin = CardLayout.origin(size: size, below: anchor, visible: visible, gap: 1)
        cardOrigin = origin
        return origin
    }
}

func fixedCardHost<Content: View>(_ content: Content) -> NSHostingView<Content> {
    let host = NSHostingView(rootView: content)
    // Words and definitions may change their intrinsic sizes; the panel owns its size.
    host.sizingOptions = []
    host.autoresizingMask = [.width, .height]
    return host
}
