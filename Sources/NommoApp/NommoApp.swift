import Foundation
import NommoUI
import SwiftUI

@main
struct NommoMenuBarApp: App {
    @State private var store = AppStore()

    init() {
        // Scripting hooks, handled before any UI appears:
        //   Nommo --login-status        print whether the app opens at login
        //   Nommo --set-login on|off    turn opening at login on or off
        //   Nommo --diagnose            print a health check (speaker, audio permission) for bug reports
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnose") {
            print(Diagnostics.report())
            exit(0)
        }
        if arguments.contains("--login-status") {
            print("login item: \(LoginItem.statusDescription)")
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--set-login"), arguments.indices.contains(index + 1) {
            do {
                try LoginItem.set(arguments[index + 1] == "on")
                print("login item: \(LoginItem.statusDescription)")
                exit(0)
            } catch {
                print("failed: \(error.localizedDescription)")
                exit(1)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Nommo", systemImage: "hifispeaker.2.fill") {
            NommoPopover(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
