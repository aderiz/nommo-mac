import AppKit
import NommoKit
import SwiftUI

// MARK: - Popover

public struct NommoPopover: View {
    @Bindable var store: AppStore
    @State private var tab: Tab
    @Namespace private var tabHighlight

    enum Tab: String, CaseIterable, Identifiable {
        case light, sound, space
        var id: String { rawValue }
        var title: String {
            switch self {
            case .light: "Light"
            case .sound: "Sound"
            case .space: "Space"
            }
        }
        var symbol: String {
            switch self {
            case .light: "sun.max.fill"
            case .sound: "slider.vertical.3"
            case .space: "dot.radiowaves.left.and.right"
            }
        }
    }

    public init(store: AppStore) {
        self.store = store
        _tab = State(initialValue: .light)
    }

    init(store: AppStore, tab: Tab) {
        self.store = store
        _tab = State(initialValue: tab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            StageView(
                left: store.stageColors?.left,
                right: store.stageColors?.right,
                brightness: store.settings.brightness,
                connected: store.isConnected,
                status: statusText
            )

            if store.isConnected {
                tabBar
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .light: LightPanel(store: store)
                    case .sound: SoundPanel(store: store)
                    case .space: SpacePanel(store: store)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, minHeight: 292, maxHeight: 292, alignment: .topLeading)
            } else {
                Unavailable(store: store)
            }

            footer
        }
        .frame(width: 380)
        .background {
            ZStack {
                AuroraBackground(left: leftGlow, right: rightGlow, level: store.isConnected ? store.settings.brightness : 0)
                Grain()
            }
        }
        .environment(\.accent, store.accent)
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }

    private var leftGlow: Color? { store.auroraColors.map { Color(rgb: $0.left) } }
    private var rightGlow: Color? { store.auroraColors.map { Color(rgb: $0.right) } }

    private var statusText: String {
        switch store.status {
        case .searching: "Searching"
        case .connected: "USB"
        case let .unavailable(reason): reason
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                let selected = item == tab
                Button {
                    withAnimation(.snappy(duration: 0.24)) { tab = item }
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                            Text(item.title).font(Theme.label)
                        }
                        .foregroundStyle(selected ? Theme.text : Theme.faint)
                        .padding(.top, 8)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if selected {
                                Capsule().fill(store.accent.color).frame(height: 2)
                                    .matchedGeometryEffect(id: "tab", in: tabHighlight)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Quit Nommo") {
                store.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(Theme.caption)
            .foregroundStyle(Theme.dim)
            .keyboardShortcut("q")
            Spacer()
            if let problem = store.loginProblem {
                Text(problem).font(.system(size: 10)).foregroundStyle(Color(hex: 0xFF8A7A)).lineLimit(1)
            } else if store.loginNeedsApproval {
                Button("Approve in Login Items") { store.openLoginSettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(store.accent.color)
            }
            Text("Open at login").font(Theme.caption).foregroundStyle(Theme.dim)
            SwitchToggle(
                isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }),
                label: "Open at login"
            )
            .scaleEffect(0.72)
            .frame(width: 34, height: 22)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct Unavailable: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 12) {
            Text("Can't reach the speakers").font(Theme.number(15)).foregroundStyle(Theme.text)
            Text("Plug in the Nommo V2 Pro over USB, and close Synapse or any virtual machine that's using it.")
                .font(Theme.caption).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Try again", systemImage: "arrow.clockwise") { store.reconnect() }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Light

private struct LightPanel: View {
    @Bindable var store: AppStore
    @Environment(\.accent) private var accent

    /// Seven effects in two rows: four, then three wider tiles.
    private var tileRows: [[Settings.Kind]] {
        let all = Settings.Kind.allCases
        return [Array(all.prefix(4)), Array(all.dropFirst(4))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                ForEach(tileRows.indices, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(tileRows[row]) { kind in
                            EffectTile(kind: kind, selected: kind == store.settings.kind) {
                                withAnimation(.snappy(duration: 0.2)) { store.settings.kind = kind }
                                store.lightingChanged()
                            }
                        }
                    }
                }
            }

            Group {
                switch store.settings.kind {
                case .builtIn:
                    note("The speakers run their own colour cycle. Pick an effect to take over.")
                case .off:
                    note("Lights are off.")
                case .solid:
                    colors
                case .breathing:
                    breathColors
                    InlineSlider(title: "Speed", value: speedBinding, range: 2 ... 12)
                case .spectrum:
                    InlineSlider(title: "Speed", value: speedBinding, range: 2 ... 12)
                    HStack {
                        Text("Same colour on both speakers").font(Theme.body).foregroundStyle(Theme.text)
                        Spacer()
                        SwitchToggle(isOn: mirror, label: "Same colour on both speakers")
                    }
                case .music:
                    PillPicker(options: MusicStyle.allCases, title: \.title, selection: musicStyle)
                    if store.settings.musicStyle == .pulse { colors }
                    InlineSlider(
                        title: "Sensitivity", valueText: String(format: "%.1f×", store.settings.musicSensitivity),
                        value: sensitivity, range: 0.5 ... 2.5
                    )
                    if let problem = store.audioProblem { warning(problem) }
                case .movie:
                    if store.movieNeedsPermission, let problem = store.movieProblem {
                        // Nothing to tune until the screen can be read, so the fix gets the whole panel.
                        warning(problem, lines: 2)
                        QuietButton(title: "Open Privacy Settings", systemImage: "lock.shield") {
                            store.openScreenRecordingSettings()
                        }
                    } else {
                        movieStatus
                        InlineSlider(
                            title: "Intensity", valueText: "\(Int((store.settings.movieIntensity * 100).rounded()))%",
                            value: movieIntensity
                        )
                        InlineSlider(
                            title: "Smoothness", valueText: "\(Int((store.settings.movieSmoothness * 100).rounded()))%",
                            value: movieSmoothness
                        )
                        if let problem = store.movieProblem ?? store.audioProblem { warning(problem, lines: 1) }
                    }
                }
            }

            Spacer(minLength: 0)

            InlineSlider(title: "Brightness", valueText: "\(Int((store.settings.brightness * 100).rounded()))%", value: brightness)
        }
    }

    // MARK: Bindings

    private var brightness: Binding<Double> {
        Binding(get: { store.settings.brightness }, set: { store.settings.brightness = $0; store.brightnessChanged() })
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { 14 - store.settings.period }, set: { store.settings.period = 14 - $0; store.lightingChanged() })
    }

    private var mirror: Binding<Bool> {
        Binding(get: { store.settings.mirrorSpectrum }, set: { store.settings.mirrorSpectrum = $0; store.lightingChanged() })
    }

    private var musicStyle: Binding<MusicStyle?> {
        Binding(get: { store.settings.musicStyle }, set: { if let s = $0 { store.settings.musicStyle = s; store.lightingChanged() } })
    }

    private var sensitivity: Binding<Double> {
        Binding(get: { store.settings.musicSensitivity }, set: { store.settings.musicSensitivity = $0; store.lightingChanged() })
    }

    private var movieIntensity: Binding<Double> {
        Binding(get: { store.settings.movieIntensity }, set: { store.settings.movieIntensity = $0; store.lightingChanged() })
    }

    private var movieSmoothness: Binding<Double> {
        Binding(get: { store.settings.movieSmoothness }, set: { store.settings.movieSmoothness = $0; store.lightingChanged() })
    }

    /// What the lights are following right now.
    private var movieStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(store.movieSource == .soundtrack ? Theme.faint : accent.color)
                .frame(width: 7, height: 7)
                .offset(y: -1)
            Text(movieStatusText).font(Theme.caption).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var movieStatusText: String {
        switch store.movieSource {
        case .picture: "Following the picture, left and right"
        case .soundtrack: "Can't read this video, following the sound"
        case nil: store.movieProblem == nil ? "Looking at the screen…" : "Following the sound for now"
        }
    }

    // MARK: Colour pickers

    private var colors: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !store.settings.linkColors { side("L") }
                SwatchRow(selection: Binding(
                    get: { store.settings.left },
                    set: {
                        store.settings.left = $0
                        if store.settings.linkColors { store.settings.right = $0 }
                        store.lightingChanged()
                    }
                ))
                linkButton
            }
            if !store.settings.linkColors {
                HStack(spacing: 8) {
                    side("R")
                    SwatchRow(selection: Binding(get: { store.settings.right }, set: { store.settings.right = $0; store.lightingChanged() }))
                }
            }
        }
    }

    /// Breathe alternates between two colours, so it asks for both.
    private var breathColors: some View {
        VStack(alignment: .leading, spacing: 8) {
            colourRow("First", selection: Binding(get: { store.settings.breathFirst }, set: { store.settings.breathFirst = $0; store.lightingChanged() }))
            colourRow("Second", selection: Binding(get: { store.settings.breathSecond }, set: { store.settings.breathSecond = $0; store.lightingChanged() }))
        }
    }

    private func colourRow(_ title: String, selection: Binding<RGB>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.label).foregroundStyle(Theme.dim).frame(width: 48, alignment: .leading)
            SwatchRow(selection: selection)
        }
    }

    private func side(_ text: String) -> some View {
        Text(text).font(Theme.label).foregroundStyle(Theme.dim).frame(width: 12)
    }

    /// Switches between one colour for both speakers and a colour for each.
    private var linkButton: some View {
        Button {
            store.settings.linkColors.toggle()
            if store.settings.linkColors { store.settings.right = store.settings.left }
            store.lightingChanged()
        } label: {
            Image(systemName: store.settings.linkColors ? "link" : "link.badge.plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 28)
                .surface(radius: 14, strong: true)
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(store.settings.linkColors ? "Colours linked" : "Colours separate")
        .help(store.settings.linkColors ? "Same colour on both speakers" : "Different colour on each speaker")
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ text: String, lines: Int? = nil) -> some View {
        Text(text).font(Theme.caption).foregroundStyle(Color(hex: 0xFF8A7A))
            .lineLimit(lines).fixedSize(horizontal: false, vertical: true)
    }
}

/// An effect: an icon and a name. The selected one is outlined in the accent.
private struct EffectTile: View {
    let kind: Settings.Kind
    let selected: Bool
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? accent.color : Theme.dim)
                Text(kind.title)
                    .font(Theme.label)
                    .foregroundStyle(selected ? Theme.text : Theme.dim)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? accent.tint : Theme.glass)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? accent.color : Theme.hairline, lineWidth: selected ? 1.5 : 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Sound

private struct SoundPanel: View {
    @Bindable var store: AppStore
    @State private var activeBand: Int?
    @Environment(\.accent) private var accent

    private var isCustom: Bool { store.shownPreset == .custom }
    private var isMusic: Bool { store.shownPreset == .music }

    private var preset: Binding<EQPreset?> {
        Binding(get: { store.shownPreset }, set: { if let p = $0 { store.selectPreset(p) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PillPicker(options: EQPreset.allCases, title: \.title, selection: preset)

            if isCustom {
                HStack {
                    ProfileChip(store: store)
                    Spacer()
                    if let band = activeBand {
                        Text(readout(band)).font(Theme.number(13)).foregroundStyle(Theme.text)
                    } else {
                        QuietButton(title: "Flat", systemImage: "equal") { store.resetEQ() }
                    }
                }
                EQCurve(values: store.settings.eqDecibels, activeBand: $activeBand, onChange: { store.setBand($0, to: $1) })
                    .frame(height: 168)
            } else if isMusic {
                HStack {
                    GenreChip(store: store)
                    Spacer()
                    QuietButton(title: "Edit as Custom", systemImage: "slider.vertical.3") { store.editGenreAsCustom() }
                }
                if store.musicGenreLive, let curve = store.settings.musicGenre.decibels {
                    // A style's curve is ours, so it can be drawn; it just isn't editable until it becomes Custom.
                    EQCurve(values: curve, editable: false, activeBand: .constant(nil), onChange: { _, _ in })
                        .frame(height: 168)
                } else {
                    Spacer(minLength: 0)
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(accent.color)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(accent.tint).overlay(Circle().strokeBorder(accent.color.opacity(0.6), lineWidth: 1.2)))
                        Text("Music is tuned inside the speaker")
                            .font(Theme.display(14)).foregroundStyle(Theme.text)
                        Text("This is the speaker's own Music sound. Pick a style to change it.")
                            .font(Theme.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accent.color)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(accent.tint).overlay(Circle().strokeBorder(accent.color.opacity(0.6), lineWidth: 1.2)))
                    Text(store.activePreset.map { "\($0.title) is tuned inside the speaker" } ?? "Reading the speaker")
                        .font(Theme.display(14)).foregroundStyle(Theme.text)
                    Text("Its curve isn't something the speaker shares. Switch to Custom to shape your own.")
                        .font(Theme.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    QuietButton(title: "Edit as Custom", systemImage: "slider.vertical.3") { store.selectPreset(.custom) }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }

    private func readout(_ band: Int) -> String {
        let db = Int(store.settings.eqDecibels[band])
        let sign = db > 0 ? "+" : (db < 0 ? "−" : "")
        return "\(sign)\(abs(db)) dB · \(EQ.label(for: EQ.frequencies[band])) Hz"
    }
}

/// A menu button's face: a symbol, a name and a chevron.
private struct ChipLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(title).font(Theme.label)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.dim)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .surface(radius: 20, strong: true)
    }
}

/// The style of music played under the Music preset. Default is the speaker's own Music tuning.
private struct GenreChip: View {
    @Bindable var store: AppStore
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            label
        } else {
            Menu {
                ForEach(MusicGenre.allCases) { genre in
                    Button {
                        store.selectGenre(genre)
                    } label: {
                        if genre == store.shownGenre { Label(genre.title, systemImage: "checkmark") } else { Text(genre.title) }
                    }
                    if genre == .standard { Divider() }
                }
            } label: { label }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
        }
    }

    private var label: some View {
        ChipLabel(symbol: "music.note", title: store.shownGenre.title)
            .accessibilityLabel("Music style, \(store.shownGenre.title)")
    }
}

/// Saved curves: choose, save, update, rename and delete.
private struct ProfileChip: View {
    @Bindable var store: AppStore
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var isNaming = false
    @State private var draft = ""
    @State private var renaming = false

    var body: some View {
        HStack(spacing: 8) {
            if isNaming {
                TextField("Name this curve", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.label)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .surface(radius: 20)
                    .frame(width: 150)
                    .onSubmit(commit)
                QuietButton(title: "Save", action: commit).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { isNaming = false }.buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.dim)
            } else if isSnapshot {
                label
            } else {
                Menu { menuItems } label: { label }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
            }
        }
    }

    private var label: some View {
        ChipLabel(symbol: "bookmark.fill", title: title)
    }

    private var title: String {
        if let active = store.activeProfile { return store.profileIsModified ? "\(active.name) (edited)" : active.name }
        return store.settings.eqProfiles.isEmpty ? "Save a curve" : "Unsaved curve"
    }

    @ViewBuilder private var menuItems: some View {
        ForEach(store.settings.eqProfiles) { profile in
            Button {
                store.applyProfile(profile.id)
            } label: {
                if profile.id == store.settings.activeEQProfile { Label(profile.name, systemImage: "checkmark") } else { Text(profile.name) }
            }
        }
        if !store.settings.eqProfiles.isEmpty { Divider() }
        Button("Save current curve as new…") { draft = ""; renaming = false; isNaming = true }
        if let active = store.activeProfile {
            if store.profileIsModified { Button("Update “\(active.name)”") { store.updateActiveProfile() } }
            Button("Rename “\(active.name)”…") { draft = active.name; renaming = true; isNaming = true }
            Button("Delete “\(active.name)”", role: .destructive) { store.deleteActiveProfile() }
        }
    }

    private func commit() {
        if renaming { store.renameActiveProfile(to: draft) } else { store.saveCurrentAsProfile(named: draft) }
        isNaming = false
    }
}

// MARK: - Space

private struct SpacePanel: View {
    @Bindable var store: AppStore

    private var enabled: Binding<Bool> {
        Binding(get: { store.settings.spatialEnabled }, set: { store.settings.spatialEnabled = $0; store.settings.save(); store.applySpatial() })
    }

    private var mode: Binding<SpatialMode?> {
        Binding(get: { store.settings.spatialMode }, set: { if let m = $0 { store.settings.spatialMode = m; store.spatialParametersChanged() } })
    }

    private var amount: Binding<Double> {
        Binding(get: { store.settings.spatialAmount }, set: { store.settings.spatialAmount = $0; store.spatialParametersChanged() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spatial audio").font(Theme.display(16)).foregroundStyle(Theme.text)
                    Text(store.settings.spatialEnabled ? "Sound is routed through Nommo" : "Off")
                        .font(Theme.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                SwitchToggle(isOn: enabled, label: "Spatial audio")
            }

            SpaceDiagram(enabled: store.settings.spatialEnabled, mode: store.settings.spatialMode, amount: store.settings.spatialAmount)

            Group {
                PillPicker(options: SpatialMode.allCases, title: \.title, selection: mode)
                InlineSlider(title: "Amount", valueText: "\(Int((store.settings.spatialAmount * 100).rounded()))%", value: amount)
            }
            .opacity(store.settings.spatialEnabled ? 1 : 0.4)
            .disabled(!store.settings.spatialEnabled)

            if let problem = store.spatialProblem {
                Text(problem).font(Theme.caption).foregroundStyle(Color(hex: 0xFF8A7A)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.settings.spatialMode == .immersive
                     ? "Cancels crosstalk so sound reaches past the speakers. Sit centred for the best effect."
                     : "Widens the upper stereo image. Subtle, and fine from any seat.")
                    .font(Theme.caption).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
