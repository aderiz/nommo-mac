import SwiftUI

/// The app icon: two matte-black speaker pods with colour spilling out from behind them, on a graphite
/// rounded square. Drawn on a 512 pt canvas (rendered at 2x for a 1024 px master) following the macOS icon
/// grid: the shape is 412 pt with transparent margin around it.
public struct AppIconView: View {
    public init() {}

    private let shape = RoundedRectangle(cornerRadius: 94, style: .continuous)
    private let pink = Color(hex: 0xFF3F9E)
    private let blue = Color(hex: 0x3F8CFF)

    public var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(hex: 0x23252D), Color(hex: 0x0C0D11)], startPoint: .top, endPoint: .bottom))
                .frame(width: 412, height: 412)
                .overlay {
                    ZStack {
                        RadialGradient(colors: [pink.opacity(0.75), pink.opacity(0)], center: UnitPoint(x: 0.27, y: 0.42), startRadius: 0, endRadius: 190)
                        RadialGradient(colors: [blue.opacity(0.75), blue.opacity(0)], center: UnitPoint(x: 0.73, y: 0.42), startRadius: 0, endRadius: 190)
                        // Light pooling on the floor.
                        HStack(spacing: 40) {
                            Ellipse().fill(pink).frame(width: 130, height: 26).blur(radius: 14)
                            Ellipse().fill(blue).frame(width: 130, height: 26).blur(radius: 14)
                        }
                        .offset(y: 100)
                        .opacity(0.85)
                    }
                    .clipShape(shape)
                }
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 8)

            HStack(spacing: 14) {
                SpeakerView(glow: pink, level: 1)
                SpeakerView(glow: blue, level: 1)
            }
            .scaleEffect(1.18)
            .offset(y: 2)
        }
        .frame(width: 512, height: 512)
    }
}
