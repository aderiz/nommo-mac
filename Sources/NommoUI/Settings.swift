import Foundation
import NommoKit

/// Everything the app remembers between launches.
struct Settings: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case builtIn, solid, breathing, spectrum, music, movie, off

        var id: String { rawValue }

        var title: String {
            switch self {
            case .builtIn: "Built-in"
            case .solid: "Solid"
            case .breathing: "Breathe"
            case .spectrum: "Spectrum"
            case .music: "Music"
            case .movie: "Movie"
            case .off: "Off"
            }
        }

        var symbol: String {
            switch self {
            case .builtIn: "sparkles"
            case .solid: "circle.fill"
            case .breathing: "wind"
            case .spectrum: "rainbow"
            case .music: "waveform"
            case .movie: "film"
            case .off: "moon.zzz.fill"
            }
        }
    }

    var kind: Kind = .builtIn
    var left = RGB(0, 120, 255)
    var right = RGB(0, 120, 255)
    var linkColors = true
    /// Seconds per breath / per spectrum cycle.
    var period: Double = 6
    /// 0...1, mapped to the speaker's 0...255 brightness.
    var brightness: Double = 1
    /// Per-band gain in dB, -12...12.
    var eqDecibels: [Double] = Array(repeating: 0, count: EQ.bandCount)
    /// Spectrum only: both speakers show the same hue instead of being half a cycle apart.
    var mirrorSpectrum = true
    /// Breathe alternates between these two colours.
    var breathFirst = RGB(255, 75, 185)
    var breathSecond = RGB(60, 190, 255)
    var eqProfiles: [EQProfile] = []
    /// The profile the current Custom curve was loaded from or saved as (it may since have been edited).
    var activeEQProfile: UUID?
    var musicStyle: MusicStyle = .pulse
    /// 1 = normal; higher makes the lights react to quieter sound.
    var musicSensitivity: Double = 1
    /// Movie mode: how strongly the lights show the scene, and how slowly they settle. Both 0...1.
    var movieIntensity = MovieSettings.standard.intensity
    var movieSmoothness = MovieSettings.standard.smoothness
    /// Spatial audio is off by default: it reroutes system audio through this app.
    var spatialEnabled = false
    var spatialMode: SpatialMode = .immersive
    /// 0...1: how strong the effect is, in either mode.
    var spatialAmount: Double = 0.6

    init() {}

    /// Tolerant decoding so settings saved by older versions keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? d.kind
        left = try c.decodeIfPresent(RGB.self, forKey: .left) ?? d.left
        right = try c.decodeIfPresent(RGB.self, forKey: .right) ?? d.right
        linkColors = try c.decodeIfPresent(Bool.self, forKey: .linkColors) ?? d.linkColors
        period = try c.decodeIfPresent(Double.self, forKey: .period) ?? d.period
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? d.brightness
        eqDecibels = try c.decodeIfPresent([Double].self, forKey: .eqDecibels) ?? d.eqDecibels
        mirrorSpectrum = try c.decodeIfPresent(Bool.self, forKey: .mirrorSpectrum) ?? d.mirrorSpectrum
        breathFirst = try c.decodeIfPresent(RGB.self, forKey: .breathFirst) ?? d.breathFirst
        breathSecond = try c.decodeIfPresent(RGB.self, forKey: .breathSecond) ?? d.breathSecond
        musicStyle = try c.decodeIfPresent(MusicStyle.self, forKey: .musicStyle) ?? d.musicStyle
        musicSensitivity = try c.decodeIfPresent(Double.self, forKey: .musicSensitivity) ?? d.musicSensitivity
        movieIntensity = try c.decodeIfPresent(Double.self, forKey: .movieIntensity) ?? d.movieIntensity
        movieSmoothness = try c.decodeIfPresent(Double.self, forKey: .movieSmoothness) ?? d.movieSmoothness
        eqProfiles = try c.decodeIfPresent([EQProfile].self, forKey: .eqProfiles) ?? d.eqProfiles
        activeEQProfile = try c.decodeIfPresent(UUID.self, forKey: .activeEQProfile)
        spatialEnabled = try c.decodeIfPresent(Bool.self, forKey: .spatialEnabled) ?? d.spatialEnabled
        spatialMode = try c.decodeIfPresent(SpatialMode.self, forKey: .spatialMode) ?? d.spatialMode
        spatialAmount = try c.decodeIfPresent(Double.self, forKey: .spatialAmount) ?? d.spatialAmount
    }

    var effect: LightingEffect {
        switch kind {
        case .builtIn: .builtIn
        case .solid: .solid(left: left, right: right)
        case .breathing: .breathing(first: breathFirst, second: breathSecond, period: period)
        case .spectrum: .spectrum(period: period, offset: mirrorSpectrum ? 0 : 0.5)
        case .music: .music(left: left, right: right, style: musicStyle, sensitivity: musicSensitivity)
        case .movie: .movie(MovieSettings(intensity: movieIntensity, smoothness: movieSmoothness))
        case .off: .off
        }
    }

    private static let key = "nommo.settings.v1"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data),
              settings.eqDecibels.count == EQ.bandCount
        else { return Settings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
