import Foundation

public final class GitIgnoreManager {
    public static let shared = GitIgnoreManager()
    
    private init() {}
    
    /// Ensures sensitive sec files and vaults are included in the nearest .gitignore
    public func ensureIgnored(in directory: URL, vaultFileName: String) {
        let gitDir = directory.appendingPathComponent(".git")
        let gitIgnoreFile = directory.appendingPathComponent(".gitignore")
        
        // Only modify if this is a git repository or already has a .gitignore
        let isGitRepo = FileManager.default.fileExists(atPath: gitDir.path)
        let hasGitIgnore = FileManager.default.fileExists(atPath: gitIgnoreFile.path)
        
        guard isGitRepo || hasGitIgnore else { return }
        
        var existingContent = ""
        if hasGitIgnore, let content = try? String(contentsOf: gitIgnoreFile, encoding: .utf8) {
            existingContent = content
        }
        
        let entriesToEnsure = [
            vaultFileName,
            "*.vault.bak",
            ".sec*",
            "*.sec_tmp"
        ]
        
        var entriesToAdd: [String] = []
        let existingLines = Set(existingContent.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) })
        
        for entry in entriesToEnsure {
            if !existingLines.contains(entry) {
                entriesToAdd.append(entry)
            }
        }
        
        guard !entriesToAdd.isEmpty else { return }
        
        var newContent = existingContent
        if !newContent.isEmpty && !newContent.hasSuffix("\n") {
            newContent += "\n"
        }
        
        newContent += "\n# sec vault & temporary buffers\n"
        for entry in entriesToAdd {
            newContent += "\(entry)\n"
        }
        
        try? newContent.write(to: gitIgnoreFile, atomically: true, encoding: .utf8)
    }
    
    /// True when the file has ever been committed in the git repository that contains it.
    /// Locking cannot take a secret back out of history, so the caller should advise rotation.
    public func wasEverCommitted(_ fileURL: URL) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        
        // Only ask git when the file is inside a repository. This also avoids triggering the
        // "install command line developer tools" dialog on Macs without git.
        var probe = directory.standardizedFileURL
        var insideRepo = false
        while true {
            if FileManager.default.fileExists(atPath: probe.appendingPathComponent(".git").path) {
                insideRepo = true
                break
            }
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path { break }
            probe = parent
        }
        guard insideRepo else { return false }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "log", "--all", "-1", "--format=%h", "--", fileURL.lastPathComponent]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        return !(String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
