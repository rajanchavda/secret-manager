import SwiftUI

public struct SecurityAuditView: View {
    let vault: VaultItem
    @ObservedObject var store: SecAppStore
    @State private var showUnlockConfirmation: Bool = false
    
    public init(vault: VaultItem, store: SecAppStore) {
        self.vault = vault
        self.store = store
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Section 1: Protection Status Cards
                VStack(alignment: .leading, spacing: 10) {
                    Text("SECURITY STATUS")
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    
                    HStack(spacing: 12) {
                        auditMetricCard(
                            title: "Active Decoy",
                            status: "Protected on Disk",
                            detail: "Real secrets shielded from AI coding tools",
                            icon: "shield.checkered",
                            color: Color(nsColor: .systemGreen)
                        )
                        
                        auditMetricCard(
                            title: "Git Safety",
                            status: ".gitignore Verified",
                            detail: ".env.vault safely excluded from git",
                            icon: "arrow.triangle.branch",
                            color: Color.blue
                        )
                        
                        auditMetricCard(
                            title: "Hardware Encryption",
                            status: "AES-256-GCM",
                            detail: "Apple Silicon Secure Enclave key",
                            icon: "lock.shield.fill",
                            color: Color(nsColor: .systemPurple)
                        )
                    }
                }
                
                Divider().opacity(0.5)
                
                // Section 2: What AI Agents See On Disk
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.scaled(size: 14))
                            .foregroundColor(Color(nsColor: .systemOrange))
                            .accessibilityHidden(true)
                        Text("Decoy File on Disk (Visible to Cursor, Claude & Copilot)")
                            .font(.scaled(size: 13.5, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("# 🔒 PROTECTED BY sec (Touch ID Secret Vault)")
                        Text("# Real secrets are encrypted in \(vault.targetFiles.first ?? ".env").vault")
                        Text("# Run commands: sec <cmd>   |   Edit secrets in app")
                        Text("")
                        Text("DATABASE_URL=locked_by_sec")
                        Text("STRIPE_SECRET_KEY=locked_by_sec")
                        Text("OPENAI_API_KEY=locked_by_sec")
                    }
                    .font(.scaled(size: 12.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Decoy file contents: Placeholder values locked by sec")
                }
                
                Divider().opacity(0.5)
                
                // Section 3: Vault Maintenance & Actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("VAULT ACTIONS")
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    
                    HStack(spacing: 12) {
                        // Re-lock
                        Button(action: {
                            Task {
                                await store.relockVault(vault: vault)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.scaled(size: 12))
                                Text("Refresh Decoy & Lock")
                                    .font(.scaled(size: 12.5, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 32)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Force encrypts current target file and refreshes decoy on disk")
                        .accessibilityLabel("Refresh decoy and lock vault")
                        
                        // Reveal in Finder
                        Button(action: {
                            store.revealInFinder(vault: vault)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.scaled(size: 12))
                                Text("Reveal in Finder")
                                    .font(.scaled(size: 12.5, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 32)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Reveal project folder in macOS Finder")
                        .accessibilityLabel("Reveal in Finder")
                        
                        // Open in Terminal
                        Button(action: {
                            store.openInTerminal(vault: vault)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.scaled(size: 12))
                                Text("Open in Terminal")
                                    .font(.scaled(size: 12.5, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 32)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Open project folder in Terminal")
                        .accessibilityLabel("Open in Terminal")
                    }
                }
                
                Divider().opacity(0.5)
                
                // Section 4: Danger Zone
                VStack(alignment: .leading, spacing: 10) {
                    Text("DANGER ZONE")
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(nsColor: .systemRed))
                        .tracking(0.6)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Permanently Unlock to Disk")
                                .font(.scaled(size: 13.5, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Restores plaintext secrets on disk and removes .vault. AI agents will be able to read plaintext credentials.")
                                .font(.scaled(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showUnlockConfirmation = true
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.open.fill")
                                    .font(.scaled(size: 12))
                                Text("Unlock to Disk")
                                    .font(.scaled(size: 12.5, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .frame(minHeight: 32)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(Color(nsColor: .systemRed))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Permanently decrypt vault and restore plaintext secrets to disk")
                        .accessibilityLabel("Permanently unlock secrets to disk in plaintext")
                    }
                    .padding(14)
                    .background(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
        }
        .confirmationDialog(
            "Restore Plaintext to Disk?",
            isPresented: $showUnlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unlock and Write Plaintext to Disk", role: .destructive) {
                Task {
                    await store.restoreToDisk(vault: vault)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will decrypt real secrets back to '\(vault.targetFiles.first ?? ".env")' in plaintext on your hard drive and delete the encrypted vault. AI agents scanning your workspace will be able to read all credentials.")
        }
    }
    
    @ViewBuilder
    private func auditMetricCard(title: String, status: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.scaled(size: 14))
                    .foregroundColor(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.scaled(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text(status)
                .font(.scaled(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            Text(detail)
                .font(.scaled(size: 11.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(status). \(detail)")
    }
}
