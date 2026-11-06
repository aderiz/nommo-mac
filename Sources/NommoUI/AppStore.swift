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
    /// Set when spatial audio could not start (permission denied, speaker output missing, …).
    private(set) var spatialProblem: String?
    /// Set when music-reactive lighting could not listen to system audio.
    private(set) var musicProblem: String?
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

    public init() {
        isPreview = false
        settings = Settings.load()
        monitor = Task { [weak self] in await self?.monitorConnection() }
    }

    /// A store with fixed state and no hardware, for snapshots and previews.
    init(preview settings: Settings, status: Status = .connected(serial: "000000000000000"), preset: EQPreset? = .custom) {
        self.settings = settings
        self.status = status
        self.activePreset = preset
        self.isPreview = true
        launchAtLogin = false
        loginNeedsApproval = false
    }

    @ObservationIgnored let isPreview: Bool

    /// Colours to show on the stage, or nil when the speakers run their own cycle and we can't know them.
    var stageColors: (left: RGB, right: RGB)? {
        switch settings.kind {
        case .builtIn: nil
        case .off: (.black, .black)
        case .solid: (settings.left, settings.right)
        case .breathing: isPreview ? (settings.breathFirst, settings.breathFirst) : (observedLeft, observedRight)
        case .spectrum, .music: isPreview ? (settings.left, settings.right) : (observedLeft, observedRight)
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
            let engine = LightingEngine(
                device: device,
                levels: { monitor.levels },
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
            settings.eqDecibels = bands.map(EQ.decibels(fromRaw:))
            activePreset = try? await device.eqPreset()
            status = .connected(serial: serial)
            try await device.setBrightness(brightnessByte)
            await engine.apply(settings.effect)
            updateLevelMonitor()
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
        guard let engine else { return }
        let effect = settings.effect
        Task { await engine.apply(effect) }
    }

    /// Listens to system audio only while the Music effect is selected.
    private func updateLevelMonitor() {
        guard isConnected, settings.kind == .music else {
            levelMonitor.stop()
            musicProblem = nil
            return
        }
        do {
            try levelMonitor.start()
            musicProblem = nil
        } catch {
            levelMonitor.stop()
            musicProblem = "Couldn't listen to system audio: \(error). Allow System Audio Recording for Nommo in System Settings → Privacy & Security."
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

    func selectPreset(_ preset: EQPreset) {
        guard let device else { return }
        Task {
            try? await device.setEQPreset(preset)
            activePreset = (try? await device.eqPreset()) ?? preset
            // Built-in presets don't change the band registers, but Custom may reset them: show what the speaker has.
            if activePreset == .custom, let bands = try? await device.eqBands() {
                settings.eqDecibels = bands.map(EQ.decibels(fromRaw:))
                settings.save()
            }
        }
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
        eqTask?.cancel()
        eqTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, let device else { return }
            if activePreset != .custom {
                try? await device.setEQPreset(.custom)
                activePreset = .custom
            }
            let raw = settings.eqDecibels.map(EQ.raw(fromDecibels:))
            try? await device.setEQBands(raw)
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
        monitor?.cancel()
        let engine = engine
        Task { await engine?.stop() }
    }
}
