import SwiftUI
import UniformTypeIdentifiers

public struct DropZoneView: View {
    @ObservedObject var store: SecAppStore
    @State private var isTargeted: Bool = false
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                )
                .foregroundColor(isTargeted ? Color.blue : Color.secondary.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.blue.opacity(0.1) : Color.primary.opacity(0.03))
                )
            
            HStack(spacing: 8) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.circle")
                    .font(.scaled(size: 13))
                    .foregroundColor(isTargeted ? .blue : .secondary)
                    .accessibilityHidden(true)
                
                Text(isTargeted ? "Release to Protect with Touch ID" : "Drop file or folder here to protect with Touch ID")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundColor(isTargeted ? .blue : .secondary)
            }
            .padding(.vertical, 8)
        }
        .frame(height: 38)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop zone: Drop file or folder here to protect with Touch ID")
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    self.store.handleIncomingFile(url: url)
                }
            }
            return true
        }
    }
}
