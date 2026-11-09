import Foundation

/// Streams the current effect to the speaker. When streaming stops, the speaker falls back to its own
/// colour cycle, so the engine just stops sending to "release" the lights.
public actor LightingEngine {
    private let device: NommoDevice
    private var effect: LightingEffect = .builtIn
    private var task: Task<Void, Never>?
    private var started = Date()
    private var generation = 0

    /// Called (from the engine's task) when the connection to the speaker fails.
    private let onFailure: @Sendable (Error) -> Void
    /// Source of audio levels for music-reactive effects.
    private let levelSource: @Sendable () -> AudioLevels
    private var smoothedLevels = AudioLevels.silent
    /// Source of the latest reading of the screen for the movie effect.
    private let sceneSource: @Sendable () -> SceneSample?
    private var follower = MovieFollower()
    /// What is driving the movie effect right now; nil when another effect is running.
    public private(set) var movieSource: MovieSource?
    /// Told about the colours being sent (about 10 times a second) so a UI can mirror the speakers.
    private let frameObserver: (@Sendable (_ left: RGB, _ right: RGB) -> Void)?
    private var lastObserved = Date.distantPast

    public init(
        device: NommoDevice,
        levels: @escaping @Sendable () -> AudioLevels = { .silent },
        scene: @escaping @Sendable () -> SceneSample? = { nil },
        frameObserver: (@Sendable (_ left: RGB, _ right: RGB) -> Void)? = nil,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.device = device
        self.levelSource = levels
        self.sceneSource = scene
        self.frameObserver = frameObserver
        self.onFailure = onFailure
    }

    public func apply(_ newEffect: LightingEffect) {
        if case let .movie(settings) = newEffect {
            if case .movie = effect { follower.settings = settings } else { follower = MovieFollower(settings: settings) }
        } else {
            movieSource = nil
        }
        effect = newEffect
        started = Date()
        if newEffect.streams {
            startIfNeeded()
        } else {
            stop()
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        Task { await device.endSoftwareLighting() }
    }

    private func startIfNeeded() {
        guard task == nil else { return }
        generation += 1
        let mine = generation
        task = Task { [weak self] in
            await self?.run(generation: mine)
        }
    }

    private func run(generation mine: Int) async {
        do {
            try await device.beginSoftwareLighting()
            var lastSent = Date.distantPast
            while !Task.isCancelled {
                let current = effect
                let now = Date()
                let t = now.timeIntervalSince(started)
                // Animated effects ~20 fps; static colours just need a keepalive (Synapse re-sends ~every 5 s).
                let interval: TimeInterval = current.isAnimated ? 0.05 : 0.5
                if now.timeIntervalSince(lastSent) >= interval {
                    if current.reactsToAudio {
                        smoothedLevels = smoothedLevels.smoothed(towards: levelSource())
                    }
                    var colors = current.colors(at: t, levels: smoothedLevels)
                    if case let .movie(settings) = current {
                        follower.settings = settings
                        let frame = follower.step(
                            scene: sceneSource(), audio: levelSource(), dt: now.timeIntervalSince(lastSent)
                        )
                        colors = (frame.left, frame.right)
                        movieSource = frame.source
                    }
                    try await device.sendFrame(left: colors.left, right: colors.right)
                    lastSent = now
                    if let frameObserver, now.timeIntervalSince(lastObserved) >= 0.1 {
                        lastObserved = now
                        frameObserver(colors.left, colors.right)
                    }
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch is CancellationError {
            // Normal shutdown.
        } catch {
            onFailure(error)
        }
        if generation == mine { task = nil }
    }
}
