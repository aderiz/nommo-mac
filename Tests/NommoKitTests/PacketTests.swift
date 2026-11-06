import Foundation
import Testing
@testable import NommoKit

@Suite("Razer packet encoding")
struct PacketTests {
    /// A real frame captured from Synapse for Windows:
    /// `07 00 07 00 00 00 29 0f 03 00 00 00 00 0b ff0000 x12 ... 2e 00`
    @Test func matchesSynapseRedFrame() {
        var args: [UInt8] = [0, 0, 0, 0, 0x0B]
        for _ in 0 ..< 12 { args += [0xFF, 0x00, 0x00] }
        let packet = RazerPacket(transactionID: 7, commandClass: 0x0F, commandID: 0x03, arguments: args)
        let bytes = packet.encoded()

        #expect(bytes.count == 91)
        #expect(Array(bytes[0 ... 8]) == [0x07, 0x00, 0x07, 0x00, 0x00, 0x00, 0x29, 0x0F, 0x03])
        #expect(bytes[9 ..< 14] == [0, 0, 0, 0, 0x0B])
        #expect(bytes[89] == 0x2E)
        #expect(bytes[90] == 0x00)
    }

    @Test func roundTripsThroughDecode() {
        let packet = RazerPacket(status: 2, transactionID: 5, commandClass: 0x0F, commandID: 0x04, arguments: [1, 0, 0x80])
        #expect(RazerPacket.decode(packet.encoded()) == packet)
    }

    @Test func rejectsWrongReportID() {
        var bytes = RazerPacket(transactionID: 0, commandClass: 0, commandID: 0).encoded()
        bytes[0] = 0
        #expect(RazerPacket.decode(bytes) == nil)
    }
}

@Suite("EQ scaling")
struct EQTests {
    @Test func flatIsTwelve() {
        #expect(EQ.raw(fromDecibels: 0) == 0x0C)
        #expect(EQ.decibels(fromRaw: 0x0C) == 0)
    }

    @Test func clampsToSpan() {
        #expect(EQ.raw(fromDecibels: 40) == 24)
        #expect(EQ.raw(fromDecibels: -40) == 0)
    }
}

@Suite("Lighting effects")
struct EffectTests {
    @Test func solidIsConstant() {
        let e = LightingEffect.solid(left: RGB(1, 2, 3), right: RGB(4, 5, 6))
        let c = e.colors(at: 123)
        #expect(c.left == RGB(1, 2, 3))
        #expect(c.right == RGB(4, 5, 6))
    }

    @Test func breathingStartsAndEndsDark() {
        let e = LightingEffect.breathing(first: .white, second: .white, period: 4)
        #expect(e.colors(at: 0).left == .black)
        #expect(e.colors(at: 2).left.r > 240) // peak mid-breath
    }

    @Test func breathingAlternatesBetweenTwoColours() {
        let a = RGB(255, 0, 0), b = RGB(0, 0, 255)
        let e = LightingEffect.breathing(first: a, second: b, period: 4)
        #expect(e.colors(at: 2).left == a)   // first breath peaks in the first colour
        #expect(e.colors(at: 6).left == b)   // second breath peaks in the second colour
        #expect(e.colors(at: 10).left == a)  // and back again
        let c = e.colors(at: 2)
        #expect(c.left == c.right)           // both speakers breathe together
    }

    @Test func spectrumStartsRed() {
        let c = LightingEffect.spectrum(period: 10, offset: 0).colors(at: 0)
        #expect(c.left == RGB(255, 0, 0))
    }

    @Test func builtInDoesNotStream() {
        #expect(LightingEffect.builtIn.streams == false)
        #expect(LightingEffect.off.streams == true)
    }
}

@Suite("Stereo widener")
struct WidenerTests {
    @Test func unityWidthIsTransparent() {
        var w = StereoWidener(sampleRate: 48000, width: 1)
        for i in 0 ..< 200 {
            let l = Float(sin(Double(i) * 0.3)), r = Float(cos(Double(i) * 0.17))
            let out = w.process(l, r)
            #expect(abs(out.left - l) < 1e-5)
            #expect(abs(out.right - r) < 1e-5)
        }
    }

    @Test func monoIsUntouchedAtAnyWidth() {
        var w = StereoWidener(sampleRate: 48000, width: 2.5)
        for i in 0 ..< 200 {
            let x = Float(sin(Double(i) * 0.4))
            let out = w.process(x, x)
            #expect(abs(out.left - x) < 1e-5)
            #expect(abs(out.right - x) < 1e-5)
        }
    }

    @Test func widensHighFrequencySide() {
        var w = StereoWidener(sampleRate: 48000, width: 2)
        var peak: Float = 0
        for i in 0 ..< 400 { // out-of-phase 24 kHz-ish content: pure side, well above the crossover
            let s: Float = i % 2 == 0 ? 0.25 : -0.25
            peak = max(peak, abs(w.process(s, -s).left))
        }
        #expect(peak > 0.45) // side doubled: 0.25 -> ~0.5
    }

    @Test func limiterStaysBelowOne() {
        #expect(StereoWidener.softLimit(0.5) == 0.5)
        #expect(abs(StereoWidener.softLimit(5)) <= 1)
        #expect(abs(StereoWidener.softLimit(-5)) <= 1)
    }
}

@Suite("Crosstalk canceller")
struct CrosstalkTests {
    @Test func zeroStrengthIsTransparent() {
        var c = CrosstalkCanceller(sampleRate: 48000, strength: 0)
        for i in 0 ..< 300 {
            let l = Float(sin(Double(i) * 0.21)), r = Float(cos(Double(i) * 0.13))
            let out = c.process(l, r)
            #expect(abs(out.left - l) < 1e-5)
            #expect(abs(out.right - r) < 1e-5)
        }
    }

    @Test func staysStableOnLoudNoiseAtFullStrength() {
        var c = CrosstalkCanceller(sampleRate: 48000, strength: 1)
        var generator = SystemRandomNumberGenerator()
        var peak: Float = 0
        for _ in 0 ..< 200_000 {
            let l = Float.random(in: -1 ... 1, using: &generator)
            let r = Float.random(in: -1 ... 1, using: &generator)
            let out = c.process(l, r)
            #expect(out.left.isFinite && out.right.isFinite)
            peak = max(peak, abs(out.left), abs(out.right))
        }
        #expect(peak < 8)
    }

    @Test func leftOnlySignalBleedsInvertedIntoRight() {
        var c = CrosstalkCanceller(sampleRate: 48000, strength: 1)
        var rightPeak: Float = 0
        for i in 0 ..< 2000 { // 3 kHz tone on the left channel only
            let x = Float(sin(Double(i) * 2 * Double.pi * 3000 / 48000))
            rightPeak = max(rightPeak, abs(c.process(x, 0).right))
        }
        #expect(rightPeak > 0.2) // the right speaker now carries the cancelling signal
    }

    @Test func bassPassesThroughNearlyUnchanged() {
        var c = CrosstalkCanceller(sampleRate: 48000, strength: 1)
        var maxError: Float = 0
        for i in 0 ..< 4000 { // 40 Hz mono bass
            let x = Float(sin(Double(i) * 2 * Double.pi * 40 / 48000))
            let out = c.process(x, x)
            if i > 2000 { maxError = max(maxError, abs(out.left - x)) }
        }
        #expect(maxError < 0.35)
    }
}

@Suite("Audio levels")
struct LevelTests {
    private func feed(_ analyzer: AudioLevelAnalyzer, left: (Int) -> Float, right: (Int) -> Float, buffers: Int = 400) {
        for b in 0 ..< buffers {
            var l = [Float](repeating: 0, count: 480), r = l
            for i in 0 ..< 480 { l[i] = left(b * 480 + i); r[i] = right(b * 480 + i) }
            l.withUnsafeBufferPointer { lp in r.withUnsafeBufferPointer { rp in
                analyzer.push(left: lp.baseAddress!, right: rp.baseAddress!, frames: 480)
            } }
        }
    }

    private func tone(_ hz: Double, _ amp: Float) -> (Int) -> Float {
        { i in amp * Float(sin(2 * Double.pi * hz * Double(i) / 48000)) }
    }

    @Test func silenceIsZero() {
        let a = AudioLevelAnalyzer(sampleRate: 48000)
        feed(a, left: { _ in 0 }, right: { _ in 0 })
        #expect(a.levels == .silent)
    }

    @Test func leftOnlyToneLightsOnlyTheLeft() {
        let a = AudioLevelAnalyzer(sampleRate: 48000)
        feed(a, left: tone(1000, 0.5), right: { _ in 0 })
        #expect(a.levels.left.overall > 0.8)
        #expect(a.levels.right.overall == 0)
    }

    @Test func bandsSeparate() {
        let bass = AudioLevelAnalyzer(sampleRate: 48000)
        feed(bass, left: tone(60, 0.5), right: tone(60, 0.5))
        #expect(bass.levels.left.bass > 0.8)
        #expect(bass.levels.left.treble < 0.1)

        let treble = AudioLevelAnalyzer(sampleRate: 48000)
        feed(treble, left: tone(8000, 0.5), right: tone(8000, 0.5))
        #expect(treble.levels.left.treble > 0.8)
        #expect(treble.levels.left.bass < 0.1)
    }

    @Test func autoGainMakesQuietMusicVisible() {
        let a = AudioLevelAnalyzer(sampleRate: 48000)
        feed(a, left: tone(1000, 0.01), right: tone(1000, 0.01))
        #expect(a.levels.left.overall > 0.8) // nothing louder has been heard, so this is "full scale"
    }
}

@Suite("Music effect")
struct MusicEffectTests {
    @Test func pulseFollowsLevelAndNeverGoesFullyDark() {
        let e = LightingEffect.music(left: .white, right: .white, style: .pulse, sensitivity: 1)
        let quiet = e.colors(at: 0, levels: .silent).left
        let loud = e.colors(at: 0, levels: AudioLevels(
            left: SpeakerLevel(overall: 1, bass: 1, mid: 1, treble: 1), right: .silent
        )).left
        #expect(quiet.r > 0 && quiet.r < 30)
        #expect(loud == .white)
    }

    @Test func colourMixMapsBandsToChannels() {
        let e = LightingEffect.music(left: .white, right: .white, style: .colorMix, sensitivity: 1)
        let level = SpeakerLevel(overall: 1, bass: 1, mid: 0.5, treble: 0)
        let c = e.colors(at: 0, levels: AudioLevels(left: level, right: .silent)).left
        #expect(c.r == 255)
        #expect(c.g > 100 && c.g < 150)
        #expect(c.b == 0)
    }
}

@Suite("EQ profiles")
struct ProfileTests {
    @Test func codableRoundTrip() throws {
        let profile = EQProfile(name: "Bass boost", decibels: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0])
        let data = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([EQProfile].self, from: data)
        #expect(decoded == [profile])
    }

    @Test func profilesHaveDistinctIdentities() {
        let a = EQProfile(name: "A", decibels: Array(repeating: 0, count: EQ.bandCount))
        let b = EQProfile(name: "A", decibels: Array(repeating: 0, count: EQ.bandCount))
        #expect(a != b)
        #expect(a.id != b.id)
    }
}
