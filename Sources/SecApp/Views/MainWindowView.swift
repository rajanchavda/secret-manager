import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var store: SecAppStore
    @FocusState private var isSearchFocused: Bool
    @State private var isWindowDropTargeted: Bool = false
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 340)
            } detail: {
                VStack(spacing: 0) {
                    // Top Modern Toolbar
                    HStack(spacing: 12) {
                        // Global Protection Status Badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.globalShieldActive ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                                .frame(width: 9, height: 9)
                                .accessibilityHidden(true)
                            
                            Text(store.statusBadgeText)
                                .font(.scaled(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundColor(store.globalShieldActive ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((store.globalShieldActive ? Color.green : Color.orange).opacity(0.14))
                        .clipShape(Capsule())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("System status: \(store.statusBadgeText)")
                        
                        Spacer()
                        
                        // Search Field (Only on screens where searching vaults and files is relevant)
                        if isSearchVisible {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.scaled(size: 13))
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                                
                                TextField("Search vaults, files...", text: $store.searchQuery)
                                    .textFieldStyle(.plain)
                                    .font(.scaled(size: 13))
                                    .focused($isSearchFocused)
                                    .accessibilityLabel("Search vaults and files")
                                
                                if !store.searchQuery.isEmpty {
                                    Button(action: { store.searchQuery = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.scaled(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Clear search")
                                    .accessibilityLabel("Clear search text")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(width: 250, height: 32)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        // Interactive Auto-Lock Timer Shortcuts Menu
                        Menu {
                            Section("Auto-Lock Duration") {
                                Button(action: { store.selectGracePeriod(.strict) }) {
                                    Label("Strict (Lock Immediately)", systemImage: store.selectedGraceOption == .strict ? "checkmark" : "hand.raised.fill")
                                }
                                .keyboardShortcut("0", modifiers: [.command, .shift])
                                
                                Button(action: { store.selectGracePeriod(.m15) }) {
                                    Label("15 Minutes", systemImage: store.selectedGraceOption == .m15 ? "checkmark" : "timer")
                                }
                                .keyboardShortcut("1", modifiers: [.command])
                                
                                Button(action: { store.selectGracePeriod(.m30) }) {
                                    Label("30 Minutes", systemImage: store.selectedGraceOption == .m30 ? "checkmark" : "timer")
                                }
                                .keyboardShortcut("2", modifiers: [.command])
                                
                                Button(action: { store.selectGracePeriod(.h1) }) {
                                    Label("1 Hour", systemImage: store.selectedGraceOption == .h1 ? "checkmark" : "timer")
                                }
                                .keyboardShortcut("3", modifiers: [.command])
                                
                                Button(action: { store.selectGracePeriod(.untilSleep) }) {
                                    Label("Until Mac Sleeps", systemImage: store.selectedGraceOption == .untilSleep ? "checkmark" : "moon.zzz.fill")
                                }
                                .keyboardShortcut("4", modifiers: [.command])
                            }
                            
                            Section("Quick Extend") {
                                Button(action: { store.extendGracePeriod(minutes: 5) }) {
                                    Label("+5 Minutes", systemImage: "plus.circle")
                                }
                                Button(action: { store.extendGracePeriod(minutes: 15) }) {
                                    Label("+15 Minutes", systemImage: "plus.circle.fill")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: { store.lockAll() }) {
                                Label("Lock All Vaults Now", systemImage: "lock.fill")
                            }
                            .keyboardShortcut("l", modifiers: [.command])
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: store.isGraceActive ? "timer" : "hand.raised.fill")
                                    .font(.scaled(size: 12))
                                    .foregroundColor(store.isGraceActive ? Color(nsColor: .systemOrange) : .secondary)
                                
                                Text(store.isGraceActive ? "Timer: \(store.formattedRemainingTime)" : (store.selectedGraceOption == .strict ? "Strict Lock" : "Locked (\(store.selectedGraceOption.rawValue))"))
                                    .font(.scaled(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(store.isGraceActive ? Color(nsColor: .systemOrange) : .primary)
                                
                                Image(systemName: "chevron.down")
                                    .font(.scaled(size: 9, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(height: 32)
                            .background(store.isGraceActive ? Color.orange.opacity(0.12) : Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(store.isGraceActive ? Color.orange.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .help("Quickly change auto-lock duration or extend session")
                        .accessibilityLabel("Auto-lock status: \(store.isGraceActive ? store.formattedRemainingTime : "Strict mode active")")
                        
                        // Emergency Lock All Button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                store.lockAll()
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.fill")
                                    .font(.scaled(size: 12))
                                
                                if store.isGraceActive || store.unlockedVaultsCount > 0 {
                                    Text("Lock All Now (\(max(1, store.unlockedVaultsCount)))")
                                        .font(.scaled(size: 12, weight: .semibold))
                                } else {
                                    Text("Lock All")
                                        .font(.scaled(size: 12, weight: .medium))
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .frame(height: 32)
                            .background(
                                (store.isGraceActive || store.unlockedVaultsCount > 0)
                                ? Color.orange.opacity(0.18)
                                : Color.primary.opacity(0.06)
                            )
                            .foregroundColor(
                                (store.isGraceActive || store.unlockedVaultsCount > 0)
                                ? Color(nsColor: .systemOrange)
                                : .secondary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        (store.isGraceActive || store.unlockedVaultsCount > 0)
                                        ? Color.orange.opacity(0.35)
                                        : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("l", modifiers: [.command])
                        .help("Panic Lock: Revokes all active sessions and wipes decrypted RAM immediately (⌘L)")
                        .accessibilityLabel("Lock all vaults immediately")
                        
                        // Add File (+) Button
                        Button(action: {
                            store.showProtectFileModal = true
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.scaled(size: 12, weight: .bold))
                                Text("Add File")
                                    .font(.scaled(size: 12.5, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(height: 32)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(color: Color.blue.opacity(0.25), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("n", modifiers: [.command])
                        .help("Protect a new .env or secret file with Touch ID (⌘N)")
                        .accessibilityLabel("Protect new file")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .windowBackgroundColor))
                    
                    Divider().opacity(0.5)
                    
                    // Main Content Canvas
                    Group {
                        switch store.selectedTab {
                        case .allVaults, .shieldedDecoys, .inRAM:
                            VaultsListView(store: store)
                        case .backups:
                            BackupsHubView(store: store)
                        case .scanner:
                            DeepScannerView(store: store)
                        case .radar:
                            AgentRadarFullView(store: store)
                        case .settings:
                            SecuritySettingsView(store: store)
                        case .runner:
                            // Fallback if runner was previously selected
                            VaultsListView(store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewStyle(.balanced)
            
            // Temporary Toast Status Banner
            if let msg = store.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.scaled(size: 14))
                        .foregroundColor(Color(nsColor: .systemGreen))
                        .accessibilityHidden(true)
                    
                    Text(msg)
                        .font(.scaled(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Notification: \(msg)")
            }
            
            // Drag-over Visual Indicator Overlay
            if isWindowDropTargeted {
                ZStack {
                    Color.blue.opacity(0.12)
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2.5, dash: [8]))
                        .padding(12)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.scaled(size: 46))
                            .foregroundColor(.blue)
                        Text("Drop File to Encrypt with Touch ID")
                            .font(.scaled(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Release to encrypt secrets and auto-add to All Vaults")
                            .font(.scaled(size: 12.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 6)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .background(
            // Hidden buttons to register keyboard shortcuts for font zoom
            Group {
                Button(action: { store.increaseFontSize() }) { EmptyView() }
                    .keyboardShortcut("+", modifiers: [.command])
                Button(action: { store.increaseFontSize() }) { EmptyView() }
                    .keyboardShortcut("=", modifiers: [.command])
                Button(action: { store.decreaseFontSize() }) { EmptyView() }
                    .keyboardShortcut("-", modifiers: [.command])
                Button(action: { store.resetFontSize() }) { EmptyView() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .onDrop(of: [.fileURL], isTargeted: $isWindowDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    store.handleIncomingFile(url: url)
                }
            }
            return true
        }
        .sheet(isPresented: $store.showProtectFileModal) {
            ProtectFileModalView(store: store, isPresented: $store.showProtectFileModal)
        }
        .alert(
            "Encrypt '\(store.pendingEncryptionURL?.lastPathComponent ?? "File")'?",
            isPresented: $store.showEncryptConfirmation,
            presenting: store.pendingEncryptionURL
        ) { url in
            Button("Encrypt & Add to Vaults") {
                Task {
                    await store.confirmAndEncrypt(fileURL: url)
                }
            }
            Button("Cancel", role: .cancel) {
                store.pendingEncryptionURL = nil
            }
        } message: { url in
            Text("Would you like to encrypt '\(url.lastPathComponent)' with Touch ID / AES-256-GCM and add it to All Vaults?\n\nA safe decoy placeholder will replace the original file to prevent leaks to AI agents and scripts.\n\nPath: \(url.path)")
        }
    }
    
    /// The search bar is only visible on tabs that display searchable vault and file lists.
    private var isSearchVisible: Bool {
        switch store.selectedTab {
        case .allVaults, .shieldedDecoys, .inRAM, .runner:
            return true
        case .scanner, .radar, .settings, .backups:
            return false
        }
    }
}
