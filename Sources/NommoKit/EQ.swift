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

/// Styles of music for the Music preset. `standard` is the speaker's own Music tuning, which can be selected but not
/// read or written. Every other style is a ten-band curve run through the Custom EQ. The cases are in menu order.
///
/// The curves are original starting points in whole dB, kept small (at most 6): the speaker is compact, and the dB
/// span is unverified by ear. Bands are 31 Hz to 16 kHz, as in `EQ.frequencies`.
public enum MusicGenre: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, flat
    case acoustic, bassBooster, bassReducer, classical, dance, deep, electronic, hipHop, jazz, latin, loudness
    case lounge, piano, pop, rnb, rock, smallSpeakers, spokenWord, trebleBooster, trebleReducer, vocal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Default"
        case .flat: "Flat"
        case .acoustic: "Acoustic"
        case .bassBooster: "Bass booster"
        case .bassReducer: "Bass reducer"
        case .classical: "Classical"
        case .dance: "Dance"
        case .deep: "Deep"
        case .electronic: "Electronic"
        case .hipHop: "Hip-hop"
        case .jazz: "Jazz"
        case .latin: "Latin"
        case .loudness: "Loudness"
        case .lounge: "Lounge"
        case .piano: "Piano"
        case .pop: "Pop"
        case .rnb: "R&B"
        case .rock: "Rock"
        case .smallSpeakers: "Small speakers"
        case .spokenWord: "Spoken word"
        case .trebleBooster: "Treble booster"
        case .trebleReducer: "Treble reducer"
        case .vocal: "Vocal booster"
        }
    }

    /// The curve in dB per band, or nil for `standard`, which has none we can write.
    public var decibels: [Double]? {
        switch self {
        case .standard: nil
        case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .acoustic: [2, 2, 2, 1, 1, 0, 1, 2, 3, 2]
        case .bassBooster: [4, 6, 5, 3, 1, 0, 0, 0, 0, 0]
        case .bassReducer: [-6, -5, -4, -2, -1, 0, 0, 0, 0, 0]
        case .classical: [1, 1, 1, 0, 0, 0, 0, 1, 2, 2]
        case .dance: [3, 5, 4, 1, 0, 0, 1, 2, 3, 3]
        case .deep: [4, 5, 4, 2, 1, 0, -1, -2, -3, -4]
        case .electronic: [3, 4, 2, 0, -2, -1, 0, 2, 3, 4]
        case .hipHop: [3, 4, 3, 1, 0, -1, 0, 1, 2, 2]
        case .jazz: [2, 2, 1, 2, 0, -1, -1, 0, 1, 2]
        case .latin: [2, 2, 1, 0, 0, 1, 2, 3, 4, 3]
        case .loudness: [5, 4, 2, 0, 0, 0, 0, 1, 3, 4]
        case .lounge: [1, 2, 2, 2, 1, 0, -1, -2, -1, 0]
        case .piano: [0, 1, 2, 2, 0, 0, 2, 3, 2, 1]
        case .pop: [-1, 1, 2, 3, 2, 0, 1, 2, 2, 1]
        case .rnb: [3, 5, 4, 2, 0, 0, 1, 2, 1, 0]
        case .rock: [3, 3, 2, 0, -2, -1, 1, 3, 3, 2]
        case .smallSpeakers: [-2, 0, 3, 4, 2, 0, 0, 1, 2, 3]
        case .spokenWord: [-6, -4, -2, 0, 2, 4, 5, 4, 1, -1]
        case .trebleBooster: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .trebleReducer: [0, 0, 0, 0, 0, -1, -2, -4, -5, -6]
        case .vocal: [-2, -1, 0, 1, 2, 3, 3, 2, 1, 0]
        }
    }

    /// The curve as the raw values the speaker takes.
    public var rawBands: [UInt8]? {
        decibels.map { $0.map(EQ.raw(fromDecibels:)) }
    }

    /// The style whose curve the speaker's bands currently hold, if any. Flat is never recognised: a flat curve is
    /// just as likely to be the user's own Custom curve.
    public static func matching(rawBands: [UInt8]) -> MusicGenre? {
        allCases.first { $0 != .flat && $0.rawBands == rawBands }
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
