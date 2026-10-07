import Foundation

public final class EditorEngine {
    public static let shared = EditorEngine()
    
    private init() {}
    
    private var rescueDirectory: URL {
        return SecPaths.dataDirectory.appendingPathComponent("rescue", isDirectory: true)
    }
    
    /// Edits a vault's contents in a temporary buffer and re-encrypts on save.
    /// The buffer is plaintext on disk while the editor is open: it lives in an owner-only directory
    /// and is deleted afterwards, but anything running as the user (including the editor itself) can read it.
    public func edit(vaultURL: URL) async throws {
        // Read decrypted plaintext
        let plainData = try await VaultEngine.shared.readDecryptedData(
            vaultURL: vaultURL,
            promptReason: "sec requires Touch ID to decrypt '\(vaultURL.lastPathComponent)' for editing"
        )
        
        // Create the buffer inside a private (0700) directory so it is never reachable by other users,
        // named after the real file so editors pick the right syntax mode
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(".sec_edit_\(UUID().uuidString)", isDirectory: true)
        let tempFile = tempDir.appendingPathComponent(vaultURL.deletingPathExtension().lastPathComponent)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: tempFile.path, contents: plainData, attributes: [.posixPermissions: 0o600]) else {
                throw VaultError.writeFailed("could not write \(tempFile.lastPathComponent)")
            }
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw VaultError.writeFailed("Failed to create secure edit buffer: \(error.localizedDescription)")
        }
        
        warnAboutPlaintextRescueCopies()
        
        var updateSucceeded = false
        var lastEditedData: Data? = nil
        
        defer {
            if !updateSucceeded, let rescueData = lastEditedData, rescueData != plainData {
                saveEncryptedRescueCopy(of: rescueData, for: vaultURL)
            }
            // Overwriting in place is not reliable on APFS/SSD storage, so the buffer is simply deleted
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Resolve editor command
        let editor = resolveEditor()
        if Self.isAIEnabledEditor(editor) {
            fputs("⚠️  '\(editor)' is an AI-enabled editor. While the buffer is open, its indexer, AI features and\n", stderr)
            fputs("   local file history can read and keep your decrypted secrets.\n", stderr)
            fputs("   Set EDITOR=nano (or vim) to keep the plaintext inside your terminal.\n", stderr)
        }
        
        print("📝 Opening secrets in editor...")
        print("   (Save and close the editor when finished to automatically re-encrypt)")
        
        // The buffer path is passed as a positional argument, never spliced into the shell command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "\(editor) \"$1\"", "sec-edit", tempFile.path]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Error launching editor: \(error.localizedDescription)")
            return
        }
        
        // Read back edited contents
        guard let editedData = try? Data(contentsOf: tempFile) else {
            print("❌ Failed to read edited temporary buffer. Vault unchanged.")
            return
        }
        
        if editedData == plainData {
            print("ℹ️ No changes detected. Vault remained unchanged.")
            return
        }
        
        // Zero-Data-Loss Guard: Prevent accidental wipe if editor closed with empty or whitespace-only buffer
        let trimmedString = (String(data: editedData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedString.isEmpty && !plainData.isEmpty {
            print("⚠️  WARNING: The edited buffer is empty or contains only whitespace, but the original vault had secrets.")
            print("   Aborting update to prevent accidental data loss. Your vault was NOT modified.")
            print("   (To remove secrets intentionally, delete individual keys or write a comment).")
            return
        }
        
        lastEditedData = editedData
        
        // Re-encrypt to vault and refresh dummy .env
        try await VaultEngine.shared.updateVault(vaultURL: vaultURL, plaintextData: editedData)
        updateSucceeded = true
        print("🔒 Successfully re-encrypted '\(vaultURL.lastPathComponent)' and refreshed placeholder.")
    }
    
    /// Editors that ship AI assistants or cloud indexing and keep their own file history
    static func isAIEnabledEditor(_ editorCommand: String) -> Bool {
        let name = URL(fileURLWithPath: editorCommand.split(separator: " ").first.map(String.init) ?? "").lastPathComponent.lowercased()
        return ["code", "code-insiders", "cursor", "windsurf", "zed", "antigravity", "kiro", "trae"].contains(name)
    }
    
    /// GUI editors that return immediately unless told to wait for the window to close
    private static func needsWaitFlag(_ editorCommand: String) -> Bool {
        let lower = editorCommand.lowercased()
        let name = URL(fileURLWithPath: lower.split(separator: " ").first.map(String.init) ?? "").lastPathComponent
        let guiEditors = ["code", "code-insiders", "cursor", "windsurf", "zed", "antigravity", "kiro", "trae", "subl", "mate", "atom"]
        return guiEditors.contains(name) && !lower.contains("-w") && !lower.contains("--wait")
    }
    
    /// Resolves the editor command (with wait flags). `$EDITOR` / `$VISUAL` always win. Without them a
    /// terminal session gets a terminal editor, so the plaintext is not handed to an AI-enabled IDE by default.
    func resolveEditor(environment: [String: String] = ProcessInfo.processInfo.environment,
                       hasTerminal: Bool = isatty(STDIN_FILENO) != 0) -> String {
        if let editor = environment["EDITOR"] ?? environment["VISUAL"], !editor.isEmpty {
            return Self.needsWaitFlag(editor) ? "\(editor) --wait" : editor
        }
        
        let fileManager = FileManager.default
        if hasTerminal {
            return fileManager.fileExists(atPath: "/usr/bin/nano") ? "nano" : "vim"
        }
        
        // No terminal (launched from the app or a Finder action): a GUI editor is the only option
        if fileManager.fileExists(atPath: "/usr/local/bin/code") || fileManager.fileExists(atPath: "/opt/homebrew/bin/code") {
            return "code --wait"
        } else if fileManager.fileExists(atPath: "/usr/local/bin/cursor") || fileManager.fileExists(atPath: "/opt/homebrew/bin/cursor") {
            return "cursor --wait"
        }
        return "open -W -n -a TextEdit"
    }
    
    /// Keeps edits that could not be written back to the vault, encrypted with the vault key.
    /// The copy is an ordinary vault file, readable with `sec view <path>`.
    func saveEncryptedRescueCopy(of data: Data, for vaultURL: URL) {
        let fm = FileManager.default
        let name = "rescue_\(vaultURL.deletingPathExtension().lastPathComponent)_\(Int(Date().timeIntervalSince1970)).vault"
        let rescueFile = rescueDirectory.appendingPathComponent(name)
        do {
            try fm.createDirectory(at: rescueDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let masterKey = try KeychainManager.shared.getMasterKey()
            let encrypted = try CryptoEngine.shared.encrypt(plaintext: data, keyData: masterKey)
            guard fm.createFile(atPath: rescueFile.path, contents: encrypted, attributes: [.posixPermissions: 0o600]) else {
                throw VaultError.writeFailed(rescueFile.path)
            }
            print("💾 Saved an encrypted rescue copy of your edits to: \(rescueFile.path)")
            print("   Read it with: sec view \"\(rescueFile.path)\"")
        } catch {
            // Never fall back to a plaintext copy
            fputs("❌ Your edits could not be saved or kept as an encrypted rescue copy: \(error.localizedDescription)\n", stderr)
        }
    }
    
    /// Older versions left rescue copies as plaintext `.env` files; point them out so they get removed
    private func warnAboutPlaintextRescueCopies() {
        let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: rescueDirectory.path)) ?? []).filter { !$0.hasSuffix(".vault") && !$0.hasPrefix(".") }
        if !leftovers.isEmpty {
            fputs("⚠️  \(leftovers.count) plaintext rescue file\(leftovers.count == 1 ? "" : "s") from an older sec version in \(rescueDirectory.path)\n", stderr)
            fputs("   They contain unencrypted secrets. Recover what you need, then delete them.\n", stderr)
        }
    }
}
