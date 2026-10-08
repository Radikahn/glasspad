import SwiftUI

/// Hue around the rim, saturation from the center out.
struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    let brightness: Double

    private static let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { geo in
            let radius = geo.size.width / 2
            let angle = hue * 2 * .pi
            ZStack {
                Circle().fill(AngularGradient(colors: Self.hues, center: .center))
                Circle().fill(RadialGradient(
                    colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().fill(.black.opacity(1 - brightness))
                Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .position(x: radius + cos(angle) * saturation * radius,
                              y: radius + sin(angle) * saturation * radius)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let dx = drag.location.x - radius
                let dy = drag.location.y - radius
                let turn = atan2(dy, dx) / (2 * .pi)
                hue = turn < 0 ? turn + 1 : turn
                saturation = min(1, hypot(dx, dy) / radius)
            })
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A slider drawn as a gradient bar; checkered tracks show where the gradient turns see-through.
struct GradientBar: View {
    @Binding var value: Double
    let colors: [Color]
    var checkered = false

    private let height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - height
            ZStack(alignment: .leading) {
                if checkered {
                    Checkerboard().clipShape(Capsule())
                }
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
                Circle()
                    .strokeBorder(.white, lineWidth: 2.5)
                    .frame(width: height + 6, height: height + 6)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: value * travel - 3)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, (drag.location.x - height / 2) / travel))
            })
        }
        .frame(height: height)
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 5
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for col in 0..<Int((size.width / cell).rounded(.up)) where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(.white.opacity(0.22)))
                }
            }
        }
        .background(.white.opacity(0.06))
    }
}
