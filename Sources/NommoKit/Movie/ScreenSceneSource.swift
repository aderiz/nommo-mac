import CoreGraphics
import CoreMedia
import Foundation
import os
@preconcurrency import ScreenCaptureKit

public enum ScreenSceneError: Error, CustomStringConvertible {
    case noPermission
    case noDisplay

    public var description: String {
        switch self {
        case .noPermission: "Screen recording is not allowed. Allow it in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .noDisplay: "No display found to watch."
        }
    }
}

/// Watches a display and keeps the latest `SceneSample`. It captures a tiny copy of the screen (about 96 pixels
/// wide, at most 20 times a second), so the cost is small. Protected video (Safari, the Apple TV and Netflix apps,
/// Chrome with hardware acceleration on) arrives black; the sample then reports `isBlank`.
public final class ScreenSceneSource: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public static let captureWidth = 96

    private let queue = DispatchQueue(label: "ai.amplified.nommo.screen", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())
    // Touched only on `queue`.
    private var reader = SceneReader()
    private var stream: SCStream?

    private struct State {
        var sample: SceneSample?
        var running = false
        var error: String?
    }

    override public init() { super.init() }

    /// Latest reading of the screen, or nil before the first frame.
    public var latest: SceneSample? { state.withLock { $0.sample } }
    public var isRunning: Bool { state.withLock { $0.running } }
    /// Why capture stopped, if the system ended it.
    public var lastError: String? { state.withLock { $0.error } }

    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Starts watching `displayID`, or the main display.
    public func start(displayID: CGDirectDisplayID? = nil) async throws {
        guard !isRunning else { return }
        guard Self.hasPermission else {
            Self.requestPermission()
            throw ScreenSceneError.noPermission
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let wanted = displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else {
            throw ScreenSceneError.noDisplay
        }

        let config = SCStreamConfiguration()
        config.width = Self.captureWidth
        config.height = max(1, Int((Double(Self.captureWidth) * Double(display.height) / Double(display.width)).rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        config.colorSpaceName = CGColorSpace.sRGB

        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        queue.sync { reader = SceneReader() }
        self.stream = stream
        state.withLock { $0 = State(running: true) }
    }

    public func stop() async {
        let stream = self.stream
        self.stream = nil
        try? await stream?.stopCapture()
        state.withLock { $0 = State() }
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let sample = reader.read(
            bgra: base, width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels)
        )
        state.withLock { $0.sample = sample }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        state.withLock {
            $0.running = false
            $0.error = error.localizedDescription
        }
    }
}
