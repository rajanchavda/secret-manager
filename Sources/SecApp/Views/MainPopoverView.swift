import SwiftUI

public struct MainPopoverView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header Bar
                HeaderView(store: store)
                
                Divider()
                    .opacity(0.5)
                
                if store.showSettings {
                    SettingsView(store: store)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    VStack(spacing: 12) {
                        // Auto-Lock Timer Selector Bar
                        GraceBarView(store: store)
                            .padding(.top, 8)
                        
                        // Vaults List Section Header + Search
                        HStack {
                            Text("PROTECTED VAULTS")
                                .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .tracking(0.6)
                            
                            Text("(\(store.vaults.count))")
                                .font(.scaled(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Refresh Button
                            Button(action: {
                                withAnimation {
                                    store.loadVaultsFromRegistry()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.scaled(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh registered projects")
                            .accessibilityLabel("Refresh registered vaults")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        
                        // Vaults Scrollable Cards
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 9) {
                                ForEach(store.filteredVaults) { vault in
                                    VaultCardView(vault: vault, store: store)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 2)
                        }
                        .frame(maxHeight: 200)
                        
                        Divider()
                            .opacity(0.4)
                            .padding(.top, 2)
                        
                        // Agent Radar Live Feed
                        AgentRadarView(store: store)
                        
                        // Drop Zone Target
                        DropZoneView(store: store)
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(width: 370)
            .background(.ultraThinMaterial)
            
            // Temporary Toast Status Banner
            if let msg = store.statusMessage {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.scaled(size: 13))
                        .foregroundColor(Color(nsColor: .systemGreen))
                        .accessibilityHidden(true)
                    
                    Text(msg)
                        .font(.scaled(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status notification: \(msg)")
            }
        }
    }
}
