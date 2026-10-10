import AppKit

/// Flat rows with native hover feedback, sized consistently for the selection menu.
final class SelectionMenuButton: NSButton {
    private var tracking: NSTrackingArea?
    private var hovered = false
    init(title: String, symbol: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false; alignment = .left; font = .systemFont(ofSize: 13)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imagePosition = .imageLeading; imageHugsTitle = true
        contentTintColor = .labelColor
        heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let iconRect = NSRect(x: 14, y: (bounds.height - 16) / 2, width: 16, height: 16)
        image?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.8, respectFlipped: true, hints: nil)
        let text = NSAttributedString(string: title, attributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        let size = text.size()
        text.draw(at: NSPoint(x: 44, y: (bounds.height - size.height) / 2))
    }
}

enum PDFMargin: Int, CaseIterable {
    case normal, narrow, minimal
    var title: String { ["正常 · 25.4 mm", "较窄 · 12.7 mm", "极窄 · 6.35 mm"][rawValue] }
    var points: CGFloat { [72, 36, 18][rawValue] }
}
