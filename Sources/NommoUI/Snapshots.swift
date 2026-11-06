import AppKit
import NommoKit
import SwiftUI

/// Renders the popover in a handful of representative states. Used by the `NommoSnapshot` tool.
@MainActor
public enum SnapshotRenderer {
    /// Renders the 1024 px app icon master to `url`.
    public static func renderIcon(to url: URL) throws {
        let renderer = ImageRenderer(content: AppIconView().environment(\.isSnapshot, true))
        renderer.scale = 2
        renderer.isOpaque = false
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    public static func renderAll(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var solid = Settings()
        solid.kind = .solid
        solid.left = RGB(255, 66, 170)
        solid.right = RGB(10, 132, 255)
        solid.linkColors = false

        var spectrum = Settings()
        spectrum.kind = .spectrum
        spectrum.left = RGB(255, 159, 10)
        spectrum.right = RGB(64, 200, 255)

        var breathe = Settings()
        breathe.kind = .breathing
        breathe.breathFirst = RGB(255, 75, 185)
        breathe.breathSecond = RGB(60, 190, 255)

        var music = Settings()
        music.kind = .music
        music.left = RGB(0, 214, 170)
        music.right = RGB(0, 214, 170)

        var eq = Settings()
        eq.kind = .solid
        eq.left = RGB(64, 200, 255)
        eq.right = RGB(64, 200, 255)
        eq.eqDecibels = [5, 6, 4, 2, 0, -1, 1, 3, 4, 2]
        let profile = EQProfile(name: "Warm", decibels: eq.eqDecibels)
        eq.eqProfiles = [profile]
        eq.activeEQProfile = profile.id

        var space = Settings()
        space.kind = .solid
        space.left = RGB(150, 100, 255)
        space.right = RGB(150, 100, 255)
        space.spatialEnabled = true
        space.spatialMode = .immersive
        space.spatialAmount = 0.7

        let shots: [(String, AppStore, NommoPopover.Tab)] = [
            ("light-solid", AppStore(preview: solid), .light),
            ("light-spectrum", AppStore(preview: spectrum), .light),
            ("light-music", AppStore(preview: music), .light),
            ("light-breathe", AppStore(preview: breathe), .light),
            ("sound-custom", AppStore(preview: eq), .sound),
            ("sound-preset", AppStore(preview: eq, preset: .music), .sound),
            ("space", AppStore(preview: space), .space),
            ("offline", AppStore(preview: Settings(), status: .unavailable("Nommo V2 Pro not found")), .light),
        ]
        for (name, store, tab) in shots {
            let view = NommoPopover(store: store, tab: tab).environment(\.isSnapshot, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
            else { continue }
            try png.write(to: directory.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }
    }
}
