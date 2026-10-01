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
}
