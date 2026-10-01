import SwiftUI

public struct RawEnvEditorView: View {
    let vault: VaultItem
    @ObservedObject var store: SecAppStore
    
    public init(vault: VaultItem, store: SecAppStore) {
        self.vault = vault
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !store.isVaultUnlockedInUI {
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "lock.doc.fill")
                        .font(.scaled(size: 44))
                        .foregroundColor(.blue.opacity(0.85))
                        .accessibilityHidden(true)
                    
                    Text("Unlock to Edit Raw Configuration")
                        .font(.scaled(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Button(action: {
                        Task {
                            await store.unlockVaultSecrets(for: vault)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "touchid")
                                .font(.scaled(size: 14))
                            Text("Unlock with Touch ID")
                                .font(.scaled(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .frame(minHeight: 36)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Unlock raw configuration with Touch ID")
                    .accessibilityLabel("Unlock raw configuration with Touch ID")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            } else {
                // Toolbar
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.scaled(size: 13))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text("\(store.currentRawEnv.components(separatedBy: "\n").count) lines")
                            .font(.scaled(size: 12.5, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        // Dirty / Saved status badge
                        if store.isRawEnvDirty {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                Text("Unsaved Changes")
                                    .font(.scaled(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.scaled(size: 10))
                                    .foregroundColor(.green)
                                Text("Encrypted & Synced")
                                    .font(.scaled(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.green.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Open in External $EDITOR button (sec edit)
                    Button(action: {
                        store.editWithExternalEditor(vault: vault)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.scaled(size: 12))
                            Text("Open in External Editor")
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
                    .help("Opens secure ephemeral buffer in VS Code / Cursor / Zed and automatically re-encrypts on save")
                    .accessibilityLabel("Open in external editor")
                    
                    // Save & Re-encrypt Button (Cmd+S)
                    Button(action: {
                        Task {
                            await store.saveSecretsToVault(for: vault)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
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
                        .background(store.isRawEnvDirty ? Color.blue : Color.blue.opacity(0.85))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Color.blue.opacity(store.isRawEnvDirty ? 0.35 : 0.15), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save changes and re-encrypt with Touch ID (⌘S)")
                    .accessibilityLabel("Save raw file and re-encrypt with Touch ID (Command S)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider().opacity(0.5)
                
                // Text Editor Canvas
                TextEditor(text: $store.currentRawEnv)
                    .font(.scaled(size: 13.5, weight: .regular, design: .monospaced))
                    .lineSpacing(5)
                    .padding(14)
                    .background(Color(nsColor: .textBackgroundColor))
                    .accessibilityLabel("Raw secrets file editor")
            }
        }
    }
}
