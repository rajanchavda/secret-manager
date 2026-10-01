import SwiftUI
import AppKit
import SecCore

public struct BackupsHubView: View {
    @ObservedObject var store: SecAppStore
    
    @State private var selectedTab: Int = 0 // 0: Snapshots, 1: Trash
    @State private var searchQuery: String = ""
    @State private var selectedSnapshotToRestore: SnapshotRecord? = nil
    @State private var showRestoreConfirmation: Bool = false
    @State private var selectedTrashToRestore: TrashRecord? = nil
    @State private var showTrashRestoreConfirmation: Bool = false
    @State private var showEmptyTrashConfirmation: Bool = false
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    private var filteredSnapshots: [SnapshotRecord] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return store.snapshots
        }
        return store.snapshots.filter {
            $0.projectName.lowercased().contains(q) ||
            $0.targetFileName.lowercased().contains(q) ||
            $0.trigger.rawValue.lowercased().contains(q) ||
            ($0.note ?? "").lowercased().contains(q)
        }
    }
    
    private var filteredTrash: [TrashRecord] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return store.trashRecords
        }
        return store.trashRecords.filter {
            $0.projectName.lowercased().contains(q) ||
            $0.targetFileName.lowercased().contains(q) ||
            $0.reason.lowercased().contains(q)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Banner
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.scaled(size: 20, weight: .semibold))
                        .foregroundColor(.teal)
                }
                .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Backups & Version History")
                            .font(.scaled(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        // Count badges
                        HStack(spacing: 6) {
                            Text("\(store.snapshots.count) snapshots")
                                .font(.scaled(size: 10.5, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                            
                            if !store.trashRecords.isEmpty {
                                Text("\(store.trashRecords.count) in trash")
                                    .font(.scaled(size: 10.5, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundColor(Color(nsColor: .systemRed))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    Text("Point-in-time encrypted snapshots with Touch ID rollback & soft-deleted trash recovery")
                        .font(.scaled(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Backup All Button
                Button(action: {
                    Task {
                        await store.backupAllVaults()
                    }
                }) {
                    HStack(spacing: 6) {
                        if store.isBackingUpAll {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.scaled(size: 12))
                        }
                        Text(store.isBackingUpAll ? "Backing up..." : "Backup All Now")
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
                .disabled(store.isBackingUpAll)
                .help("Create point-in-time snapshots for all registered project vaults")
                .accessibilityLabel("Backup all registered vaults now")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider().opacity(0.5)
            
            // Sub-Toolbar: Segmented Tab + Search
            HStack(spacing: 12) {
                Picker("Section", selection: $selectedTab) {
                    Text("Snapshots (\(store.snapshots.count))").tag(0)
                    Text("Trash (\(store.trashRecords.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .frame(width: 280)
                
                Spacer()
                
                // Search Input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    
                    TextField("Filter by project, file, trigger...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.scaled(size: 12))
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.scaled(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 240, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                if selectedTab == 1 && !store.trashRecords.isEmpty {
                    Button(action: {
                        showEmptyTrashConfirmation = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.scaled(size: 11))
                            Text("Empty Trash")
                                .font(.scaled(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .frame(height: 28)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(Color(nsColor: .systemRed))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Permanently delete all soft-deleted vaults from trash")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            
            Divider().opacity(0.4)
            
            // Content List
            Group {
                if selectedTab == 0 {
                    snapshotsListContent
                } else {
                    trashListContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .confirmationDialog(
            "Restore to v\(selectedSnapshotToRestore?.version ?? 1)?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rollback & Restore", role: .destructive) {
                if let snap = selectedSnapshotToRestore {
                    Task {
                        await store.restoreSnapshot(snap)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let snap = selectedSnapshotToRestore {
                Text("This will restore '\(snap.targetFileName)' to the exact secrets from version v\(snap.version) (\(snap.relativeTime)). An auto-snapshot of current secrets will be preserved first.")
            }
        }
        .confirmationDialog(
            "Restore from Trash?",
            isPresented: $showTrashRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Vault to Workspace") {
                if let item = selectedTrashToRestore {
                    Task {
                        await store.restoreTrashItem(item)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let item = selectedTrashToRestore {
                Text("This will restore '\(item.targetFileName)' and its encrypted vault back to its original workspace at '\(item.projectPath)'.")
            }
        }
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $showEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Permanently Empty Trash", role: .destructive) {
                store.purgeAllTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all soft-deleted vaults stored in ~/.sec/trash. This cannot be undone.")
        }
        .sheet(isPresented: $store.isPreviewingSnapshot) {
            SnapshotPreviewModalView(store: store)
        }
    }
    
    // MARK: - Snapshots List
    private var snapshotsListContent: some View {
        Group {
            if filteredSnapshots.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.scaled(size: 38))
                        .foregroundColor(.secondary.opacity(0.4))
                        .accessibilityHidden(true)
                    Text("No snapshots recorded yet")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Snapshots are automatically created whenever secrets are edited or unlocked, or when clicking 'Backup All Now'.")
                        .font(.scaled(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSnapshots) { snapshot in
                            snapshotRowView(snapshot: snapshot)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
    
    @ViewBuilder
    private func snapshotRowView(snapshot: SnapshotRecord) -> some View {
        HStack(spacing: 12) {
            // Version Badge
            VStack(spacing: 2) {
                Text("v\(snapshot.version)")
                    .font(.scaled(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
            .frame(width: 44, height: 38)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Trigger Icon & Name
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.projectName)
                        .font(.scaled(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(snapshot.targetFileName)
                        .font(.scaled(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    // Trigger pill
                    HStack(spacing: 3) {
                        Image(systemName: snapshot.trigger.iconName)
                            .font(.scaled(size: 9))
                        Text(snapshot.trigger.rawValue)
                            .font(.scaled(size: 9.5, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
                }
                
                HStack(spacing: 8) {
                    Text(snapshot.relativeTime)
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                    
                    if snapshot.keyCount > 0 {
                        Text("•")
                            .font(.scaled(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("\(snapshot.keyCount) keys")
                            .font(.scaled(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    if let note = snapshot.note, !note.isEmpty {
                        Text("•")
                            .font(.scaled(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(note)
                            .font(.scaled(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 6) {
                Button(action: {
                    Task {
                        await store.previewSnapshot(snapshot)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.scaled(size: 10.5))
                        Text("Preview")
                            .font(.scaled(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Preview encrypted secrets contained in this snapshot")
                
                Button(action: {
                    selectedSnapshotToRestore = snapshot
                    showRestoreConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.scaled(size: 10.5))
                        Text("Restore")
                            .font(.scaled(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Roll back this vault to version v\(snapshot.version)")
                
                Button(action: {
                    store.deleteSnapshot(snapshot)
                }) {
                    Image(systemName: "trash")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Delete this snapshot")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Trash List
    private var trashListContent: some View {
        Group {
            if filteredTrash.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.scaled(size: 38))
                        .foregroundColor(.secondary.opacity(0.4))
                        .accessibilityHidden(true)
                    Text("Trash is empty")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Vaults that are unlocked to disk or removed from the workspace are automatically preserved here so you can recover them anytime.")
                        .font(.scaled(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredTrash) { item in
                            trashRowView(item: item)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
    
    @ViewBuilder
    private func trashRowView(item: TrashRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: "trash.fill")
                    .font(.scaled(size: 14))
                    .foregroundColor(Color(nsColor: .systemRed))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.projectName)
                        .font(.scaled(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(item.targetFileName)
                        .font(.scaled(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                HStack(spacing: 8) {
                    Text("Removed \(item.relativeTime)")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.scaled(size: 10))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text(item.reason)
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                    
                    if item.originalKeyCount > 0 {
                        Text("•")
                            .font(.scaled(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("\(item.originalKeyCount) keys preserved")
                            .font(.scaled(size: 11, design: .monospaced))
                            .foregroundColor(Color(nsColor: .systemGreen))
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Button(action: {
                    selectedTrashToRestore = item
                    showTrashRestoreConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.backward.fill")
                            .font(.scaled(size: 10.5))
                        Text("Restore Vault")
                            .font(.scaled(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.green.opacity(0.12))
                    .foregroundColor(Color(nsColor: .systemGreen))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Restore this vault and its secrets back into its original workspace")
                
                Button(action: {
                    store.purgeTrashItem(item)
                }) {
                    Image(systemName: "xmark")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Purge permanently from trash")
            }
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
