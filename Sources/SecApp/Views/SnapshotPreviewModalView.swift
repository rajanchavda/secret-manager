import SwiftUI
import AppKit
import SecCore

public struct SnapshotPreviewModalView: View {
    @ObservedObject var store: SecAppStore
    @State private var searchText: String = ""
    @State private var viewMode: ViewMode = .table
    @State private var showRestoreConfirmation: Bool = false
    @State private var copiedFeedback: Bool = false
    
    private enum ViewMode: String, CaseIterable {
        case table = "Key-Value"
        case raw = "Raw Content"
    }
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    private var snapshot: SnapshotRecord? {
        store.activePreviewSnapshot
    }
    
    private var filteredSecrets: [SecretEntry] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.previewSnapshotSecrets
        }
        let query = searchText.lowercased()
        return store.previewSnapshotSecrets.filter {
            $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.scaled(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Snapshot Preview")
                            .font(.scaled(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("v\(snapshot?.version ?? 1)")
                            .font(.scaled(size: 11.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Text("\(snapshot?.projectName ?? "") / \(snapshot?.targetFileName ?? "") • \(snapshot?.relativeTime ?? "") • \(snapshot?.trigger.rawValue ?? "")")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Restore Button
                Button(action: {
                    showRestoreConfirmation = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.scaled(size: 11))
                        Text("Restore this Version")
                            .font(.scaled(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Restore workspace files to this snapshot's exact secrets")
                
                // Close Button
                Button(action: {
                    store.isPreviewingSnapshot = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close preview")
                .accessibilityLabel("Close snapshot preview")
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Toolbar (Search & View Mode)
            HStack(spacing: 10) {
                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                    
                    TextField("Filter secrets...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.scaled(size: 12))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.scaled(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                Spacer()
                
                // Copy all
                Button(action: {
                    let contentToCopy = store.previewSnapshotRawText.isEmpty
                        ? store.previewSnapshotSecrets.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                        : store.previewSnapshotRawText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(contentToCopy, forType: .string)
                    copiedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedFeedback = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.scaled(size: 11))
                            .foregroundColor(copiedFeedback ? .green : .secondary)
                        Text(copiedFeedback ? "Copied!" : "Copy All")
                            .font(.scaled(size: 11, weight: .medium))
                            .foregroundColor(copiedFeedback ? .green : .primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                
                // Segmented picker if structured secrets exist
                if !store.previewSnapshotSecrets.isEmpty {
                    Picker("", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider().opacity(0.5)
            
            // Content
            Group {
                if !store.previewSnapshotSecrets.isEmpty && viewMode == .table {
                    secretsTableView
                } else if !store.previewSnapshotRawText.isEmpty {
                    rawTextView
                } else {
                    emptyStateView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 460, idealHeight: 540)
        .confirmationDialog(
            "Restore to v\(snapshot?.version ?? 1)?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rollback & Restore", role: .destructive) {
                if let snap = snapshot {
                    store.isPreviewingSnapshot = false
                    Task {
                        await store.restoreSnapshot(snap)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let snap = snapshot {
                Text("This will restore '\(snap.targetFileName)' to the exact secrets from version v\(snap.version) (\(snap.relativeTime)). An auto-snapshot of current secrets will be preserved first.")
            }
        }
    }
    
    // MARK: - Key-Value Table View
    private var secretsTableView: some View {
        Group {
            if filteredSecrets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.scaled(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No secrets match '\(searchText)'")
                        .font(.scaled(size: 12.5))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        // Header
                        HStack(spacing: 12) {
                            Text("KEY")
                                .font(.scaled(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 220, alignment: .leading)
                            
                            Text("VALUE")
                                .font(.scaled(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("ACTION")
                                .font(.scaled(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        
                        Divider().opacity(0.4)
                        
                        ForEach(filteredSecrets) { secret in
                            HStack(spacing: 12) {
                                Text(secret.key)
                                    .font(.scaled(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(width: 220, alignment: .leading)
                                    .lineLimit(1)
                                
                                Text(secret.value)
                                    .font(.scaled(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(secret.value, forType: .string)
                                    store.showTemporaryStatus("Copied '\(secret.key)'")
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.scaled(size: 11))
                                        .foregroundColor(.secondary)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .help("Copy value to clipboard")
                                .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Raw Text View
    private var rawTextView: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(store.previewSnapshotRawText)
                .font(.scaled(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.scaled(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No decrypted content in this snapshot")
                .font(.scaled(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
