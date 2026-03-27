import Foundation

enum AppResources {
    // SPM names the resource bundle "TargetName_TargetName.bundle"
    private static let bundleName = "PTS_PTS.bundle"

    static let bundle: Bundle = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName),
            URL(fileURLWithPath: CommandLine.arguments[0])
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName)
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            guard let bundle = Bundle(url: candidate) else { continue }
            return bundle
        }

        Swift.fatalError("could not locate resource bundle \(bundleName)")
    }()
}
