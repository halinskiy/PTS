import Cocoa

private let githubReleasesURL = "https://api.github.com/repos/halinskiy/PTS/releases/latest"

extension AppController {
    func setupAutomaticUpdateChecks() {
        // Silent background check on launch (no alert if up to date)
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.performUpdateCheck(silent: true)
        }
    }

    @objc func checkForUpdates() {
        checkForUpdatesMenuItem?.title = "Checking…"
        checkForUpdatesMenuItem?.isEnabled = false
        performUpdateCheck(silent: false)
    }

    private func performUpdateCheck(silent: Bool) {
        guard let url = URL(string: githubReleasesURL) else { return }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.checkForUpdatesMenuItem?.title = "Check for Updates…"
                self?.checkForUpdatesMenuItem?.isEnabled = true
            }

            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlUrl = json["html_url"] as? String
            else {
                if !silent {
                    DispatchQueue.main.async { [weak self] in
                        self?.presentErrorAlert(
                            title: "Update check failed",
                            message: "Couldn't reach GitHub. Check your internet connection and try again."
                        )
                    }
                }
                return
            }

            let latest = AppVersion(tagName)
            let current = AppVersion(AppMetadata.installedVersion)

            DispatchQueue.main.async { [weak self] in
                if latest > current {
                    self?.presentUpdateAvailableAlert(
                        latestVersion: latest.description,
                        currentVersion: current.description,
                        downloadURL: htmlUrl
                    )
                } else if !silent {
                    self?.presentInfoAlert(
                        title: "PTS is up to date",
                        message: "You're running version \(current.description) — the latest release."
                    )
                }
            }
        }.resume()
    }

    private func presentUpdateAvailableAlert(latestVersion: String, currentVersion: String, downloadURL: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "PTS \(latestVersion) is available"
        alert.informativeText = "You're running \(currentVersion). Would you like to download the latest version?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
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
