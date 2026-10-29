import SwiftUI

/// Shared Liquid Glass vocabulary.
///
/// Every surface in the app is built from these three pieces so the material
/// behaves consistently: a panel modifier, a stat meter and a button style.
/// Real `glassEffect` / `GlassEffectContainer` APIs are used throughout — there
/// is no `Material` fallback path, because the deployment target is iOS 26.
extension Glass {
    /// Standard panel glass: regular thickness, optional tint, responds to touch.
    static func panel(tint: Color? = nil, interactive: Bool = true) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint.opacity(0.28))
        }
        return interactive ? glass.interactive() : glass
    }

    /// Clear glass for surfaces that sit over the sprite scene and should let the
    /// artwork read through.
    static var scenery: Glass {
        Glass.clear.interactive()
    }
}

struct GlassPanel: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(.panel(tint: tint), in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(
        tint: Color? = nil,
        cornerRadius: CGFloat = 28,
        padding: CGFloat = 16
    ) -> some View {
        modifier(GlassPanel(tint: tint, cornerRadius: cornerRadius, padding: padding))
    }
}

/// Picks between the prominent and standard glass button style.
///
/// A ternary cannot be used inline because the two styles are different types,
/// so selection state is expressed as a modifier instead.
private struct GlassChipModifier: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

extension View {
    func glassChip(_ isSelected: Bool) -> some View {
        modifier(GlassChipModifier(isSelected: isSelected))
    }
}

/// A horizontal meter that reads as a glass tube with liquid inside.
struct StatMeter: View {
    let key: StatKey
    let value: Double
    var compact = false

    private var fraction: Double { min(max(value / 100, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: key.symbolName)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(Color(hex: key.tintHex))
                Text(key.displayName)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(Int(value.rounded()))")
                    .font(.system(compact ? .caption2 : .caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            // A GeometryReader has no intrinsic width, so two of them side by
            // side inside an HStack make the row unmeasurable and it overflows.
            // Scaling a full-width capsule keeps the layout measurable.
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: key.tintHex),
                                Color(hex: key.tintHex).opacity(0.65)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: max(0.015, fraction), y: 1, anchor: .leading)
            }
            .frame(height: compact ? 6 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.displayName) \(Int(value))")
        .accessibilityValue("\(Int(value)) / 100")
    }
}

/// Icon-only glass button used in the action dock.
struct GlassActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isEnabled ? tint : Color.secondary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.glass)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Formats a signed stat delta the way the receipt chips display it.
func formatDelta(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    if rounded == 0 { return "±0" }
    return rounded > 0 ? "+\(rounded)" : "\(rounded)"
}
