import Foundation

/// Presets as Synapse selects them: `08/02 [01 PP]`.
public enum EQPreset: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case game = 1
    case music = 2
    case movie = 3
    case custom = 4

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .game: "Game"
        case .music: "Music"
        case .movie: "Movie"
        case .custom: "Custom"
        }
    }
}

public enum EQ {
    public static let bandCount = 10
    /// Band centre frequencies in Hz (31 Hz to 16 kHz, per the sibling Nommo V2 X documentation).
    public static let frequencies: [Int] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    public static func label(for hz: Int) -> String {
        hz >= 1000 ? "\(hz / 1000)k" : "\(hz)"
    }

    /// Raw device value for a flat band.
    public static let flatRaw: UInt8 = 0x0C
    /// Assumed span: raw 0...24 maps to -12...+12 dB around flat. UNVERIFIED by ear.
    public static let maxDecibels: Double = 12

    public static func raw(fromDecibels dB: Double) -> UInt8 {
        let clamped = min(max(dB, -maxDecibels), maxDecibels)
        return UInt8((Double(flatRaw) + clamped).rounded())
    }

    public static func decibels(fromRaw raw: UInt8) -> Double {
        min(max(Double(raw) - Double(flatRaw), -maxDecibels), maxDecibels)
    }
}

/// A named Custom EQ curve, in dB per band (-12...12).
public struct EQProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var decibels: [Double]

    public init(id: UUID = UUID(), name: String, decibels: [Double]) {
        self.id = id
        self.name = name
        self.decibels = decibels
    }
}
