import Foundation

enum AppMetadata {
    static let projectName = "Pet in The System"
    static let shortName = "PTS"
    static let bundleIdentifier = "com.pts.app"

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var installedBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static var displayVersion: String {
        guard let build = installedBuild, build != installedVersion else {
            return installedVersion
        }
        return "\(installedVersion) (\(build))"
    }
}
