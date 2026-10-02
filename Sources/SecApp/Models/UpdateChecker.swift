import Foundation
import AppKit
import Combine

/// GitHub Release metadata representation
public struct GitHubRelease: Codable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct GitHubAsset: Codable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

/// Zero-dependency Update Checker using standard URLSession
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()
    
    public let repoOwner = "rajanchavda"
    public let repoName = "file-sec"
    
    @Published public var isChecking: Bool = false
    @Published public var latestRelease: GitHubRelease?
    @Published public var isUpdateAvailable: Bool = false
    @Published public var lastCheckDate: Date?
    @Published public var errorMessage: String?
    @Published public var showUpdateSheet: Bool = false
    
    private let lastCheckKey = "sec_last_update_check_timestamp"
    
    public var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    public var isInstalledViaHomebrew: Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.contains("/Cellar/") ||
               bundlePath.contains("/Caskroom/") ||
               FileManager.default.fileExists(atPath: "/opt/homebrew/bin/sec") ||
               FileManager.default.fileExists(atPath: "/usr/local/bin/sec")
    }
    
    public var dmgDownloadURL: URL? {
        guard let release = latestRelease else { return nil }
        if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
            return URL(string: dmgAsset.browserDownloadUrl)
        }
        return URL(string: release.htmlUrl)
    }
    
    private init() {
        if let storedDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            self.lastCheckDate = storedDate
        }
    }
    
    /// Checks for updates.
    /// - Parameter userInitiated: If true, will present feedback even if no update is found.
    public func checkForUpdates(userInitiated: Bool = false) async {
        guard !isChecking else { return }
        
        isChecking = true
        errorMessage = nil
        
        let apiURLString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: apiURLString) else {
            isChecking = false
            errorMessage = "Invalid update URL."
            return
        }
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SecretManager-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 404 {
                // No releases published yet on GitHub
                isUpdateAvailable = false
                isChecking = false
                if userInitiated {
                    presentUpToDateAlert()
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)
            
            self.latestRelease = release
            self.lastCheckDate = Date()
            UserDefaults.standard.set(self.lastCheckDate, forKey: lastCheckKey)
            
            let remoteCleanVersion = cleanVersion(release.tagName)
            let localCleanVersion = cleanVersion(currentVersion)
            
            if isVersion(remoteCleanVersion, greaterThan: localCleanVersion) {
                self.isUpdateAvailable = true
                self.showUpdateSheet = true
            } else {
                self.isUpdateAvailable = false
                if userInitiated {
                    presentUpToDateAlert()
                }
            }
        } catch {
            self.errorMessage = error.localizedDescription
            if userInitiated {
                presentErrorAlert(message: error.localizedDescription)
            }
        }
        
        isChecking = false
    }
    
    /// Throttled background check on app launch (once every 24 hours)
    public func performBackgroundCheckIfStale() {
        if let lastCheck = lastCheckDate, Date().timeIntervalSince(lastCheck) < 86400 {
            return
        }
        
        Task {
            await checkForUpdates(userInitiated: false)
        }
    }
    
    // MARK: - Version Comparison Helpers
    
    private func cleanVersion(_ versionString: String) -> String {
        var v = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased().hasPrefix("v") {
            v.removeFirst()
        }
        return v
    }
    
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
    
    // MARK: - UI Alerts
    
    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date!"
        alert.informativeText = "Secret Manager \(currentVersion) is currently the newest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not check for updates: \(message)\n\nPlease check your internet connection or visit the GitHub releases page."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub Releases")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let releasesURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases") {
                NSWorkspace.shared.open(releasesURL)
            }
        }
    }
}
