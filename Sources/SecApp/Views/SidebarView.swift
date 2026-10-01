import SwiftUI

public struct SidebarView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // App Branding Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.85), Color.teal.opacity(0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)
                        .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.scaled(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Secret Manager")
                        .font(.scaled(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Touch ID Vault")
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(store.globalShieldActive ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                        .frame(width: 9, height: 9)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.globalShieldActive ? "All vaults shielded from AI agents" : "Unshielded plaintext detected")
                .help(store.globalShieldActive ? "All vaults shielded from AI agents" : "Unshielded plaintext detected")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)
            
            Divider()
                .opacity(0.6)
                .padding(.horizontal, 10)
            
            // Navigation List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Group 1: Vaults
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VAULTS")
                            .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .tracking(0.6)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                        
                        sidebarButton(tab: .allVaults, badge: "\(store.vaults.count)")
                        sidebarButton(tab: .shieldedDecoys, badge: "\(store.vaults.filter { $0.status == .protectedWithDecoy }.count)")
                        sidebarButton(tab: .inRAM, badge: "\(store.vaults.filter { $0.status == .inRAM }.count)")
                    }
                    
                    // Group 2: Tools (Runner Studio hidden)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOOLS")
                            .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .tracking(0.6)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                        
                        sidebarButton(tab: .backups, badge: store.trashRecords.isEmpty ? nil : "\(store.trashRecords.count)")
                        sidebarButton(tab: .scanner, badge: nil)
                        sidebarButton(tab: .radar, badge: store.radarEvents.isEmpty ? nil : "\(store.radarEvents.count)")
                    }
                    
                    // Group 3: Settings
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PREFERENCES")
                            .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .tracking(0.6)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                        
                        sidebarButton(tab: .settings, badge: nil)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
            Divider()
                .opacity(0.6)
                .padding(.horizontal, 10)
            
            VStack(spacing: 8) {
                // Live Process RAM & In-Memory Secrets Monitor
                MemoryFooterView(store: store)
                
                // Bottom Secure Enclave Hardware Badge
                HStack(spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .font(.scaled(size: 14))
                        .foregroundColor(Color(nsColor: .systemGreen))
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Secure Enclave")
                            .font(.scaled(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Hardware AES-256-GCM")
                            .font(.scaled(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.scaled(size: 15))
                        .foregroundColor(Color(nsColor: .systemGreen))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .accessibilityElement(children: .contain)
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    @ViewBuilder
    private func sidebarButton(tab: NavigationTab, badge: String?) -> some View {
        let isSelected = store.selectedTab == tab
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.selectedTab = tab
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: tab.iconName)
                    .font(.scaled(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                
                Text(tab.rawValue)
                    .font(.scaled(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
                
                Spacer()
                
                if let b = badge {
                    Text(b)
                        .font(.scaled(size: 11.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            isSelected ? Color.blue.opacity(0.18) : Color.primary.opacity(0.08)
                        )
                        .foregroundColor(
                            isSelected ? .blue : .primary
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.rawValue)\(badge != nil ? ", \(badge!) items" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
