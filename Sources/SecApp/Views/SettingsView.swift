import SwiftUI
import AppKit
import SecCore

public struct SettingsView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.scaled(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        store.showSettings = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close preferences")
            }
            .padding(.bottom, 2)
            
            // System Integrations & App Controls
            VStack(spacing: 8) {
                Button(action: {
                    try? FinderInstaller.shared.install()
                    store.addRadarEvent(
                        agent: "Finder",
                        action: "Installed macOS Quick Actions",
                        detail: "Right-click lock/unlock available in Finder",
                        severity: .success
                    )
                }) {
                    HStack {
                        Image(systemName: "macwindow.on.rectangle")
                            .foregroundColor(.blue)
                        Text("Reinstall Finder Right-Click Actions")
                            .font(.scaled(size: 12.5, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.scaled(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Reinstall macOS Finder right-click Quick Actions")
                .accessibilityLabel("Reinstall Finder Right-Click Actions")
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                            .foregroundColor(Color(nsColor: .systemRed))
                        Text("Quit sec Pro")
                            .font(.scaled(size: 12.5, weight: .medium))
                            .foregroundColor(Color(nsColor: .systemRed))
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Quit sec Pro application")
                .accessibilityLabel("Quit sec Pro application")
            }
        }
        .padding(16)
    }
}
