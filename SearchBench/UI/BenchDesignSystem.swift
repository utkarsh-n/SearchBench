import SwiftUI

// Metro Station adapted to a measurement tool. The app has no decorative clock,
// sensor transforms, or synthetic signal; every foreground value belongs to the
// runtime's prepared snapshot.
enum BenchPalette {
    static let canvas = Color(red: 0.025, green: 0.042, blue: 0.058)
    static let panel = Color(red: 0.045, green: 0.070, blue: 0.087)
    static let metalLight = Color(red: 0.055, green: 0.073, blue: 0.090)
    static let metalDark = Color(red: 0.021, green: 0.032, blue: 0.042)
    static let display = Color(red: 0.91, green: 0.95, blue: 0.97)
    static let secondary = Color(red: 0.60, green: 0.69, blue: 0.73)
    static let cyan = Color(red: 0.34, green: 0.93, blue: 0.96)
    static let amber = Color(red: 1.00, green: 0.74, blue: 0.37)
    static let violet = Color(red: 0.76, green: 0.57, blue: 1.00)
}

struct BenchBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            BenchPalette.canvas
            if !reduceTransparency {
                RadialGradient(
                    colors: [BenchPalette.cyan.opacity(0.07), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct BenchPanel<Content: View>: View {
    let content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BenchPalette.panel.opacity(reduceTransparency ? 1 : 0.88),
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.24 : 0.09), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct BenchSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(BenchPalette.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct BenchMetric: View {
    let label: String
    let value: String
    let unit: String
    var accent = BenchPalette.cyan
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(BenchPalette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .medium))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(.caption, design: .monospaced))
            }
            .foregroundStyle(accent)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value == "—" ? "Not measured" : "\(value) \(unit)")
    }
}

struct BenchAction: View {
    let title: String
    let symbol: String
    var prominent = false
    var accent = BenchPalette.cyan
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 8)
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .modifier(BenchActionMaterial(prominent: prominent, accent: accent,
                                      reduceTransparency: reduceTransparency))
    }
}

private struct BenchActionMaterial: ViewModifier {
    let prominent: Bool
    let accent: Color
    let reduceTransparency: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            if prominent {
                content.buttonStyle(.glassProminent).tint(accent)
            } else {
                content.buttonStyle(.glass).tint(accent)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(accent)
                .foregroundStyle(BenchPalette.canvas)
        } else {
            content.buttonStyle(.bordered).tint(accent)
        }
    }
}
