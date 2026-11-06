import AppKit
import Foundation
import NommoKit

/// A plain-text health check, for bug reports: `Nommo.app/Contents/MacOS/Nommo --diagnose`.
/// It prints nothing that identifies the user or the speaker (no serial number).
public enum Diagnostics {
    public static func report() -> String {
        let info = Bundle.main.infoDictionary
        var lines = [
            "Nommo \(info?["CFBundleShortVersionString"] as? String ?? "?")",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "login item: \(LoginItem.statusDescription)",
        ]

        // The speaker over USB HID. Two programs talking to it at once would read each other's replies, so if the
        // Nommo app is already running, don't query it; the running app having the speaker means it is reachable.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: info?["CFBundleIdentifier"] as? String ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            lines.append("speaker: skipped, the Nommo app is running and has it (quit the app to test the speaker from here)")
        } else if !IOKitHIDTransport.isDevicePresent() {
            lines.append("speaker: not found (is it plugged in over USB?)")
        } else {
            do {
                let device = NommoDevice(transport: try IOKitHIDTransport.open())
                let semaphore = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var result = "speaker: connected, but did not answer"
                Task {
                    if let brightness = try? await device.brightness(), let bands = try? await device.eqBands() {
                        result = "speaker: connected, brightness \(brightness)/255, EQ \(bands)"
                    }
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 5)
                lines.append(result)
            } catch {
                lines.append("speaker: found but could not be opened (\(error)). Another app may be using it.")
            }
        }

        // System audio capture, which Spatial audio and the Music lighting effect need.
        let monitor = AudioLevelMonitor()
        do {
            try monitor.start()
            Thread.sleep(forTimeInterval: 1)
            lines.append("system audio tap: ok")
            monitor.stop()
        } catch {
            lines.append("system audio tap: failed (\(error)). Check System Settings, Privacy & Security, System Audio Recording.")
        }
        return lines.joined(separator: "\n")
    }
}
