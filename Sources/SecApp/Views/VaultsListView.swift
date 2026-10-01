import SwiftUI

public struct VaultsListView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    @State private var collapsedVaultIds: Set<UUID> = []
    
    public var body: some View {
        HSplitView {
            // Master Vault Cards Column
            VStack(spacing: 0) {
                // Header Bar with Count & Add Button
                HStack(spacing: 8) {
                    Text(store.selectedTab.rawValue.uppercased())
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    
                    Text("(\(store.filteredVaults.count))")
                        .font(.scaled(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Expand/Collapse All Toggle Button
                    if !store.filteredVaults.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if collapsedVaultIds.count == store.filteredVaults.count {
                                    collapsedVaultIds.removeAll()
                                } else {
                                    collapsedVaultIds = Set(store.filteredVaults.map { $0.id })
                                }
                            }
                        }) {
                            Image(systemName: collapsedVaultIds.count == store.filteredVaults.count ? "chevron.down.square" : "chevron.up.square")
                                .font(.scaled(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(collapsedVaultIds.count == store.filteredVaults.count ? "Expand All Folders" : "Collapse All Folders")
                        .accessibilityLabel("Toggle folder collapse")
                    }
                    
                    Button(action: {
                        store.showProtectFileModal = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.scaled(size: 11, weight: .bold))
                            Text("Add File")
                                .font(.scaled(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Protect and encrypt a secret file with Touch ID")
                    .accessibilityLabel("Add File to protect")
                    
                    Button(action: {
                        withAnimation {
                            store.loadVaultsFromRegistry()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.scaled(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh registered vaults")
                    .accessibilityLabel("Refresh registered vaults")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider().opacity(0.5)
                
                if store.filteredVaults.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.04))
                                .frame(width: 76, height: 76)
                            
                            Image(systemName: store.searchQuery.isEmpty ? "lock.slash" : "magnifyingglass")
                                .font(.scaled(size: 34))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .accessibilityHidden(true)
                        
                        Text(store.searchQuery.isEmpty ? "No Vaults Found" : "No Matching Vaults")
                            .font(.scaled(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(store.searchQuery.isEmpty 
                             ? "Drag any .env or secret file from Finder into the app to encrypt it with Touch ID." 
                             : "No encrypted files matched \"\(store.searchQuery)\".")
                            .font(.scaled(size: 12.5))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        
                        if store.searchQuery.isEmpty {
                            Button("Protect a File...") {
                                store.showProtectFileModal = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .font(.scaled(size: 12.5, weight: .medium))
                            .help("Choose a secret file to encrypt and protect")
                        } else {
                            Button("Clear Search") {
                                store.searchQuery = ""
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Clear current search filter")
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 10) {
                            ForEach(store.filteredVaults) { vault in
                                VSCodeFolderTreeView(
                                    vault: vault,
                                    isSelected: store.selectedVault?.id == vault.id,
                                    isExpanded: !collapsedVaultIds.contains(vault.id),
                                    onToggleExpand: {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            if collapsedVaultIds.contains(vault.id) {
                                                collapsedVaultIds.remove(vault.id)
                                            } else {
                                                collapsedVaultIds.insert(vault.id)
                                            }
                                        }
                                    },
                                    onSelectVault: {
                                        store.selectVault(vault)
                                    },
                                    onSelectFile: { filename in
                                        store.selectVault(vault)
                                        Task {
                                            await store.selectActiveFile(filename, for: vault)
                                        }
                                    },
                                    store: store
                                )
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
            
            // Detail Canvas Column
            Group {
                if let selected = store.selectedVault {
                    VaultDetailView(vault: selected, store: store)
                } else if store.vaults.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue.opacity(0.08))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.scaled(size: 36))
                                .foregroundColor(.blue)
                        }
                        .accessibilityHidden(true)
                        
                        Text("No Vaults Protected Yet")
                            .font(.scaled(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Drag and drop your .env or secret file here from Finder.\nWe will prompt to encrypt it with Touch ID and add it to All Vaults.")
                            .font(.scaled(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                        
                        Button("Choose File to Encrypt...") {
                            store.showProtectFileModal = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .help("Choose a file to encrypt with Touch ID")
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "sidebar.left")
                            .font(.scaled(size: 44))
                            .foregroundColor(.secondary.opacity(0.5))
                            .accessibilityHidden(true)
                        Text("Select a Vault to Inspect Secrets")
                            .font(.scaled(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
            .frame(minWidth: 480)
        }
    }
}

// MARK: - VS Code-Style Folder Tree Component
private struct VSCodeFolderTreeView: View {
    let vault: VaultItem
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSelectVault: () -> Void
    let onSelectFile: (String) -> Void
    @ObservedObject var store: SecAppStore
    @State private var isHeaderHovered: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Folder Header Row (VS Code Explorer directory node)
            HStack(spacing: 7) {
                // Expansion Chevron Button
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.scaled(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse project folder" : "Expand project folder")
                .accessibilityLabel(isExpanded ? "Collapse folder \(vault.projectName)" : "Expand folder \(vault.projectName)")
                
                // Folder Icon
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.scaled(size: 14))
                    .foregroundColor(Color.blue)
                
                // Folder Project Name
                Text(vault.projectName)
                    .font(.scaled(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // File Count Pill
                HStack(spacing: 2) {
                    Text("\(vault.files.count)")
                        .font(.scaled(size: 10, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 4) {
                    Image(systemName: vault.status.iconName)
                        .font(.scaled(size: 9))
                    Text(vault.status.rawValue)
                        .font(.scaled(size: 10.5, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(vault.status.color.opacity(0.14))
                .foregroundColor(vault.status.color)
                .clipShape(Capsule())
                
                // Reveal in Finder Button on Hover
                if isHeaderHovered {
                    Button(action: {
                        store.revealInFinder(vault: vault)
                    }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.scaled(size: 11.5))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal folder in Finder")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHeaderHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectVault()
            }
            .onHover { hovering in
                isHeaderHovered = hovering
            }
            
            // Nested Files Tree Rows (VS Code Tree Indentation)
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(Array(vault.files.enumerated()), id: \.element.id) { index, file in
                        let isLast = index == vault.files.count - 1
                        let isFileActive = isSelected && vault.activeFile == file.filename
                        
                        VSCodeFileTreeRow(
                            file: file,
                            vault: vault,
                            isLast: isLast,
                            isActive: isFileActive,
                            onSelect: {
                                onSelectFile(file.filename)
                            },
                            store: store
                        )
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            
            // Directory Path Bar (Subtle bottom caption)
            HStack {
                Text(vault.abbreviatedPath)
                    .font(.scaled(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 3)
            .padding(.bottom, 6)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Color.blue.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: isSelected ? Color.blue.opacity(0.08) : Color.clear, radius: 4, x: 0, y: 1)
    }
}

// MARK: - VS Code Nested File Row
private struct VSCodeFileTreeRow: View {
    let file: VaultFileInfo
    let vault: VaultItem
    let isLast: Bool
    let isActive: Bool
    let onSelect: () -> Void
    @ObservedObject var store: SecAppStore
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // VS Code Tree Guide Line & Indent
                HStack(spacing: 0) {
                    // Tree Guide Vertical Line
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1.5)
                        .padding(.leading, 17)
                        .padding(.trailing, 8)
                    
                    // Tree Branch Connector
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 8, height: 1.5)
                        .padding(.trailing, 6)
                }
                .frame(height: 28)
                
                // File Content
                HStack(spacing: 6) {
                    // Left Active Indicator Bar (VS Code active file highlight)
                    if isActive {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.blue)
                            .frame(width: 2.5, height: 16)
                    }
                    
                    // File Icon with Status Dot
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "doc.text.fill")
                            .font(.scaled(size: 11.5))
                            .foregroundColor(isActive ? Color.blue : Color.secondary)
                        
                        Circle()
                            .fill(file.status == .protectedWithDecoy ? Color.green : (file.status == .inRAM ? Color.purple : Color.orange))
                            .frame(width: 4.5, height: 4.5)
                            .offset(x: 2, y: 2)
                    }
                    .frame(width: 14, height: 14)
                    
                    // Monospace Filename
                    Text(file.filename)
                        .font(.scaled(size: 11.5, weight: isActive ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(isActive ? Color.blue : Color.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Key Count Badge
                    if file.keyCount > 0 {
                        Text("\(file.keyCount) keys")
                            .font(.scaled(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    // Individual File Status Tag
                    Text(file.status == .protectedWithDecoy ? "Decoy" : (file.status == .inRAM ? "In RAM" : "Plain"))
                        .font(.scaled(size: 9.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(file.status.color.opacity(0.12))
                        .foregroundColor(file.status.color)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    
                    // Hover Quick Action: Edit in external editor
                    if isHovered {
                        Button(action: {
                            Task {
                                await store.selectActiveFile(file.filename, for: vault)
                                store.editWithExternalEditor(vault: vault)
                            }
                        }) {
                            Image(systemName: "pencil")
                                .font(.scaled(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help("Edit \(file.filename)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.blue.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
        }
        .buttonStyle(.plain)
        .help("Inspect secrets in \(file.filename)")
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File \(file.filename) in \(vault.projectName), status \(file.status.rawValue), \(file.keyCount) keys")
    }
}

