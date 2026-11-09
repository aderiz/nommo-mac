import Foundation
import Testing
@testable import NommoKit

typealias Pixel = (r: UInt8, g: UInt8, b: UInt8)

/// Tightly packed BGRA bytes for a synthetic frame.
func frame(width: Int = 96, height: Int = 54, _ pixel: (_ x: Int, _ y: Int) -> Pixel) -> [UInt8] {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0 ..< height {
        for x in 0 ..< width {
            let p = pixel(x, y), i = (y * width + x) * 4
            bytes[i] = p.b
            bytes[i + 1] = p.g
            bytes[i + 2] = p.r
        }
    }
    return bytes
}

func read(_ bytes: [UInt8], reader: inout SceneReader, width: Int = 96, height: Int = 54) -> SceneSample {
    reader.read(bgra: bytes, width: width, height: height)
}

func close(_ a: UInt8, _ b: UInt8, within tolerance: Int = 3) -> Bool { abs(Int(a) - Int(b)) <= tolerance }

@Suite("Reading the screen")
struct SceneReaderTests {
    let amber: Pixel = (255, 140, 20)

    @Test func uniformColourComesBackUnchanged() {
        var reader = SceneReader()
        let s = read(frame { _, _ in (60, 140, 200) }, reader: &reader)
        for rgb in [s.left.rgb, s.right.rgb] {
            #expect(close(rgb.r, 60) && close(rgb.g, 140) && close(rgb.b, 200))
        }
        #expect(!s.isBlank)
    }

    @Test func letterboxBarsAreIgnored() {
        var reader = SceneReader()
        let bytes = frame { _, y in (y < 14 || y >= 40) ? (0, 0, 0) : amber }
        let s = read(bytes, reader: &reader)
        #expect(close(s.left.rgb.r, 255) && close(s.left.rgb.g, 140) && close(s.left.rgb.b, 20))
        #expect(abs(s.bars.top - 14.0 / 54) < 0.03 && abs(s.bars.bottom - 14.0 / 54) < 0.03)
    }

    @Test func pillarboxBarsAreIgnored() {
        var reader = SceneReader()
        let bytes = frame { x, _ in (x < 20 || x >= 76) ? (0, 0, 0) : (30, 90, 220) }
        let s = read(bytes, reader: &reader)
        #expect(close(s.left.rgb.b, 220) && close(s.right.rgb.b, 220))
        #expect(s.bars.leading > 0.15 && s.bars.trailing > 0.15)
    }

    @Test func subtitleInTheBarDoesNotMoveThePicture() {
        var reader = SceneReader()
        let plain = frame { _, y in (y < 14 || y >= 40) ? (0, 0, 0) : amber }
        let subtitled = frame { x, y in
            if y == 44, x > 30, x < 66 { return (255, 255, 255) }
            return (y < 14 || y >= 40) ? (0, 0, 0) : amber
        }
        var last: SceneSample?
        for i in 0 ..< 30 { last = read(i % 3 == 0 ? subtitled : plain, reader: &reader) }
        #expect(close(last!.left.rgb.r, 255) && close(last!.left.rgb.g, 140, within: 6))
    }

    @Test func offCentreBlastGivesTheNearSpeakerTheHotCore() {
        // Fireball fringe on the left, white-yellow core reaching the right edge.
        var reader = SceneReader()
        let bytes = frame { x, _ in
            let t = Double(x) / 95
            return (255, UInt8(120 + 120 * t), UInt8(10 + 200 * t * t))
        }
        let s = read(bytes, reader: &reader)
        // The edges themselves are (255,120,10) and (255,240,210); the average pulls them together but they stay apart.
        #expect(s.right.luminance > s.left.luminance * 1.4)
        #expect(s.left.rgb.g < 175) // still amber on the left
        #expect(s.right.rgb.b > s.left.rgb.b + 50) // visibly paler on the right
    }

    @Test func centredBlastLightsBothSpeakers() {
        var reader = SceneReader()
        let dark = frame { _, _ in (12, 10, 10) }
        let blast = frame { x, y in
            let dx = Double(x) - 47.5, dy = (Double(y) - 26.5) * 1.6
            return dx * dx + dy * dy < 22 * 22 ? (255, 245, 220) : (12, 10, 10)
        }
        let before = read(dark, reader: &reader)
        let s = read(blast, reader: &reader)
        #expect(s.left.luminance > 0.08 && s.right.luminance > 0.08)
        #expect(s.left.luminance > before.left.luminance * 20)
        #expect(abs(s.left.luminance - s.right.luminance) < 0.05 * max(s.left.luminance, s.right.luminance))
    }

    @Test func linearLightLetsABrightCoreBeatDimSurroundings() {
        // A small white patch among dark orange should pull the average towards white rather than orange.
        var reader = SceneReader()
        let bytes = frame { x, y in (x > 80 && y > 20 && y < 34) ? (255, 255, 255) : (90, 40, 5) }
        let s = read(bytes, reader: &reader)
        #expect(s.right.rgb.b > 40)
    }

    @Test func protectedVideoReadsAsBlank() {
        var reader = SceneReader()
        let s = read(frame { _, _ in (0, 0, 0) }, reader: &reader)
        #expect(s.isBlank)
    }

    @Test func aNearlyBlackLetterboxedFrameIsNotBlankWhenThePictureHasLight() {
        var reader = SceneReader()
        let s = read(frame { _, y in (y < 14 || y >= 40) ? (0, 0, 0) : (50, 45, 40) }, reader: &reader)
        #expect(!s.isBlank)
    }
}

@Suite("Following the scene")
struct MovieFollowerTests {
    func scene(_ c: LinearColor, _ d: LinearColor? = nil, blank: Bool = false) -> SceneSample {
        SceneSample(left: c, right: d ?? c, isBlank: blank)
    }

    func run(_ f: inout MovieFollower, scene: SceneSample?, audio: AudioLevels = .silent, seconds: Double, dt: Double = 0.05) -> MovieFrame {
        var out = MovieFrame(left: .black, right: .black, source: .picture)
        for _ in 0 ..< Int(seconds / dt) { out = f.step(scene: scene, audio: audio, dt: dt) }
        return out
    }

    @Test func settlesOnASteadyScene() {
        var f = MovieFollower()
        let target = LinearColor(0.4, 0.2, 0.05)
        let out = run(&f, scene: scene(target), seconds: 6)
        #expect(out.source == .picture)
        #expect(out.left.r > out.left.g && out.left.g > out.left.b)
        #expect(out.left == out.right)
    }

    @Test func splitSidesStaySplit() {
        var f = MovieFollower()
        let out = run(&f, scene: scene(LinearColor(0.5, 0.25, 0.02), LinearColor(0.6, 0.55, 0.4)), seconds: 6)
        #expect(out.right.b > out.left.b)
        #expect(out.left.r > out.left.b)
    }

    @Test func brightnessRisesFasterThanItFalls() {
        // Steps small enough not to count as a cut. Progress is measured on the first frame after the change.
        func firstStepProgress(from a: Float, to b: Float) -> Double {
            var f = MovieFollower()
            let start = run(&f, scene: scene(LinearColor(a, a, a)), seconds: 4).left.g
            let end = run(&f, scene: scene(LinearColor(b, b, b)), seconds: 6).left.g
            var g = MovieFollower()
            _ = run(&g, scene: scene(LinearColor(a, a, a)), seconds: 4)
            let first = g.step(scene: scene(LinearColor(b, b, b)), audio: .silent, dt: 0.05).left.g
            return (Double(first) - Double(start)) / (Double(end) - Double(start))
        }
        #expect(firstStepProgress(from: 0.25, to: 0.5) > 0.5)
        #expect(firstStepProgress(from: 0.5, to: 0.25) < 0.5)
    }

    @Test func aHardCutSnapsToTheNewColour() {
        var f = MovieFollower()
        _ = run(&f, scene: scene(LinearColor(0.7, 0.1, 0.05)), seconds: 4)
        let out = f.step(scene: scene(LinearColor(0.05, 0.1, 0.7)), audio: .silent, dt: 0.05)
        #expect(out.left.b > out.left.r)
    }

    @Test func darkScenesDimButKeepTheirColour() {
        var f = MovieFollower()
        _ = run(&f, scene: scene(LinearColor(0.4, 0.2, 0.05)), seconds: 3)
        let out = run(&f, scene: scene(LinearColor(0.02, 0.01, 0.0025)), seconds: 6)
        #expect(out.left.r > out.left.b)
        #expect(out.left.r < 120)
    }

    /// A screen edge as the capture reports it (sRGB bytes), as linear light.
    func screen(_ r: Int, _ g: Int, _ b: Int) -> LinearColor {
        LinearColor(SRGB.decodeTable[r], SRGB.decodeTable[g], SRGB.decodeTable[b])
    }

    @Test func aMutedFilmSceneStillComesOutVivid() {
        // Edge averages measured from a real film on the default settings, which first came out dull.
        var warm = MovieFollower()
        let amber = run(&warm, scene: scene(screen(64, 57, 50)), seconds: 6).left
        #expect(max(amber.r, amber.g, amber.b) > 120) // a mid-dim scene is no longer a faint glow
        #expect(Int(amber.r) - Int(amber.b) > 60) // and the warm cast shows as colour, not off-white

        var cool = MovieFollower()
        let blue = run(&cool, scene: scene(screen(61, 79, 89)), seconds: 6).left
        #expect(blue.b > blue.r + 60)
    }

    @Test func neutralGreyStaysWhiteAndDarkStaysDark() {
        var grey = MovieFollower()
        let out = run(&grey, scene: scene(screen(80, 80, 80)), seconds: 6).left
        #expect(close(out.r, out.g, within: 4) && close(out.g, out.b, within: 4)) // no invented tint
        #expect(out.g > 100)

        var dark = MovieFollower()
        let night = run(&dark, scene: scene(screen(13, 7, 8)), seconds: 6).left
        #expect(max(night.r, night.g, night.b) < 70) // a near-black scene is still dim
    }

    @Test func intensityZeroIsLeastVividAndOneIsMost() {
        func peak(_ intensity: Double) -> (brightness: Int, tint: Int) {
            var f = MovieFollower(settings: MovieSettings(intensity: intensity, smoothness: 0.5))
            let c = run(&f, scene: scene(screen(64, 57, 50)), seconds: 6).left
            return (Int(max(c.r, c.g, c.b)), Int(c.r) - Int(c.b))
        }
        #expect(peak(0).brightness < peak(0.5).brightness && peak(0.5).brightness < peak(1).brightness)
        #expect(peak(0).tint < peak(0.5).tint && peak(0.5).tint < peak(1).tint)
    }

    @Test func theFlashLimiterCapsStrobing() {
        var f = MovieFollower()
        var levels: [Int] = []
        // White/black every 50 ms for three seconds.
        for i in 0 ..< 60 {
            let c = i % 2 == 0 ? LinearColor(1, 1, 1) : LinearColor.zero
            levels.append(Int(f.step(scene: scene(c), audio: .silent, dt: 0.05).left.g))
        }
        // Total movement in any one second of output, in 0...1 units of the 8-bit range.
        var worst = 0.0
        for start in 0 ..< (levels.count - 20) {
            var total = 0.0
            for i in start + 1 ..< start + 20 { total += abs(Double(levels[i] - levels[i - 1])) / 255 }
            worst = max(worst, total)
        }
        // The limiter works on linear brightness; the output is gamma encoded, so allow headroom over the raw limit.
        #expect(worst < 10)
        #expect(levels.contains { $0 > 100 })
    }

    @Test func blankScreenHandsOverToTheSoundtrackAfterAMoment() {
        var f = MovieFollower()
        _ = run(&f, scene: scene(LinearColor(0.4, 0.3, 0.2)), seconds: 2)
        var out = run(&f, scene: scene(.zero, blank: true), seconds: 1)
        #expect(out.source == .picture) // not yet: the screen may just be fading
        out = run(&f, scene: scene(.zero, blank: true), seconds: 1)
        #expect(out.source == .soundtrack)
        // And the picture takes over again as soon as it can be read.
        out = f.step(scene: scene(LinearColor(0.4, 0.3, 0.2)), audio: .silent, dt: 0.05)
        #expect(out.source == .picture)
    }

    @Test func aBassImpactOnTheRightFlaresTheRightSpeaker() {
        var f = MovieFollower()
        let quiet = SpeakerLevel(overall: 0.1, bass: 0.05, mid: 0.1, treble: 0.05)
        let boom = SpeakerLevel(overall: 0.9, bass: 1, mid: 0.6, treble: 0.4)
        _ = run(&f, scene: nil, audio: AudioLevels(left: quiet, right: quiet), seconds: 3)
        let out = run(&f, scene: nil, audio: AudioLevels(left: quiet, right: boom), seconds: 0.4)
        #expect(out.source == .soundtrack)
        #expect(Int(out.right.r) + Int(out.right.g) > Int(out.left.r) + Int(out.left.g) + 100)
        #expect(out.right.r > out.right.b) // warm, not the cool ambient
        #expect(out.left.b > out.left.r) // the quiet side stays cool
    }

    @Test func silenceStaysDimButNotOff() {
        var f = MovieFollower()
        let out = run(&f, scene: nil, audio: .silent, seconds: 4)
        #expect(out.source == .soundtrack)
        #expect(out.left.b > 0 && out.left.b < 90)
    }
}
