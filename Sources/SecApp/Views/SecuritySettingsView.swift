import SwiftUI
import SecCore

public struct SecuritySettingsView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Section 1: Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.scaled(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Manage auto-lock policies, macOS Finder integration, and interface scaling")
                        .font(.scaled(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Divider().opacity(0.5)
                
                // Section 3: Access Policy & Grace Period
                VStack(alignment: .leading, spacing: 10) {
                    Text("AUTO-LOCK & SESSION")
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Touch ID Auto-Lock Timer")
                                    .font(.scaled(size: 13.5, weight: .semibold))
                                Text("Strict mode requires Touch ID on every run. Timed modes keep secrets in memory temporarily.")
                                    .font(.scaled(size: 12.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker("Auto-lock period", selection: $store.selectedGraceOption) {
                                ForEach(GracePeriodOption.allCases) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)
                            .onChange(of: store.selectedGraceOption) { _, opt in
                                store.selectGracePeriod(opt)
                            }
                            .accessibilityLabel("Select auto-lock duration")
                        }
                        
                        Divider().opacity(0.3)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Instant Revoke (Lock All)")
                                    .font(.scaled(size: 13.5, weight: .semibold))
                                Text("Immediately purge all memory session tokens and require Touch ID on the next command.")
                                    .font(.scaled(size: 12.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                store.lockAll()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "lock.fill")
                                        .font(.scaled(size: 12))
                                    Text("Lock All Now")
                                        .font(.scaled(size: 12.5, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(minHeight: 30)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(Color(nsColor: .systemOrange))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Immediately lock all vaults and purge RAM")
                            .accessibilityLabel("Immediately lock all vaults and purge memory")
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Section 4: Finder Quick Actions Integration
                VStack(alignment: .leading, spacing: 10) {
                    Text("FINDER INTEGRATION")
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("Finder Right-Click Quick Actions")
                                        .font(.scaled(size: 13.5, weight: .semibold))
                                    
                                    Text(store.isFinderActionsInstalled ? "Installed" : "Not Installed")
                                        .font(.scaled(size: 11, weight: .semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background((store.isFinderActionsInstalled ? Color.green : Color.secondary).opacity(0.15))
                                        .foregroundColor(store.isFinderActionsInstalled ? Color(nsColor: .systemGreen) : .secondary)
                                        .clipShape(Capsule())
                                }
                                
                                Text("Right-click any file in macOS Finder ➡️ Quick Actions ➡️ Lock/Unlock/Edit/View Secrets.")
                                    .font(.scaled(size: 12.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                store.toggleFinderActions()
                            }) {
                                Text(store.isFinderActionsInstalled ? "Uninstall Actions" : "Install in Finder")
                                    .font(.scaled(size: 12.5, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .frame(minHeight: 32)
                                    .background(store.isFinderActionsInstalled ? Color.primary.opacity(0.06) : Color.blue)
                                    .foregroundColor(store.isFinderActionsInstalled ? .primary : .white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help(store.isFinderActionsInstalled ? "Uninstall macOS Finder right-click Quick Actions" : "Install macOS Finder right-click Quick Actions")
                            .accessibilityLabel(store.isFinderActionsInstalled ? "Uninstall Finder Quick Actions" : "Install Finder Quick Actions")
                        }
                        
                        Divider().opacity(0.3)
                        
                        // Included actions overview
                        HStack(spacing: 12) {
                            actionBadge(name: "Lock with Touch ID", icon: "lock.shield.fill")
                            actionBadge(name: "Unlock with Touch ID", icon: "lock.open.fill")
                            actionBadge(name: "Edit Secrets", icon: "pencil")
                            actionBadge(name: "View Secrets", icon: "eye.fill")
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Section 6: Appearance & Font Scaling
                VStack(alignment: .leading, spacing: 10) {
                    Text("APPEARANCE & ACCESSIBILITY")
                        .font(.scaled(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("Application Font Scaling")
                                        .font(.scaled(size: 13.5, weight: .semibold))
                                    
                                    Text("\(Int(round(store.fontScale * 100)))%")
                                        .font(.scaled(size: 11, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }
                                
                                Text("Zoom the UI fonts in or out dynamically using ⌘+ / ⌘- shortcuts or standard View menu.")
                                    .font(.scaled(size: 12.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Button(action: {
                                    store.decreaseFontSize()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "minus")
                                            .font(.scaled(size: 11, weight: .bold))
                                        Text("Smaller")
                                            .font(.scaled(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .help("Zoom out / smaller text (⌘-)")
                                .accessibilityLabel("Decrease font size")
                                
                                Button(action: {
                                    store.resetFontSize()
                                }) {
                                    Text("100%")
                                        .font(.scaled(size: 11.5, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(store.fontScale == 1.0 ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                                        .foregroundColor(store.fontScale == 1.0 ? .blue : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .help("Reset font size to default 100% (⌘0)")
                                .accessibilityLabel("Reset font size")
                                
                                Button(action: {
                                    store.increaseFontSize()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.scaled(size: 11, weight: .bold))
                                        Text("Bigger")
                                            .font(.scaled(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .help("Zoom in / larger text (⌘+)")
                                .accessibilityLabel("Increase font size")
                            }
                        }
                        
                        Divider().opacity(0.3)
                        
                        // Live Font Scaling Preview Banner
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("LIVE PREVIEW")
                                    .font(.scaled(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    actionBadge(name: "⌘- Smaller", icon: "minus.magnifyingglass")
                                    actionBadge(name: "⌘0 Reset", icon: "arrow.counterclockwise")
                                    actionBadge(name: "⌘+ Bigger", icon: "plus.magnifyingglass")
                                }
                            }
                            
                            HStack {
                                Text("DATABASE_URL=postgres://app_user:••••••••@127.0.0.1:5432/production")
                                    .font(.scaled(size: 12.5, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("AES-256-GCM")
                                    .font(.scaled(size: 10.5, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.14))
                                    .foregroundColor(Color(nsColor: .systemGreen))
                                    .clipShape(Capsule())
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    @ViewBuilder
    private func actionBadge(name: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.scaled(size: 11))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(name)
                .font(.scaled(size: 11.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
