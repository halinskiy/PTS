import Cocoa
import Sparkle

// MARK: - Sparkle Auto-Update Integration

private var sparkleController: SPUStandardUpdaterController?

extension AppController {
    func setupAutomaticUpdateChecks() {
        sparkleController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    @objc func checkForUpdates() {
        sparkleController?.checkForUpdates(nil)
    }

    @objc func showAboutWindow() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func presentInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
