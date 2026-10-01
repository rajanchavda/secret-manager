import SwiftUI
import AppKit

public struct DeepScannerView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Scanner Configuration Header
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scanner")
                            .font(.scaled(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Find unprotected .env and secret files across your computer")
                            .font(.scaled(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Prune Button
                    Button(action: {
                        store.pruneRegistry()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "scissors")
                                .font(.scaled(size: 12))
                            Text("Clean Up Missing")
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
                    .help("Cleans up registry entries for deleted or moved folders")
                    .accessibilityLabel("Clean up missing vaults from registry")
                }
                
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.scaled(size: 13))
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        
                        TextField("Path to scan", text: $store.scanDirectoryPath)
                            .textFieldStyle(.plain)
                            .font(.scaled(size: 13))
                            .accessibilityLabel("Path to scan directory")
                        
                        Button(action: {
                            selectFolder()
                        }) {
                            Text("Browse...")
                                .font(.scaled(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Select a directory from Finder")
                        .accessibilityLabel("Browse folder to scan")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 34)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    Button(action: {
                        Task {
                            await store.runDeepScanner()
                        }
                    }) {
                        HStack(spacing: 6) {
                            if store.isScanning {
                                ProgressView()
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.scaled(size: 13))
                            }
                            Text(store.isScanning ? "Scanning..." : "Scan Directory")
                                .font(.scaled(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .frame(minHeight: 34)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Scan selected directory for plaintext and encrypted secret files")
                    .disabled(store.isScanning)
                    .accessibilityLabel(store.isScanning ? "Scanning directory in progress" : "Scan directory for secret files")
                }
            }
            .padding(18)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider().opacity(0.5)
            
            // Discovered Table Header
            HStack(spacing: 14) {
                Text("FILE NAME")
                    .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)
                
                Text("LOCATION")
                    .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("STATUS")
                    .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 130, alignment: .leading)
                
                Text("ACTION")
                    .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            
            Divider().opacity(0.5)
            
            // Results List
            if store.discoveredFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass.circle")
                        .font(.scaled(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                    Text("No secret files scanned yet")
                        .font(.scaled(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Click 'Scan Directory' to discover all .env and secret files across your workspace.")
                        .font(.scaled(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.discoveredFiles) { item in
                            DiscoveredRowView(item: item, store: store)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.scanDirectoryPath = url.path
        }
    }
}

// MARK: - Discovered Row View
private struct DiscoveredRowView: View {
    let item: DiscoveredSecretFile
    @ObservedObject var store: SecAppStore
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Filename
            HStack(spacing: 7) {
                Image(systemName: item.isLocked ? "lock.doc.fill" : "doc.text.fill")
                    .font(.scaled(size: 14))
                    .foregroundColor(item.isLocked ? .blue : Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)
                
                Text(item.filename)
                    .font(.scaled(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(width: 150, alignment: .leading)
            
            // Location
            Text(item.abbreviatedPath)
                .font(.scaled(size: 12.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Status Pill
            HStack(spacing: 4) {
                Image(systemName: item.isLocked ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.scaled(size: 10))
                
                Text(item.isLocked ? "Protected" : "Unprotected")
                    .font(.scaled(size: 11.5, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background((item.isLocked ? Color.green : Color.orange).opacity(0.15))
            .foregroundColor(item.isLocked ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
            .clipShape(Capsule())
            .frame(width: 130, alignment: .leading)
            
            // Action
            HStack {
                if !item.isLocked {
                    Button(action: {
                        Task {
                            await store.lockDiscoveredFile(item)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.scaled(size: 11))
                            Text("Protect File")
                                .font(.scaled(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(minHeight: 28)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Encrypt secrets with Touch ID and replace with safe decoy")
                    .accessibilityLabel("Protect \(item.filename) with Touch ID")
                } else {
                    Button(action: {
                        NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                    }) {
                        Text("Show in Finder")
                            .font(.scaled(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 28)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal file in macOS Finder")
                    .accessibilityLabel("Show \(item.filename) in Finder")
                }
            }
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 38)
        .background(isHovered ? Color.blue.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
