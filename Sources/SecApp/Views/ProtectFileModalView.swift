import SwiftUI
import AppKit

public struct ProtectFileModalView: View {
    @ObservedObject var store: SecAppStore
    @Binding var isPresented: Bool
    
    @State private var selectedURL: URL? = nil
    @State private var isTargetHovered: Bool = false
    @State private var autoGitIgnore: Bool = true
    @State private var isLocking: Bool = false
    
    public init(store: SecAppStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
    }
    
    public var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.scaled(size: 17))
                        .foregroundColor(.blue)
                }
                .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protect Secret File")
                        .font(.scaled(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Encrypt secrets with Apple Silicon Touch ID and create decoy file on disk")
                        .font(.scaled(size: 12.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(size: 18))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Close dialog")
                .accessibilityLabel("Close dialog")
            }
            
            Divider().opacity(0.5)
            
            // Drop & Select Zone
            VStack(spacing: 12) {
                if let url = selectedURL {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.scaled(size: 24))
                            .foregroundColor(.blue)
                            .accessibilityHidden(true)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent)
                                .font(.scaled(size: 13.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text(url.path)
                                .font(.scaled(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button(action: { selectedURL = nil }) {
                            Image(systemName: "trash")
                                .font(.scaled(size: 13))
                                .foregroundColor(Color(nsColor: .systemRed))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Remove selected file")
                        .accessibilityLabel("Remove selected file")
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.scaled(size: 32))
                            .foregroundColor(.blue.opacity(0.85))
                            .accessibilityHidden(true)
                        
                        Text("Drop your .env or secret file here")
                            .font(.scaled(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("or")
                            .font(.scaled(size: 12))
                            .foregroundColor(.secondary)
                        
                        Button("Choose File...") {
                            chooseFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .font(.scaled(size: 13, weight: .medium))
                        .help("Choose a secret file from Finder")
                        .accessibilityLabel("Choose file from disk")
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(isTargetHovered ? 0.7 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .background(Color.blue.opacity(isTargetHovered ? 0.08 : 0.03))
                    )
                    .onDrop(of: ["public.file-url"], isTargeted: $isTargetHovered) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url = url {
                                DispatchQueue.main.async {
                                    self.selectedURL = url
                                }
                            }
                        }
                        return true
                    }
                }
            }
            
            // Options
            Toggle(isOn: $autoGitIgnore) {
                Text("Automatically add .vault to .gitignore")
                    .font(.scaled(size: 13, weight: .medium))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider().opacity(0.5)
            
            // Footer Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.scaled(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(minHeight: 32)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Cancel and close dialog")
                .accessibilityLabel("Cancel")
                
                Spacer()
                
                Button(action: {
                    guard let url = selectedURL else { return }
                    isLocking = true
                    Task {
                        await store.lockFile(at: url, force: false)
                        isLocking = false
                        isPresented = false
                    }
                }) {
                    HStack(spacing: 6) {
                        if isLocking {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "lock.shield.fill")
                                .font(.scaled(size: 13))
                        }
                        Text("Protect with Touch ID")
                            .font(.scaled(size: 13.5, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 34)
                    .background(selectedURL != nil ? Color.blue : Color.secondary.opacity(0.2))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Encrypt file with Touch ID and replace original with decoy")
                .disabled(selectedURL == nil || isLocking)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Protect selected file with Touch ID")
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            self.selectedURL = url
        }
    }
}
