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

        guard let data = Self.runGit(["-C", directory.path, "log", "--all", "-1", "--format=%h", "--", fileURL.lastPathComponent]) else { return false }
        return !(String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Runs `/usr/bin/git` and returns its stdout, or nil when git cannot start, exits non-zero, or has not
    /// finished within `timeout` (it is then terminated). `sec lock` waits on this, so a git that stalls
    /// (a hook, a lock, the Xcode shim waiting on something) must not hang the command.
    /// Only for commands with short output: stdout is read after exit, so it has to fit in the pipe buffer.
    static func runGit(_ arguments: [String], timeout: TimeInterval = 10) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return nil }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}
