import SwiftUI

extension Font {
    static func mono(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        Font(Theme.font(size: size, bold: bold, italic: italic) as CTFont)
    }
}

extension Color {
    static let glassAccent = Color(nsColor: Theme.accent)
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Frosted, see-through window glass, tinted and as clear as the user's settings ask.
struct GlassBackground: View {
    @Environment(GlassSettings.self) private var glass

    var body: some View {
        ZStack {
            // Practically invisible; keeps clicks from falling through a fully clear window.
            Color.black.opacity(0.02)
            VisualEffect(material: .hudWindow, blending: .behindWindow)
                .opacity(glass.blurOpacity)
            glass.tint(dimmed: 0.25)
                .opacity(glass.solidOpacity)
            LinearGradient(
                colors: [
                    glass.tint().opacity(glass.tintLevel),
                    glass.tint(dimmed: 0.55).opacity(min(1, glass.tintLevel * 1.45)),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Makes the hosting window transparent so the glass shows through.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HookView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HookView: NSView {
        private static let sizedKey = "GlasspadDidSetInitialWindowSize"

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // SwiftUI sizes the first window from its content, so pin a journal-shaped
            // window on first launch; after that the system restores the user's frame.
            if !UserDefaults.standard.bool(forKey: Self.sizedKey) {
                UserDefaults.standard.set(true, forKey: Self.sizedKey)
                DispatchQueue.main.async {
                    window.setContentSize(NSSize(width: 460, height: 640))
                    window.center()
                }
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.appearance = NSAppearance(named: .darkAqua)
            window.tabbingMode = .disallowed
            window.hasShadow = true
        }
    }
}
