import AppKit

/// The small label in the corner of a code block. Clicking it opens a menu
/// that rewrites the block's fence info string.
final class LanguagePill: NSView {
    static let font = Theme.font(size: 10)
    static let height: CGFloat = 16

    var language = "" {
        didSet {
            guard language != oldValue else { return }
            title = CodeLanguage.label(for: language)
            needsDisplay = true
        }
    }
    var onSelect: ((String) -> Void)?

    private var title = CodeLanguage.label(for: "")
    private var hovering = false { didSet { needsDisplay = true } }

    var fittingWidth: CGFloat {
        (title as NSString).size(withAttributes: [.font: Self.font]).width + 24
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor(white: 1, alpha: hovering ? 0.12 : 0.05).setFill()
        shape.fill()

        let color = NSColor(white: 1, alpha: hovering ? 0.85 : 0.42)
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: 9, y: (bounds.height - size.height) / 2), withAttributes: attrs)

        let chevron = NSBezierPath()
        let cx = bounds.width - 10, cy = bounds.midY
        chevron.move(to: NSPoint(x: cx - 2.5, y: cy - 1.2))
        chevron.line(to: NSPoint(x: cx, y: cy + 1.3))
        chevron.line(to: NSPoint(x: cx + 2.5, y: cy - 1.2))
        chevron.lineWidth = 1.1
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        color.setStroke()
        chevron.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let current = CodeLanguage.find(language)?.id ?? language.lowercased()

        let plain = NSMenuItem(title: "Plain text", action: #selector(choose(_:)), keyEquivalent: "")
        plain.target = self
        plain.representedObject = ""
        plain.state = current.isEmpty ? .on : .off
        menu.addItem(plain)
        menu.addItem(.separator())

        for lang in CodeLanguage.all {
            let item = NSMenuItem(title: lang.name, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.id
            item.state = lang.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func choose(_ item: NSMenuItem) {
        onSelect?(item.representedObject as? String ?? "")
    }
}
