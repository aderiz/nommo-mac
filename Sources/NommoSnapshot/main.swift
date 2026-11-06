import AppKit
import NommoUI
import SwiftUI

// Renders each panel of the popover to a PNG so the design can be reviewed without clicking through it.
//   swift run NommoSnapshot <output-directory>
//   swift run NommoSnapshot --icon <output.png>      (the 1024 px app icon master)
let arguments = Array(CommandLine.arguments.dropFirst())
MainActor.assumeIsolated {
    do {
        if arguments.first == "--icon" {
            try SnapshotRenderer.renderIcon(to: URL(fileURLWithPath: arguments.dropFirst().first ?? "AppIcon-1024.png"))
        } else {
            try SnapshotRenderer.renderAll(to: URL(fileURLWithPath: arguments.first ?? "snapshots", isDirectory: true))
        }
    } catch {
        FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
        exit(1)
    }
}
