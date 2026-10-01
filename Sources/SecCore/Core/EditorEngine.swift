import Foundation

public final class EditorEngine {
    public static let shared = EditorEngine()
    
    private init() {}
    
    /// Securely edits a vault's contents in an ephemeral temporary buffer with automatic re-encryption and shredding
    public func edit(vaultURL: URL) async throws {
        // Read decrypted plaintext
        let plainData = try await VaultEngine.shared.readDecryptedData(
            vaultURL: vaultURL,
            promptReason: "sec requires Touch ID to decrypt '\(vaultURL.lastPathComponent)' for editing"
        )
        
        // Create secure temporary file
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempFile = tempDir.appendingPathComponent(".sec_edit_\(UUID().uuidString).env")
        
        do {
            try plainData.write(to: tempFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempFile.path)
        } catch {
            throw VaultError.writeFailed("Failed to create secure edit buffer: \(error.localizedDescription)")
        }
        
        var updateSucceeded = false
        var lastEditedData: Data? = nil
        
        defer {
            if !updateSucceeded, let rescueData = lastEditedData, rescueData != plainData {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let rescueDir = home.appendingPathComponent(".sec/rescue", isDirectory: true)
                try? FileManager.default.createDirectory(at: rescueDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let rescueFile = rescueDir.appendingPathComponent("rescue_\(vaultURL.deletingPathExtension().lastPathComponent)_\(Int(Date().timeIntervalSince1970)).env")
                if (try? rescueData.write(to: rescueFile, options: .atomic)) != nil {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rescueFile.path)
                    print("💾 Saved rescue copy of your edits to: \(rescueFile.path)")
                }
            }
            // Secure shredding on exit
            shredAndRemove(tempFile)
        }
        
        // Resolve editor command
        let editorCommand = resolveEditorCommand(for: tempFile.path)
        
        print("📝 Opening secrets in editor...")
        print("   (Save and close the editor when finished to automatically re-encrypt)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", editorCommand]
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
    
    /// Resolves preferred editor with wait flags
    private func resolveEditorCommand(for filePath: String) -> String {
        let envEditor = ProcessInfo.processInfo.environment["EDITOR"] ??
                        ProcessInfo.processInfo.environment["VISUAL"]
        
        if let editor = envEditor, !editor.isEmpty {
            let lower = editor.lowercased()
            if (lower.contains("code") || lower.contains("cursor") || lower.contains("subl") || lower.contains("mate") || lower.contains("atom") || lower.contains("zed"))
                && !lower.contains("-w") && !lower.contains("--wait") {
                return "\(editor) --wait \"\(filePath)\""
            }
            return "\(editor) \"\(filePath)\""
        }
        
        // Check for common installed editors
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: "/usr/local/bin/code") || fileManager.fileExists(atPath: "/opt/homebrew/bin/code") {
            return "code --wait \"\(filePath)\""
        } else if fileManager.fileExists(atPath: "/usr/local/bin/cursor") || fileManager.fileExists(atPath: "/opt/homebrew/bin/cursor") {
            return "cursor --wait \"\(filePath)\""
        } else if fileManager.fileExists(atPath: "/usr/bin/nano") {
            return "nano \"\(filePath)\""
        } else {
            return "vim \"\(filePath)\""
        }
    }
    
    /// Overwrites file with random bytes before unlinking to prevent data recovery
    private func shredAndRemove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, fileSize > 0 {
            var randomBytes = [UInt8](repeating: 0, count: fileSize)
            _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            let randomData = Data(randomBytes)
            try? randomData.write(to: url, options: .atomic)
        }
        
        try? FileManager.default.removeItem(at: url)
    }
}
