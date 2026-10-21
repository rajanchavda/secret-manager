import Foundation

/// The version `sec --version` reports.
public enum SecVersion {
    /// Latest released version. Used when the CLI runs outside the app bundle (e.g. `make install`),
    /// so bump it together with the release tag.
    public static let fallback = "1.1.0"

    /// The version stamped into Secret Manager.app's Info.plist by the release build when the CLI runs
    /// from inside the bundle (Homebrew links `sec` to `Contents/MacOS/sec`), otherwise `fallback`.
    public static var current: String {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return fallback }
        return bundleVersion(forExecutableAt: executable) ?? fallback
    }

    /// Reads `CFBundleShortVersionString` from `<App>.app/Contents/Info.plist` for an executable
    /// at `<App>.app/Contents/MacOS/<name>`. Returns nil for executables outside an app bundle.
    static func bundleVersion(forExecutableAt executable: URL) -> String? {
        let macOSDir = executable.deletingLastPathComponent()
        let contentsDir = macOSDir.deletingLastPathComponent()
        guard macOSDir.lastPathComponent == "MacOS", contentsDir.lastPathComponent == "Contents" else { return nil }
        let plistURL = contentsDir.appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: plistURL),
              let version = info["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return nil }
        return version
    }
}
