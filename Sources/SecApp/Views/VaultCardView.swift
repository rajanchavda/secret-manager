import SwiftUI

public struct VaultCardView: View {
    public let vault: VaultItem
    @ObservedObject var store: SecAppStore
    @State private var isHovered: Bool = false
    
    public init(vault: VaultItem, store: SecAppStore) {
        self.vault = vault
        self.store = store
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Top Row: Folder Icon + Project Name + File Count + Status Pill
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.scaled(size: 14))
                    .foregroundColor(.blue)
                
                Text(vault.projectName)
                    .font(.scaled(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // File count badge
                HStack(spacing: 2) {
                    Text("\(vault.files.count)")
                        .font(.scaled(size: 9.5, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 3.5) {
                    Image(systemName: vault.status.iconName)
                        .font(.scaled(size: 8.5))
                    
                    Text(vault.status.rawValue)
                        .font(.scaled(size: 10, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(vault.status.color.opacity(0.14))
                .foregroundColor(vault.status.color)
                .clipShape(Capsule())
            }
            
            // Nested Files (VS Code Tree Style)
            VStack(spacing: 2) {
                ForEach(vault.files) { file in
                    let isSelected = vault.activeFile == file.filename
                    
                    Button(action: {
                        Task {
                            await store.selectActiveFile(file.filename, for: vault)
                        }
                    }) {
                        HStack(spacing: 0) {
                            // Tree indent guides
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(width: 1.5)
                                    .padding(.leading, 8)
                                    .padding(.trailing, 6)
                                
                                Rectangle()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(width: 6, height: 1.5)
                                    .padding(.trailing, 5)
                            }
                            .frame(height: 22)
                            
                            // File row content
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(file.status == .protectedWithDecoy ? Color.green : (file.status == .inRAM ? Color.purple : Color.orange))
                                    .frame(width: 4.5, height: 4.5)
                                
                                Text(file.filename)
                                    .font(.scaled(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                                    .foregroundColor(isSelected ? .blue : .primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if file.keyCount > 0 {
                                    Text("\(file.keyCount) keys")
                                        .font(.scaled(size: 9.5, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(file.status == .protectedWithDecoy ? "Decoy" : (file.status == .inRAM ? "RAM" : "Plain"))
                                    .font(.scaled(size: 9, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(file.status.color.opacity(0.12))
                                    .foregroundColor(file.status.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Select \(file.filename)")
                }
            }
            .padding(.top, 1)
            
            // Path Caption
            Text(vault.abbreviatedPath)
                .font(.scaled(size: 10.5))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 1)
            
            // Bottom Action Row
            HStack(spacing: 8) {
                // Edit Button
                Button(action: {
                    store.editWithExternalEditor(vault: vault)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.scaled(size: 10.5))
                        Text("Edit Secrets")
                            .font(.scaled(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .frame(minHeight: 26)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Open encrypted vault in temporary secure buffer")
                .accessibilityLabel("Edit secrets for \(vault.projectName)")
                
                Spacer()
                
                // Reveal in Finder Button
                Button(action: {
                    store.revealInFinder(vault: vault)
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.scaled(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Reveal folder in Finder")
                .accessibilityLabel("Reveal \(vault.projectName) in Finder")
            }
            .padding(.top, 2)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(cardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var cardFillColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.85 : 0.55)
    }
    
    private var cardStrokeColor: Color {
        isHovered ? Color.blue.opacity(0.35) : Color.primary.opacity(0.08)
    }
}
