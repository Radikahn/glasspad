import SwiftUI

struct SettingsView: View {
    @Environment(GlassSettings.self) private var glass

    var body: some View {
        @Bindable var glass = glass
        VStack(alignment: .leading, spacing: 18) {
            SettingLabel("Tint Color")
            ColorWheel(hue: $glass.hue, saturation: $glass.saturation, brightness: glass.brightness)
                .frame(width: 196, height: 196)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            Row("Brightness", value: glass.brightness) {
                GradientBar(value: $glass.brightness, colors: [
                    .black, Color(hue: glass.hue, saturation: glass.saturation, brightness: 1),
                ])
            }
            Row("Tint Level", value: glass.tintLevel) {
                GradientBar(value: $glass.tintLevel, colors: [glass.tint().opacity(0), glass.tint()], checkered: true)
            }
            Row("Transparency", value: glass.transparency) {
                let solid = glass.tint(dimmed: 0.25)
                GradientBar(value: $glass.transparency, colors: [solid, solid.opacity(0)], checkered: true)
            }

            Divider()
            HStack {
                SettingLabel("Scroll Bar")
                Spacer()
                Toggle("Scroll Bar", isOn: $glass.showsScrollBar)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(.glassAccent)
            }

            HStack {
                Spacer()
                Button("Reset to Default") { glass.reset() }
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 320)
        .preferredColorScheme(.dark)
    }
}

private struct SettingLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.mono(11, bold: true))
            .foregroundStyle(.white.opacity(0.55))
    }
}

private struct Row<Control: View>: View {
    let title: String
    let value: Double
    @ViewBuilder let control: Control

    init(_ title: String, value: Double, @ViewBuilder control: () -> Control) {
        self.title = title
        self.value = value
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SettingLabel(title)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.mono(10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .monospacedDigit()
            }
            control
        }
    }
}
