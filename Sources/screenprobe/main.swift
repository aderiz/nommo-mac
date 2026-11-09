import CoreGraphics
import CoreMedia
import Darwin
import Foundation
@preconcurrency import ScreenCaptureKit

// screenprobe: a read-only test of what a Mac app can see of the screen.
//
// It captures a tiny copy of one display and prints, once a second, the average colour, how much of the picture is
// exactly black, and the colour at the left and right edges (what a speaker beside the screen would show).
// It never opens the speaker and writes nothing to disk.
//
//   screenprobe [seconds] [--display N]
//
// Play something in the app you want to test. Protected video usually arrives as exactly black (0, 0, 0) even though it
// is visible on the screen. A genuinely dark scene is almost never exactly black across the whole picture.

func say(_ s: String) { print(s); fflush(stdout) }

struct Window {
    var frames = 0
    var r = 0.0, g = 0.0, b = 0.0
    var exactBlack = 0.0
    var lr = 0.0, lg = 0.0, lb = 0.0
    var rr = 0.0, rg = 0.0, rb = 0.0
}

final class Probe: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "screenprobe")
    // Everything below is only touched on `queue`.
    private var window = Window()
    private(set) var secondsWithFrames = 0
    private(set) var secondsBlack = 0
    private(set) var secondsIdle = 0
    private(set) var totalFrames = 0
    private var timer: DispatchSourceTimer?
    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func startReporting() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.report() }
        t.resume()
        timer = t
    }

    func stopReporting() { queue.sync { timer?.cancel(); timer = nil } }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        say("stream stopped: \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        guard w > 0, h > 0 else { return }
        let edge = max(1, w / 5)

        var sum = (0.0, 0.0, 0.0), left = (0.0, 0.0, 0.0), right = (0.0, 0.0, 0.0)
        var nLeft = 0.0, nRight = 0.0, zero = 0.0
        for y in 0 ..< h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0 ..< w {
                // BGRA
                let b = Double(row[x * 4]), g = Double(row[x * 4 + 1]), r = Double(row[x * 4 + 2])
                sum.0 += r; sum.1 += g; sum.2 += b
                if row[x * 4] == 0, row[x * 4 + 1] == 0, row[x * 4 + 2] == 0 { zero += 1 }
                if x < edge { left.0 += r; left.1 += g; left.2 += b; nLeft += 1 }
                if x >= w - edge { right.0 += r; right.1 += g; right.2 += b; nRight += 1 }
            }
        }
        let n = Double(w * h)
        let (fSum, fLeft, fRight, fNLeft, fNRight, fZero) = (sum, left, right, nLeft, nRight, zero)
        queue.async { [self] in
            window.frames += 1
            totalFrames += 1
            window.r += fSum.0 / n; window.g += fSum.1 / n; window.b += fSum.2 / n
            window.exactBlack += fZero / n
            window.lr += fLeft.0 / fNLeft; window.lg += fLeft.1 / fNLeft; window.lb += fLeft.2 / fNLeft
            window.rr += fRight.0 / fNRight; window.rg += fRight.1 / fNRight; window.rb += fRight.2 / fNRight
        }
    }

    private func report() {
        let w = window
        window = Window()
        let now = clock.string(from: Date())
        guard w.frames > 0 else {
            secondsIdle += 1
            say("\(now)  no new frames (screen not changing, or the stream is not delivering)")
            return
        }
        secondsWithFrames += 1
        let f = Double(w.frames)
        let avg = (w.r / f, w.g / f, w.b / f)
        let black = w.exactBlack / f
        let luma = 0.2126 * avg.0 + 0.7152 * avg.1 + 0.0722 * avg.2
        let exactlyBlack = black > 0.995
        let nearlyBlack = !exactlyBlack && black > 0.7 && luma < 15
        if exactlyBlack || nearlyBlack { secondsBlack += 1 }
        func c(_ r: Double, _ g: Double, _ b: Double) -> String {
            String(format: "(%3.0f,%3.0f,%3.0f)", r, g, b)
        }
        say(String(format: "%@  frames %2d  avg %@  luma %3.0f  exact-black %5.1f%%  L %@  R %@  %@",
                   now, w.frames, c(avg.0, avg.1, avg.2), luma, black * 100,
                   c(w.lr / f, w.lg / f, w.lb / f), c(w.rr / f, w.rg / f, w.rb / f),
                   exactlyBlack ? "BLACK" : nearlyBlack ? "NEARLY BLACK" : "live"))
    }
}

func cpuSeconds() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    return s(u.ru_utime) + s(u.ru_stime)
}

func run() async throws {
    var duration = 90.0
    var displayIndex: Int?
    var args = Array(CommandLine.arguments.dropFirst())[...]
    while let a = args.popFirst() {
        if a == "--display", let v = args.popFirst(), let i = Int(v) { displayIndex = i }
        else if let d = Double(a) { duration = d }
        else { say("usage: screenprobe [seconds] [--display N]"); exit(2) }
    }

    if !CGPreflightScreenCaptureAccess() {
        say("Screen Recording is not allowed for this terminal yet. macOS will ask now; allow it under")
        say("System Settings > Privacy & Security > Screen & System Audio Recording, then run this again.")
        _ = CGRequestScreenCaptureAccess()
    }

    let content: SCShareableContent
    do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    catch { say("cannot read the screen: \(error.localizedDescription)"); exit(1) }

    let displays = content.displays
    guard !displays.isEmpty else { say("no displays found"); exit(1) }
    for (i, d) in displays.enumerated() {
        say("display \(i): \(d.width)x\(d.height)\(d.displayID == CGMainDisplayID() ? "  (main)" : "")")
    }
    let display = displayIndex.flatMap { displays.indices.contains($0) ? displays[$0] : nil }
        ?? displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays[0]

    let config = SCStreamConfiguration()
    config.width = 96
    config.height = max(1, Int((96.0 * Double(display.height) / Double(display.width)).rounded()))
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.minimumFrameInterval = CMTime(value: 1, timescale: 20)
    config.queueDepth = 3
    config.showsCursor = false
    config.capturesAudio = false
    config.colorSpaceName = CGColorSpace.sRGB

    let seconds = duration
    let probe = Probe()
    let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: probe)
    try stream.addStreamOutput(probe, type: .screen, sampleHandlerQueue: probe.queue)

    say("")
    say("capturing \(config.width)x\(config.height) from the chosen display for \(Int(duration)) s. Play something now; Ctrl-C stops early.")
    say("")
    probe.startReporting()
    let cpuStart = cpuSeconds()
    let wallStart = Date()
    try await stream.startCapture()

    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let stopped = AsyncStream<Void> { continuation in
        sigint.setEventHandler { continuation.yield() }
        sigint.resume()
    }
    await withTaskGroup(of: Void.self) { group in
        group.addTask { try? await Task.sleep(for: .seconds(seconds)) }
        group.addTask { for await _ in stopped { return } }
        await group.next()
        group.cancelAll()
    }

    try? await stream.stopCapture()
    probe.stopReporting()
    let wall = Date().timeIntervalSince(wallStart)
    let cpu = cpuSeconds() - cpuStart

    probe.queue.sync {
        say("")
        say("seconds with frames: \(probe.secondsWithFrames)   black or nearly black: \(probe.secondsBlack)   idle: \(probe.secondsIdle)")
        say(String(format: "frames received: %d   this process used %.1f%% of one core (the system's own capture work is extra; see replayd and WindowServer in Activity Monitor)",
                   probe.totalFrames, cpu / max(wall, 0.001) * 100))
    }
}

do { try await run() } catch { say("error: \(error)"); exit(1) }
