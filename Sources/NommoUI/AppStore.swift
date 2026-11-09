import AppKit
import Foundation
import NommoKit
import Observation

@MainActor
@Observable
public final class AppStore {
    public enum Status: Equatable {
        case searching
        case connected(serial: String)
        case unavailable(String)
    }

    public private(set) var status: Status = .searching
    var settings: Settings
    /// Colours the engine is currently sending (for animated effects), mirrored in the UI.
    private(set) var observedLeft = RGB.black
    private(set) var observedRight = RGB.black
    /// The EQ preset the speaker reports as active; nil until known.
    private(set) var activePreset: EQPreset?
    /// True while the speaker's band registers hold a music style's curve rather than the user's own Custom curve.
    private(set) var bandsHoldMusicGenre = false
    /// Set when spatial audio could not start (permission denied, speaker output missing, …).
    private(set) var spatialProblem: String?
    /// Set when Music or Movie lighting could not listen to system audio.
    private(set) var audioProblem: String?
    /// Set when Movie mode could not read the screen.
    private(set) var movieProblem: String?
    /// True while Screen Recording has not been allowed, so the interface can offer to open Settings.
    private(set) var movieNeedsPermission = false
    /// What is driving the lights in Movie mode: the picture, or the soundtrack when the picture can't be read.
    private(set) var movieSource: MovieSource?
    /// Whether the app opens at login, and whether macOS is waiting for the user to approve that.
    private(set) var launchAtLogin = LoginItem.isEnabled
    private(set) var loginNeedsApproval = LoginItem.needsApproval
    private(set) var loginProblem: String?

    @ObservationIgnored private var device: NommoDevice?
    @ObservationIgnored private var engine: LightingEngine?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var brightnessTask: Task<Void, Never>?
    @ObservationIgnored private var eqTask: Task<Void, Never>?
    @ObservationIgnored private let spatial = SpatialAudio()
    @ObservationIgnored private let levelMonitor = AudioLevelMonitor()
    @ObservationIgnored private let screen = ScreenSceneSource()
    @ObservationIgnored private var movieTask: Task<Void, Never>?

    public init() {
        isPreview = false
        settings = Settings.load()
        monitor = Task { [weak self] in await self?.monitorConnection() }
    }

    /// A store with fixed state and no hardware, for snapshots and previews.
    init(
        preview settings: Settings, status: Status = .connected(serial: "000000000000000"), preset: EQPreset? = .custom,
        movie: (source: MovieSource?, problem: String?, needsPermission: Bool) = (.picture, nil, false),
        playingMusicGenre: Bool = false
    ) {
        self.settings = settings
        self.status = status
        self.activePreset = preset
        self.bandsHoldMusicGenre = playingMusicGenre
        self.isPreview = true
        launchAtLogin = false
        loginNeedsApproval = false
        movieSource = movie.source
        movieProblem = movie.problem
        movieNeedsPermission = movie.needsPermission
    }

    @ObservationIgnored let isPreview: Bool

    /// True while a music style (not the speaker's own Music tuning) is what you hear.
    var musicGenreLive: Bool {
        bandsHoldMusicGenre && activePreset == .custom && settings.musicGenre != .standard
    }

    /// The style the speaker is playing under Music; `.standard` when it is on its own tuning.
    var shownGenre: MusicGenre { musicGenreLive ? settings.musicGenre : .standard }

    /// The preset the interface shows as chosen. A music style runs through the speaker's Custom EQ but belongs
    /// under Music.
    var shownPreset: EQPreset? { musicGenreLive ? .music : activePreset }

    /// Colours to show on the stage, or nil when the speakers run their own cycle and we can't know them.
    var stageColors: (left: RGB, right: RGB)? {
        switch settings.kind {
        case .builtIn: nil
        case .off: (.black, .black)
        case .solid: (settings.left, settings.right)
        case .breathing: isPreview ? (settings.breathFirst, settings.breathFirst) : (observedLeft, observedRight)
        case .spectrum, .music, .movie: isPreview ? (settings.left, settings.right) : (observedLeft, observedRight)
        }
    }

    /// Colours for the window's glow: the speakers' hues at full strength, so the UI stays colourful even when
    /// the lights are momentarily dark (Music with nothing playing, the dark gap in a breath). nil = cycling.
    var auroraColors: (left: RGB, right: RGB)? {
        guard let live = stageColors else { return nil }
        func vivid(_ c: RGB, fallback: RGB) -> RGB {
            let peak = max(c.r, c.g, c.b)
            guard peak >= 24 else { return fallback }
            let scale = 255 / Double(peak)
            func up(_ v: UInt8) -> UInt8 { UInt8(min(255, (Double(v) * scale).rounded())) }
            return RGB(up(c.r), up(c.g), up(c.b))
        }
        return (vivid(live.left, fallback: settings.left), vivid(live.right, fallback: settings.right))
    }

    /// The interface accent is the colour the user chose for the lights, so the UI echoes what they set.
    var accent: Accent { Accent(rgb: settings.kind == .breathing ? settings.breathFirst : settings.left) }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    // MARK: - Connection

    private func monitorConnection() async {
        while !Task.isCancelled {
            if device == nil {
                await connect()
            } else if !IOKitHIDTransport.isDevicePresent() {
                disconnect(reason: "Speaker unplugged")
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func connect() async {
        guard IOKitHIDTransport.isDevicePresent() else {
            status = .unavailable("Nommo V2 Pro not found")
            return
        }
        do {
            let transport = try IOKitHIDTransport.open()
            let device = NommoDevice(transport: transport)
            let serial = try await device.serialNumber()
            let bands = try await device.eqBands()
            let monitor = levelMonitor
            let screen = screen
            let engine = LightingEngine(
                device: device,
                levels: { monitor.levels },
                scene: { screen.latest },
                frameObserver: { [weak self] left, right in
                    Task { @MainActor in
                        self?.observedLeft = left
                        self?.observedRight = right
                    }
                }
            ) { [weak self] error in
                Task { @MainActor in self?.disconnect(reason: "Lost connection: \(error)") }
            }
            self.device = device
            self.engine = engine
            adoptEQ(preset: try? await device.eqPreset(), bands: bands)
            status = .connected(serial: serial)
            try await device.setBrightness(brightnessByte)
            await engine.apply(settings.effect)
            updateLevelMonitor()
            updateMovie()
            applySpatial()
        } catch NommoError.openFailed {
            status = .unavailable("Speaker is in use by another app (Synapse or a virtual machine?)")
        } catch {
            status = .unavailable("Could not talk to the speaker: \(error)")
            device = nil
            engine = nil
        }
    }

    private func disconnect(reason: String) {
        spatial.stop()
        levelMonitor.stop()
        let engine = engine
        Task { await engine?.stop() }
        device = nil
        self.engine = nil
        status = .unavailable(reason)
        updateMovie()
    }

    func reconnect() {
        disconnect(reason: "Reconnecting…")
        status = .searching
    }

    // MARK: - Changes from the UI

    private var brightnessByte: UInt8 { UInt8((settings.brightness * 255).rounded()) }

    func lightingChanged() {
        settings.save()
        updateLevelMonitor()
        updateMovie()
        guard let engine else { return }
        let effect = settings.effect
        Task { await engine.apply(effect) }
    }

    /// Listens to system audio only while an effect that reacts to it is selected: Music, and Movie for its
    /// soundtrack fallback.
    private func updateLevelMonitor() {
        guard isConnected, settings.kind == .music || settings.kind == .movie else {
            levelMonitor.stop()
            audioProblem = nil
            return
        }
        do {
            try levelMonitor.start()
            audioProblem = nil
        } catch {
            levelMonitor.stop()
            let allow = "Allow System Audio Recording for Nommo in System Settings → Privacy & Security."
            audioProblem = settings.kind == .movie
                ? "Allow System Audio Recording for protected video."
                : "Couldn't listen to system audio: \(error). \(allow)"
        }
    }

    // MARK: - Movie

    /// Watches the screen only while Movie is selected. Safe to call on every lighting change.
    private func updateMovie() {
        if isConnected, settings.kind == .movie, !isPreview {
            guard movieTask == nil else { return }
            movieTask = Task { [weak self] in await self?.superviseMovie() }
        } else {
            movieTask?.cancel()
            movieTask = nil
            movieSource = nil
            movieProblem = nil
            movieNeedsPermission = false
            let screen = screen
            Task { await screen.stop() }
        }
    }

    /// Keeps screen capture running while Movie is selected (the system ends it when a display sleeps or changes),
    /// and mirrors what the engine reports it is following.
    private func superviseMovie() async {
        var asked = false
        var retryAt = Date.distantPast
        while !Task.isCancelled {
            // Ask for Screen Recording once; after that only try again once it has been allowed.
            if !screen.isRunning, Date() >= retryAt, ScreenSceneSource.hasPermission || !asked {
                asked = true
                do {
                    try await screen.start()
                    movieProblem = nil
                    movieNeedsPermission = false
                } catch ScreenSceneError.noPermission {
                    movieNeedsPermission = true
                    movieProblem = "Allow Nommo to record the screen in Privacy & Security. Until then the lights follow the sound."
                } catch {
                    movieNeedsPermission = false
                    movieProblem = "Couldn't read the screen. Trying again…"
                    retryAt = Date().addingTimeInterval(3)
                }
            }
            if screen.isRunning, movieProblem != nil {
                movieProblem = nil
                movieNeedsPermission = false
            }
            if let engine { movieSource = await engine.movieSource }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func brightnessChanged() {
        settings.save()
        brightnessTask?.cancel()
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, let device else { return }
            try? await device.setBrightness(brightnessByte)
        }
    }

    /// Runs speaker EQ writes one after another, so quick changes can't interleave and leave the speaker with a
    /// mix of two of them.
    private func queueEQ(_ work: @escaping @MainActor () async -> Void) {
        let previous = eqTask
        previous?.cancel()
        eqTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        }
    }

    /// Takes the speaker's own EQ state as the truth. Bands that hold a music style's curve aren't the user's Custom
    /// curve, so the one saved here is kept.
    private func adoptEQ(preset: EQPreset?, bands: [UInt8]) {
        if let style = MusicGenre.matching(rawBands: bands) {
            bandsHoldMusicGenre = true
            if preset == .custom {
                settings.musicGenre = style
                settings.save()
            }
        } else {
            bandsHoldMusicGenre = false
            settings.eqDecibels = bands.map(EQ.decibels(fromRaw:))
        }
        activePreset = preset
    }

    /// Runs a speaker write, once more if it fails: the speaker now and then times out on a single command.
    private func retrying(_ operation: () async throws -> Void) async -> Bool {
        for attempt in 0 ..< 2 {
            do { try await operation(); return true } catch {
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(250)) }
            }
        }
        return false
    }

    func selectPreset(_ preset: EQPreset) {
        guard let device else { return }
        queueEQ { [self] in
            if preset == .music, settings.musicGenre != .standard {
                // Music plays the chosen style, which the speaker holds as a Custom curve.
                let genre = settings.musicGenre
                if await retrying({ try await device.setMusicGenre(genre) }) {
                    activePreset = .custom
                    bandsHoldMusicGenre = true
                } else if let bands = try? await device.eqBands() {
                    // A write failed part-way: show what the speaker really has rather than what was asked for.
                    adoptEQ(preset: try? await device.eqPreset(), bands: bands)
                }
                return
            }
            try? await device.setEQPreset(preset)
            activePreset = (try? await device.eqPreset()) ?? preset
            guard activePreset == .custom else { return }
            if bandsHoldMusicGenre {
                // The bands still hold a music style's curve: put the user's own Custom curve back.
                let raw = settings.eqDecibels.map(EQ.raw(fromDecibels:))
                if await retrying({ try await device.setEQBands(raw) }) {
                    bandsHoldMusicGenre = false
                } else if let bands = try? await device.eqBands() {
                    adoptEQ(preset: try? await device.eqPreset(), bands: bands)
                }
            } else if let bands = try? await device.eqBands() {
                // Built-in presets don't change the band registers, but Custom may reset them: show what the speaker has.
                settings.eqDecibels = bands.map(EQ.decibels(fromRaw:))
                settings.save()
            }
        }
    }

    /// Chooses a style under Music. `.standard` goes back to the speaker's own Music tuning.
    func selectGenre(_ genre: MusicGenre) {
        settings.musicGenre = genre
        settings.save()
        selectPreset(.music)
    }

    /// Starts the Custom EQ from the style being played. The speaker already holds that curve, so nothing is sent.
    func editGenreAsCustom() {
        guard musicGenreLive, let curve = settings.musicGenre.decibels else {
            selectPreset(.custom)
            return
        }
        settings.eqDecibels = curve
        settings.activeEQProfile = nil
        settings.save()
        bandsHoldMusicGenre = false
    }

    /// Called only when the user drags a band, never when values are read back from the speaker.
    func setBand(_ index: Int, to decibels: Double) {
        guard settings.eqDecibels.indices.contains(index) else { return }
        settings.eqDecibels[index] = decibels
        writeEQ()
    }

    func resetEQ() {
        settings.eqDecibels = Array(repeating: 0, count: EQ.bandCount)
        writeEQ()
    }

    // MARK: - EQ profiles

    var activeProfile: EQProfile? {
        settings.eqProfiles.first { $0.id == settings.activeEQProfile }
    }

    /// True when the live curve differs from the saved profile it started from.
    var profileIsModified: Bool {
        guard let profile = activeProfile else { return false }
        return profile.decibels != settings.eqDecibels
    }

    func applyProfile(_ id: UUID) {
        guard let profile = settings.eqProfiles.first(where: { $0.id == id }) else { return }
        settings.eqDecibels = profile.decibels
        settings.activeEQProfile = id
        writeEQ()
    }

    func saveCurrentAsProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = EQProfile(name: trimmed, decibels: settings.eqDecibels)
        settings.eqProfiles.append(profile)
        settings.activeEQProfile = profile.id
        settings.save()
    }

    func updateActiveProfile() {
        guard let index = settings.eqProfiles.firstIndex(where: { $0.id == settings.activeEQProfile }) else { return }
        settings.eqProfiles[index].decibels = settings.eqDecibels
        settings.save()
    }

    func renameActiveProfile(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = settings.eqProfiles.firstIndex(where: { $0.id == settings.activeEQProfile }) else { return }
        settings.eqProfiles[index].name = trimmed
        settings.save()
    }

    func deleteActiveProfile() {
        settings.eqProfiles.removeAll { $0.id == settings.activeEQProfile }
        settings.activeEQProfile = nil
        settings.save()
    }

    /// Custom bands only apply under the Custom preset, so switch to it first if needed.
    private func writeEQ() {
        settings.save()
        let previous = eqTask
        previous?.cancel()
        eqTask = Task { [weak self] in
            await previous?.value
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, let device else { return }
            if activePreset != .custom {
                try? await device.setEQPreset(.custom)
                activePreset = .custom
            }
            let raw = settings.eqDecibels.map(EQ.raw(fromDecibels:))
            try? await device.setEQBands(raw)
            bandsHoldMusicGenre = false
        }
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginProblem = nil
        } catch {
            loginProblem = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }

    func openLoginSettings() { LoginItem.openSystemSettings() }

    // MARK: - Spatial audio

    /// Starts or stops the spatial effect to match the saved setting.
    func applySpatial() {
        if settings.spatialEnabled, isConnected {
            do {
                try spatial.start(mode: settings.spatialMode, amount: Float(settings.spatialAmount))
                spatialProblem = nil
            } catch {
                spatial.stop()
                settings.spatialEnabled = false
                settings.save()
                spatialProblem = "Couldn't start: \(error). Allow System Audio Recording for Nommo in System Settings → Privacy & Security."
            }
        } else {
            spatial.stop()
            if !settings.spatialEnabled { spatialProblem = nil }
        }
    }

    func spatialParametersChanged() {
        settings.save()
        spatial.setParameters(mode: settings.spatialMode, amount: Float(settings.spatialAmount))
    }

    public func shutdown() {
        spatial.stop()
        levelMonitor.stop()
        movieTask?.cancel()
        let screen = screen
        Task { await screen.stop() }
        monitor?.cancel()
        let engine = engine
        Task { await engine?.stop() }
    }
}
