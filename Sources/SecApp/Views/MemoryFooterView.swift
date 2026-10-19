import SwiftUI

public struct MemoryFooterView: View {
    @ObservedObject var store: SecAppStore
    @State private var showDetails: Bool = false
    @State private var isHovered: Bool = false
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        Button(action: {
            showDetails.toggle()
        }) {
            HStack(spacing: 7) {
                Image(systemName: "memorychip")
                    .font(.scaled(size: 11.5, weight: .semibold))
                    .foregroundColor(store.inRAMSecretsCount > 0 ? Color(nsColor: .systemPurple) : .secondary)
                    .accessibilityHidden(true)
                
                Text("RAM: \(store.formattedMemoryUsage)")
                    .font(.scaled(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.inRAMSecretsCount > 0 ? Color(nsColor: .systemPurple) : Color(nsColor: .systemGreen))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    
                    Text(store.inRAMSecretsSummary)
                        .font(.scaled(size: 10.5, weight: .medium))
                        .foregroundColor(store.inRAMSecretsCount > 0 ? Color(nsColor: .systemPurple) : .secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        store.inRAMSecretsCount > 0 ? Color.purple.opacity(0.3) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            MemoryDetailsPopoverView(store: store, isPresented: $showDetails)
        }
        .help("Live process RAM footprint and in-memory decrypted secret vault status. Click for details.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current memory usage: \(store.formattedMemoryUsage), \(store.inRAMSecretsSummary)")
    }
}

public struct MemoryDetailsPopoverView: View {
    @ObservedObject var store: SecAppStore
    @Binding var isPresented: Bool
    
    public init(store: SecAppStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "memorychip.fill")
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundColor(store.inRAMSecretsCount > 0 ? Color(nsColor: .systemPurple) : Color(nsColor: .systemGreen))
                
                Text("Process RAM & Secret Vault Status")
                    .font(.scaled(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    store.refreshMemoryUsage()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.scaled(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh memory stats")
            }
            
            Divider().opacity(0.5)
            
            // Memory Metrics Grid
            VStack(spacing: 8) {
                memoryMetricRow(
                    label: "Process Footprint (RSS)",
                    value: store.formattedMemoryUsage,
                    detail: "Resident memory active in physical RAM",
                    isHighlight: false
                )
                
                memoryMetricRow(
                    label: "Virtual Address Space",
                    value: store.currentMemoryInfo.formattedVirtual,
                    detail: "Mapped memory and framework allocations",
                    isHighlight: false
                )
                
                memoryMetricRow(
                    label: "Decrypted Secrets in RAM",
                    value: "\(store.inRAMSecretsCount)",
                    detail: store.inRAMSecretsCount > 0 ? "Held exclusively in memory • Plaintext never on disk" : "RAM cleared • Zero credentials in memory",
                    isHighlight: store.inRAMSecretsCount > 0
                )
                
                memoryMetricRow(
                    label: "Active In-RAM Vaults",
                    value: "\(store.inRAMVaultsCount)",
                    detail: store.inRAMVaultsCount > 0 ? "\(store.inRAMVaultsCount) vault session active" : "All vaults locked & secure",
                    isHighlight: store.inRAMVaultsCount > 0
                )
            }
            
            Divider().opacity(0.5)
            
            // Security Guarantee Banner
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.scaled(size: 13))
                    .foregroundColor(Color(nsColor: .systemGreen))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zero-Disk-Plaintext Policy")
                        .font(.scaled(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Disk contains only dummy decoy placeholders.")
                        .font(.scaled(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Quick Action
            if store.inRAMSecretsCount > 0 {
                Button(action: {
                    store.lockAll()
                    isPresented = false
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.scaled(size: 11))
                        Text("Purge In-Memory Secrets (⌘L)")
                            .font(.scaled(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.18))
                    .foregroundColor(Color(nsColor: .systemOrange))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Immediately revoke sessions and drop decrypted secrets held by the app")
            }
        }
        .padding(14)
        .frame(width: 290)
    }
    
    @ViewBuilder
    private func memoryMetricRow(label: String, value: String, detail: String, isHighlight: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.scaled(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.scaled(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(value)
                .font(.scaled(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(isHighlight ? Color(nsColor: .systemPurple) : .primary)
        }
    }
}
