import SwiftUI
import AppKit

public struct SecretTableView: View {
    let vault: VaultItem
    @ObservedObject var store: SecAppStore
    
    @State private var filterQuery: String = ""
    @State private var isAddingSecret: Bool = false
    @State private var newKeyName: String = ""
    @State private var newKeyValue: String = ""
    @State private var copiedKeyId: UUID? = nil
    
    public init(vault: VaultItem, store: SecAppStore) {
        self.vault = vault
        self.store = store
    }
    
    public var filteredSecrets: [SecretEntry] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return store.currentSecrets
        }
        return store.currentSecrets.filter {
            $0.key.localizedCaseInsensitiveContains(q) ||
            $0.value.localizedCaseInsensitiveContains(q)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !store.isVaultUnlockedInUI {
                // Locked State - Biometric Tap Request
                VStack(spacing: 18) {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 90, height: 90)
                        
                        Image(systemName: "touchid")
                            .font(.scaled(size: 46, weight: .light))
                            .foregroundColor(.blue)
                    }
                    .accessibilityHidden(true)
                    
                    VStack(spacing: 6) {
                        Text("Secrets Encrypted with Touch ID")
                            .font(.scaled(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Authenticate once to unlock all vaults for \(store.selectedGraceOption.rawValue). Plaintext is never stored on disk.")
                            .font(.scaled(size: 13.5))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    
                    Button(action: {
                        Task {
                            await store.unlockVaultSecrets(for: vault)
                        }
                    }) {
                        HStack(spacing: 8) {
                            if store.isAuthenticating {
                                ProgressView()
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: "lock.open.fill")
                                    .font(.scaled(size: 14))
                            }
                            Text(store.isAuthenticating ? "Authenticating..." : "Unlock with Touch ID")
                                .font(.scaled(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(minHeight: 38)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.blue.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Unlock secrets using Apple Touch ID or system password")
                    .disabled(store.isAuthenticating)
                    .accessibilityLabel("Unlock vault secrets with Touch ID")
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            } else {
                // Unlocked State - Full Key-Value Table
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                    // Actions Toolbar
                    HStack(spacing: 10) {
                        // Search in keys
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.scaled(size: 12))
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                            
                            TextField("Filter variables...", text: $filterQuery)
                                .textFieldStyle(.plain)
                                .font(.scaled(size: 12.5))
                                .accessibilityLabel("Filter secret variables")
                            
                            if !filterQuery.isEmpty {
                                Button(action: { filterQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.scaled(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Clear filter query")
                                .accessibilityLabel("Clear filter query")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 240, minHeight: 30)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        Spacer()
                        
                        // Toggle Reveal All
                        Button(action: {
                            store.toggleAllSecretsVisibility()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: store.isAllSecretsRevealed ? "eye.slash" : "eye")
                                    .font(.scaled(size: 12))
                                Text(store.isAllSecretsRevealed ? "Mask All" : "Reveal All")
                                    .font(.scaled(size: 12.5, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minHeight: 30)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(store.isAllSecretsRevealed ? "Mask all secret values" : "Reveal all secret values")
                        .accessibilityLabel(store.isAllSecretsRevealed ? "Mask all secret values" : "Reveal all secret values")
                        
                        // Add Variable Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isAddingSecret.toggle()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.scaled(size: 11, weight: .bold))
                                Text("Add Variable")
                                    .font(.scaled(size: 12.5, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minHeight: 30)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Add a new secret variable")
                        .accessibilityLabel("Add new secret variable")
                        
                        // Save Changes Button
                        Button(action: {
                            Task {
                                await store.saveSecretsToVault(for: vault)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.scaled(size: 12))
                                Text("Save & Re-encrypt")
                                    .font(.scaled(size: 12.5, weight: .semibold))
                                Text("⌘S")
                                    .font(.scaled(size: 10.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.white.opacity(0.22))
                                    .clipShape(RoundedRectangle(cornerRadius: 3.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: 30)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(color: Color.blue.opacity(0.2), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("s", modifiers: .command)
                        .help("Save secrets and re-encrypt vault with Touch ID (⌘S)")
                        .accessibilityLabel("Save secrets and re-encrypt with Touch ID (Command S)")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor))
                    
                    Divider().opacity(0.5)
                    
                    // Inline Add Variable Bar
                    if isAddingSecret {
                        HStack(spacing: 10) {
                            TextField("KEY_NAME", text: $newKeyName)
                                .textFieldStyle(.roundedBorder)
                                .font(.scaled(size: 12.5, design: .monospaced))
                                .frame(width: 180)
                                .accessibilityLabel("New variable key name")
                            
                            TextField("Secret value", text: $newKeyValue)
                                .textFieldStyle(.roundedBorder)
                                .font(.scaled(size: 12.5, design: .monospaced))
                                .accessibilityLabel("New secret value")
                            
                            Button(action: {
                                store.addSecretEntry(key: newKeyName, value: newKeyValue)
                                newKeyName = ""
                                newKeyValue = ""
                                isAddingSecret = false
                            }) {
                                Text("Add")
                                    .font(.scaled(size: 12.5, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help("Add variable to vault")
                            .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Confirm add variable")
                            
                            Button(action: {
                                isAddingSecret = false
                            }) {
                                Image(systemName: "xmark")
                                    .font(.scaled(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel adding variable")
                            .accessibilityLabel("Cancel adding variable")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.06))
                        
                        Divider().opacity(0.4)
                    }
                    
                    // Table Header
                    HStack(spacing: 14) {
                        Text("VARIABLE KEY")
                            .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 240, alignment: .leading)
                        
                        Text("SECRET VALUE")
                            .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("ACTIONS")
                            .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    
                    Divider().opacity(0.5)
                    
                    // Key-Value Rows List
                    if filteredSecrets.isEmpty {
                        if store.isAuthenticating {
                            VStack(spacing: 12) {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("Decrypting secrets...")
                                    .font(.scaled(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        } else {
                            VStack(spacing: 10) {
                                Spacer()
                                Image(systemName: "tray")
                                    .font(.scaled(size: 32))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .accessibilityHidden(true)
                                Text("No secrets in this vault yet")
                                    .font(.scaled(size: 13.5))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredSecrets) { secret in
                                    SecretRowView(
                                        secret: secret,
                                        isCopied: copiedKeyId == secret.id,
                                        onToggleVisibility: {
                                            store.toggleSecretVisibility(id: secret.id)
                                        },
                                        onCopy: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(secret.value, forType: .string)
                                            copiedKeyId = secret.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                                if copiedKeyId == secret.id {
                                                    copiedKeyId = nil
                                                }
                                            }
                                        },
                                        onDelete: {
                                            store.deleteSecretEntry(id: secret.id)
                                        }
                                    )
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                    }
                }
                
                // Floating 5-Second Undo Toast Banner
                if let undo = store.activeUndoEntry {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.scaled(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("Removed '\(undo.secret.key)'")
                            .font(.scaled(size: 12.5, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            store.undoDeleteSecretEntry()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.scaled(size: 11, weight: .bold))
                                Text("Undo")
                                    .font(.scaled(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Undo secret removal")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 380)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}
}

// MARK: - Secret Row View
private struct SecretRowView: View {
    let secret: SecretEntry
    let isCopied: Bool
    let onToggleVisibility: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Key Name
            Text(secret.key)
                .font(.scaled(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 240, alignment: .leading)
                .lineLimit(1)
            
            // Value
            Group {
                if secret.isRevealed {
                    Text(secret.value)
                        .font(.scaled(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    Text(String(repeating: "•", count: max(8, min(secret.value.count, 24))))
                        .font(.scaled(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(2.0)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            
            Spacer()
            
            // Actions
            HStack(spacing: 6) {
                // Copy Button
                Button(action: onCopy) {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.scaled(size: 11))
                        if isCopied {
                            Text("Copied")
                                .font(.scaled(size: 11, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(minHeight: 28)
                    .background(isCopied ? Color.green.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundColor(isCopied ? Color(nsColor: .systemGreen) : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Copy secret value to clipboard")
                .accessibilityLabel("Copy value of \(secret.key)")
                
                // Visibility Eye Button
                Button(action: onToggleVisibility) {
                    Image(systemName: secret.isRevealed ? "eye.slash" : "eye")
                        .font(.scaled(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(secret.isRevealed ? "Mask secret" : "Reveal secret")
                .accessibilityLabel(secret.isRevealed ? "Mask \(secret.key)" : "Reveal \(secret.key)")
                
                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.scaled(size: 12))
                        .foregroundColor(Color(nsColor: .systemRed))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Delete variable")
                .accessibilityLabel("Delete variable \(secret.key)")
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 38)
        .background(isHovered ? Color.blue.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
