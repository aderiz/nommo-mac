import NommoKit
import SwiftUI

// MARK: - Colour

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    var rgb: RGB {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        return RGB(byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

/// The one colour the interface uses for anything selected or active: whatever colour the user chose for
/// the lights. Everything else is neutral, so the speakers and this accent are the only colour on screen.
struct Accent: Equatable {
    var rgb: RGB

    static let fallback = Accent(rgb: RGB(10, 132, 255))

    var color: Color { Color(rgb: rgb) }

    /// A barely-there vertical gradient in the same hue, so fills have a little depth.
    var fill: LinearGradient {
        LinearGradient(colors: [Color(rgb: rgb.mixed(with: .white, 0.16)), color], startPoint: .top, endPoint: .bottom)
    }

    var tint: Color { color.opacity(0.16) }

    /// Text that reads on top of the accent fill.
    var onAccent: Color {
        let luminance = (0.299 * Double(rgb.r) + 0.587 * Double(rgb.g) + 0.114 * Double(rgb.b)) / 255
        return luminance > 0.6 ? Color(hex: 0x0E0F12) : .white
    }
}

extension EnvironmentValues {
    @Entry var accent = Accent.fallback
    /// Snapshot rendering can't draw some AppKit-backed controls or animate, so views swap in static stand-ins.
    @Entry var isSnapshot = false
}

// MARK: - Tokens

enum Theme {
    static let baseTop = Color(hex: 0x181A1F)
    static let baseBottom = Color(hex: 0x0E0F12)
    static let text = Color.white
    static let dim = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.36)
    static let glass = Color.white.opacity(0.06)
    static let glassStrong = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.09)

    /// Expanded SF Pro gives the name and readouts the proportions of hardware lettering.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold).width(.expanded) }
    static func number(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold).width(.expanded).monospacedDigit() }
    static let label = Font.system(size: 12.5, weight: .medium)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11.5)
}

/// A quiet surface with a hairline edge.
struct Surface: ViewModifier {
    var radius: CGFloat = 14
    var strong = false

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(strong ? Theme.glassStrong : Theme.glass)
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1) }
        }
    }
}

extension View {
    func surface(radius: CGFloat = 14, strong: Bool = false) -> some View { modifier(Surface(radius: radius, strong: strong)) }
}

/// Slight lift on hover and press for anything clickable.
struct Pressable: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(hovering ? 0.08 : 0)
            .animation(.snappy(duration: 0.12), value: hovering)
            .animation(.snappy(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

// MARK: - Slider

struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0 ... 1
    @Environment(\.accent) private var accent

    private let thumb: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = thumb / 2 + CGFloat(min(max(t, 0), 1)) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10)).frame(height: 6)
                Capsule().fill(accent.fill).frame(width: x, height: 6)
                Circle().fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .shadow(color: accent.color.opacity(0.5), radius: 6)
                    .offset(x: x - thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = Double(min(max((drag.location.x - thumb / 2) / usable, 0), 1))
                    value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - Pill picker

/// A segmented choice. The selection is a pill in the accent colour that slides between options.
struct PillPicker<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option?
    @Environment(\.accent) private var accent
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(Theme.label)
                        .foregroundStyle(selected ? accent.onAccent : Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected { Capsule().fill(accent.fill).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.glass).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1)))
    }
}

// MARK: - Switch

struct SwitchToggle: View {
    @Binding var isOn: Bool
    var label: String
    @Environment(\.accent) private var accent

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(accent.fill) : AnyShapeStyle(Color.white.opacity(0.14)))
                    .frame(width: 46, height: 28)
                Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Swatches

/// Preset colours, plus a rainbow bead that opens the system colour picker. These are the one place a
/// spread of colour is right: the colours are the data.
struct SwatchRow: View {
    @Binding var selection: RGB
    var size: CGFloat = 20
    @Environment(\.isSnapshot) private var isSnapshot

    static let palette: [RGB] = [
        RGB(255, 69, 80), RGB(255, 150, 30), RGB(255, 214, 10), RGB(60, 215, 100), RGB(0, 215, 180),
        RGB(60, 190, 255), RGB(10, 132, 255), RGB(155, 105, 255), RGB(255, 75, 185), RGB(255, 255, 255),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.palette, id: \.self) { color in
                Button { selection = color } label: { bead(color, selected: color == selection) }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("Colour")
                    .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
            customBead
        }
    }

    private func bead(_ color: RGB, selected: Bool) -> some View {
        Circle()
            .fill(Color(rgb: color))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 1 : 0.18), lineWidth: selected ? 2 : 0.8))
            .padding(selected ? 0 : 1)
            .scaleEffect(selected ? 1.1 : 1)
    }

    private var isCustom: Bool { !Self.palette.contains(selection) }

    private var customBead: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .overlay { if isCustom { Circle().fill(Color(rgb: selection)).padding(6) } }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(isCustom ? 1 : 0.18), lineWidth: isCustom ? 2 : 0.8))
            if !isSnapshot {
                // The real picker sits invisibly on top so the bead can be styled freely.
                ColorPicker("Custom colour", selection: Binding(get: { Color(rgb: selection) }, set: { selection = $0.rgb }),
                            supportsOpacity: false)
                    .labelsHidden().opacity(0.02).frame(width: size, height: size).clipShape(Circle())
            }
        }
    }
}

// MARK: - Small controls

struct QuietButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(Theme.label)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .surface(radius: 20, strong: true)
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }
}

/// A name on the left and a value or control on the right.
struct FieldHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(Theme.label).foregroundStyle(Theme.dim)
            Spacer()
            trailing
        }
    }
}

/// A label, a slider and a value on a single line.
struct InlineSlider: View {
    let title: String
    var valueText: String = ""
    @Binding var value: Double
    var range: ClosedRange<Double> = 0 ... 1

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(Theme.label).foregroundStyle(Theme.dim)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: 70, alignment: .leading)
            GlowSlider(value: $value, range: range)
            Text(valueText).font(Theme.number(12)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 52, alignment: .trailing)
        }
    }
}
