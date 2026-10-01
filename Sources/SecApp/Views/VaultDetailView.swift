import SwiftUI
import SecCore

public struct VaultDetailView: View {
    let vault: VaultItem
    @ObservedObject var store: SecAppStore
    
    public init(vault: VaultItem, store: SecAppStore) {
        self.vault = vault
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Project Top Detail Banner
            HStack(spacing: 14) {
                // Folder / Lock Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.scaled(size: 22))
                        .foregroundColor(.blue)
                }
                .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(vault.projectName)
                            .font(.scaled(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        if vault.isFolderStack {
                            HStack(spacing: 3) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.scaled(size: 10, weight: .bold))
                                Text("\(vault.totalFileCount) files")
                                    .font(.scaled(size: 11, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                        }
                        
                        // Status Pill
                        HStack(spacing: 4) {
                            Image(systemName: vault.status.iconName)
                                .font(.scaled(size: 11))
                            Text(vault.status.rawValue)
                                .font(.scaled(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(vault.status.color.opacity(0.15))
                        .foregroundColor(vault.status.color)
                        .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 8) {
                        Text(vault.directoryPath)
                            .font(.scaled(size: 12.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Button(action: {
                            store.revealInFinder(vault: vault)
                        }) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.scaled(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                        .accessibilityLabel("Reveal \(vault.projectName) folder in Finder")
                    }
                }
                
                Spacer()
                
                // Manual Snapshot Button
                Button(action: {
                    Task {
                        await store.createManualBackup(for: vault)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.scaled(size: 12))
                        Text("Snapshot")
                            .font(.scaled(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(height: 32)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Create an immutable point-in-time backup snapshot for '\(vault.activeFile)'")
                .accessibilityLabel("Create snapshot backup")
                
                // Lock / Re-lock Action Button
                Button(action: {
                    Task {
                        await store.relockVault(vault: vault)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.scaled(size: 12))
                        Text(vault.isFolderStack ? "Re-lock Folder" : "Re-lock Vault")
                            .font(.scaled(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(height: 32)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Lock this vault and purge memory")
                .accessibilityLabel("Re-lock vault for \(vault.projectName)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider().opacity(0.5)
            
            // VS Code-Style Breadcrumbs Bar
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.scaled(size: 11))
                    .foregroundColor(.blue)
                
                Text(vault.projectName)
                    .font(.scaled(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.6))
                
                Image(systemName: "doc.text.fill")
                    .font(.scaled(size: 11))
                    .foregroundColor(.primary)
                
                Text(vault.activeFile)
                    .font(.scaled(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                
                if store.isRawEnvDirty {
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5.5, height: 5.5)
                        Text("unsaved")
                            .font(.scaled(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            
            Divider().opacity(0.4)
            
            // VS Code-Style Editor Tabs (when multiple files exist in folder)
            if vault.isFolderStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(vault.files) { file in
                            let isActive = vault.activeFile == file.filename
                            Button(action: {
                                Task {
                                    await store.selectActiveFile(file.filename, for: vault)
                                }
                            }) {
                                VStack(spacing: 0) {
                                    // Top Active Accent Line (VS Code editor tab active indicator)
                                    Rectangle()
                                        .fill(isActive ? Color.blue : Color.clear)
                                        .frame(height: 2)
                                    
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(file.status == .protectedWithDecoy ? Color.green : (file.status == .inRAM ? Color.purple : Color.orange))
                                            .frame(width: 5.5, height: 5.5)
                                        
                                        Image(systemName: "doc.text.fill")
                                            .font(.scaled(size: 11))
                                            .foregroundColor(isActive ? Color.blue : Color.secondary)
                                        
                                        Text(file.filename)
                                            .font(.scaled(size: 11.5, weight: isActive ? .semibold : .regular, design: .monospaced))
                                            .foregroundColor(isActive ? .primary : .secondary)
                                        
                                        if isActive && store.isRawEnvDirty {
                                            Circle()
                                                .fill(Color.orange)
                                                .frame(width: 5, height: 5)
                                                .help("Unsaved changes (⌘S)")
                                        }
                                        
                                        if file.keyCount > 0 {
                                            Text("(\(file.keyCount))")
                                                .font(.scaled(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                }
                                .background(isActive ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .help("Switch to \(file.filename)")
                        }
                        
                        Spacer()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                
                Divider().opacity(0.4)
            }
            
            // Segmented View Selector Tab
            HStack {
                Picker("Vault View Mode", selection: $store.secretEditorTab) {
                    Text("Secrets").tag(0)
                    Text("Raw File").tag(1)
                    Text("Decoy & Safety").tag(2)
                    Text("History (\(currentFileSnapshots.count))").tag(3)
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 480)
                .help("Select view mode: structured secrets, raw file, decoy audit, or version history")
                .accessibilityLabel("Vault view options")
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider().opacity(0.5)
            
            // Content Pane
            Group {
                switch store.secretEditorTab {
                case 0:
                    SecretTableView(vault: vault, store: store)
                case 1:
                    RawEnvEditorView(vault: vault, store: store)
                case 2:
                    SecurityAuditView(vault: vault, store: store)
                default:
                    VaultHistoryPane(vault: vault, store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            store.loadBackupsAndTrash()
        }
        .onChange(of: store.secretEditorTab) { _, newTab in
            if newTab == 3 {
                store.loadBackupsAndTrash()
            }
        }
    }
    
    private var currentFileSnapshots: [SnapshotRecord] {
        let normalizedVaultDir = URL(fileURLWithPath: vault.directoryPath).standardizedFileURL.resolvingSymlinksInPath().path
        let vaultHash = BackupEngine.deterministicProjectHash(for: URL(fileURLWithPath: vault.directoryPath))
        return store.snapshots.filter {
            let snapDir = URL(fileURLWithPath: $0.projectPath).standardizedFileURL.resolvingSymlinksInPath().path
            let matchesPath = snapDir == normalizedVaultDir || $0.projectPath == vault.directoryPath || $0.projectHash == vaultHash
            return matchesPath && $0.targetFileName == vault.activeFile
        }
    }
}

// MARK: - In-Context Vault History Pane
private struct VaultHistoryPane: View {
    let vault: VaultItem
    @ObservedObject var store: SecAppStore
    
    @State private var snapshotToRestore: SnapshotRecord? = nil
    @State private var showConfirm: Bool = false
    
    private var snapshots: [SnapshotRecord] {
        let normalizedVaultDir = URL(fileURLWithPath: vault.directoryPath).standardizedFileURL.resolvingSymlinksInPath().path
        let vaultHash = BackupEngine.deterministicProjectHash(for: URL(fileURLWithPath: vault.directoryPath))
        return store.snapshots.filter {
            let snapDir = URL(fileURLWithPath: $0.projectPath).standardizedFileURL.resolvingSymlinksInPath().path
            let matchesPath = snapDir == normalizedVaultDir || $0.projectPath == vault.directoryPath || $0.projectHash == vaultHash
            return matchesPath && $0.targetFileName == vault.activeFile
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if snapshots.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.scaled(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                        .accessibilityHidden(true)
                    Text("No snapshots recorded for '\(vault.activeFile)' yet")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Click 'Snapshot' in the top right or edit secrets to start tracking version snapshots.")
                        .font(.scaled(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    
                    Button(action: {
                        Task {
                            await store.createManualBackup(for: vault)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "camera.badge.ellipsis")
                                .font(.scaled(size: 12))
                            Text("Create First Snapshot")
                                .font(.scaled(size: 12.5, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(snapshots) { snap in
                            HStack(spacing: 12) {
                                Text("v\(snap.version)")
                                    .font(.scaled(size: 12.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .frame(width: 40, height: 34)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                VStack(alignment: .leading, spacing: 2.5) {
                                    HStack(spacing: 6) {
                                        Text(snap.trigger.rawValue)
                                            .font(.scaled(size: 12.5, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        if let note = snap.note, !note.isEmpty {
                                            Text("•")
                                                .foregroundColor(.secondary.opacity(0.4))
                                            Text(note)
                                                .font(.scaled(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text(snap.relativeTime)
                                            .font(.scaled(size: 11))
                                            .foregroundColor(.secondary)
                                        
                                        if snap.keyCount > 0 {
                                            Text("•")
                                                .font(.scaled(size: 10))
                                                .foregroundColor(.secondary.opacity(0.4))
                                            Text("\(snap.keyCount) keys")
                                                .font(.scaled(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    Task {
                                        await store.previewSnapshot(snap)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: store.isVaultUnlockedInUI ? "eye" : "touchid")
                                            .font(.scaled(size: 10))
                                        Text(store.isVaultUnlockedInUI ? "Preview" : "Touch ID Preview")
                                            .font(.scaled(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help(store.isVaultUnlockedInUI ? "Preview snapshot secrets" : "Authenticate with Touch ID to preview snapshot")
                                
                                Button(action: {
                                    snapshotToRestore = snap
                                    showConfirm = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.scaled(size: 10))
                                        Text("Rollback")
                                            .font(.scaled(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help("Rollback to version v\(snap.version)")
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .confirmationDialog(
            "Rollback to v\(snapshotToRestore?.version ?? 1)?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Rollback to this Version", role: .destructive) {
                if let s = snapshotToRestore {
                    Task {
                        await store.restoreSnapshot(s)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let s = snapshotToRestore {
                Text("This will restore '\(s.targetFileName)' to version v\(s.version). A snapshot of the current state will be saved automatically first.")
            }
        }
        .sheet(isPresented: $store.isPreviewingSnapshot) {
            SnapshotPreviewModalView(store: store)
        }
        .onAppear {
            store.loadBackupsAndTrash()
        }
    }
}
