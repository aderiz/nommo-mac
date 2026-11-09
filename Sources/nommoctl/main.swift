import Foundation
import NommoKit

// nommoctl: small command-line front end for NommoKit.
//   nommoctl info
//   nommoctl brightness <0-255>
//   nommoctl color <r> <g> <b> [seconds]      solid colour on both speakers, held while running
//   nommoctl split <r g b> <r g b> [seconds]  left colour then right colour
//   nommoctl effect <spectrum|breathing> [seconds]
//   nommoctl eq-preset <game|music|movie|custom>
//   nommoctl eq <b1> ... <b10>                raw band values (12 = flat)
//   nommoctl movie [seconds] [intensity] [smoothness]
//                                             speakers extend the screen (falls back to the soundtrack)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    fail("usage: nommoctl info | brightness N | color R G B [secs] | split R G B R G B [secs] | effect spectrum|breathing [secs] | eq-preset NAME | eq b1..b10 | movie [secs] [intensity] [smoothness]")
}

func byte(_ s: String) -> UInt8 {
    guard let v = UInt8(s) else { fail("not a 0-255 number: \(s)") }
    return v
}

func seconds(_ args: ArraySlice<String>, default d: Double) -> Double {
    args.first.flatMap(Double.init) ?? d
}

func hold(_ effect: LightingEffect, device: NommoDevice, for secs: Double) async throws {
    let engine = LightingEngine(device: device) { error in
        FileHandle.standardError.write(Data("lighting failed: \(error)\n".utf8))
    }
    await engine.apply(effect)
    try await Task.sleep(for: .seconds(secs))
    await engine.stop()
}

func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { usage() }
    let transport: IOKitHIDTransport
    do { transport = try IOKitHIDTransport.open() } catch { fail("cannot open the speaker: \(error)") }
    let device = NommoDevice(transport: transport)
    let rest = args.dropFirst()

    switch command {
    case "info":
        print("serial:     \(try await device.serialNumber())")
        print("brightness: \(try await device.brightness())/255")
        print("eq bands:   \(try await device.eqBands())")
    case "brightness":
        guard let v = rest.first else { usage() }
        try await device.setBrightness(byte(v))
        print("brightness now \(try await device.brightness())")
    case "color":
        guard rest.count >= 3 else { usage() }
        let c = RGB(byte(rest[rest.startIndex]), byte(rest[rest.startIndex + 1]), byte(rest[rest.startIndex + 2]))
        let secs = seconds(rest.dropFirst(3), default: 10)
        print("holding \(c) for \(secs)s")
        try await hold(.solid(left: c, right: c), device: device, for: secs)
    case "split":
        guard rest.count >= 6 else { usage() }
        let i = rest.startIndex
        let left = RGB(byte(rest[i]), byte(rest[i + 1]), byte(rest[i + 2]))
        let right = RGB(byte(rest[i + 3]), byte(rest[i + 4]), byte(rest[i + 5]))
        let secs = seconds(rest.dropFirst(6), default: 10)
        print("left \(left), right \(right) for \(secs)s")
        try await hold(.solid(left: left, right: right), device: device, for: secs)
    case "effect":
        guard let name = rest.first else { usage() }
        let secs = seconds(rest.dropFirst(), default: 15)
        let effect: LightingEffect
        switch name {
        case "spectrum": effect = .spectrum(period: 8, offset: 0.5)
        case "breathing": effect = .breathing(first: RGB(0, 150, 255), second: RGB(255, 60, 160), period: 4)
        default: usage()
        }
        try await hold(effect, device: device, for: secs)
    case "eq-preset":
        guard let name = rest.first, let preset = EQPreset.allCases.first(where: { $0.title.lowercased() == name }) else { usage() }
        try await device.setEQPreset(preset)
        print("preset \(preset.title)")
    case "eq":
        guard rest.count == EQ.bandCount else { usage() }
        try await device.setEQBands(rest.map(byte))
        print("bands now \(try await device.eqBands())")
    case "movie":
        let secs = seconds(rest, default: 60)
        let settings = MovieSettings(
            intensity: rest.dropFirst().first.flatMap(Double.init) ?? 0.5,
            smoothness: rest.dropFirst(2).first.flatMap(Double.init) ?? 0.5
        )
        let source = ScreenSceneSource()
        do { try await source.start() } catch { fail("cannot read the screen: \(error)") }
        let monitor = AudioLevelMonitor()
        do { try monitor.start() } catch { print("note: soundtrack fallback is off (\(error))") }
        let engine = LightingEngine(device: device, levels: { monitor.levels }, scene: { source.latest }) { error in
            FileHandle.standardError.write(Data("lighting failed: \(error)\n".utf8))
        }
        await engine.apply(.movie(settings))
        print("movie mode for \(Int(secs)) s, intensity \(settings.intensity), smoothness \(settings.smoothness)")
        let end = Date().addingTimeInterval(secs)
        while Date() < end {
            try await Task.sleep(for: .seconds(1))
            let driving = await engine.movieSource.map { "\($0)" } ?? "-"
            if let scene = source.latest {
                print("driving: \(driving)  screen L \(scene.left.rgb) R \(scene.right.rgb)\(scene.isBlank ? "  BLANK" : "")")
            } else {
                print("driving: \(driving)  no frames yet")
            }
        }
        await engine.stop()
        monitor.stop()
        await source.stop()
    default:
        usage()
    }
}

do { try await run() } catch { fail("error: \(error)") }
