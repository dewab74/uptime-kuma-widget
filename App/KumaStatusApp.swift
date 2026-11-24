import AppKit
import KumaKit
import KumaUI
import SwiftUI

@main
struct KumaStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if model.configuration == nil {
            // First run: there is nothing to show until a page is chosen.
            SettingsOpener.open()
        }
    }

    /// `kumastatus://open` comes from a click on the widget: open the status
    /// page in the browser, or settings when none is set up yet.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "kumastatus" }) else { return }
        if model.configuration == nil {
            SettingsOpener.open()
        } else {
            model.openStatusPage()
        }
    }
}

/// Opens the Settings scene from places that have no SwiftUI environment.
/// A menu bar (LSUIElement) app also has to activate itself, or the window
/// opens behind the frontmost app.
@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let summary = model.state?.snapshot?.summary
        if model.configuration == nil {
            Image(systemName: "gauge.with.dots.needle.67percent")
        } else if model.isStale || summary == nil {
            Image(systemName: "wifi.slash")
        } else if let summary {
            HStack(spacing: 3) {
                Image(systemName: summary.overall.menuBarSymbol)
                if summary.problems > 0 {
                    Text("\(summary.problems)")
                }
            }
        }
    }
}
