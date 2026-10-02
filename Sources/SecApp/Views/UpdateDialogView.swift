import SwiftUI
import AppKit

public struct UpdateDialogView: View {
    @ObservedObject var updater: UpdateChecker
    @Environment(\.dismiss) private var dismiss
    
    @State private var copiedBrewCommand: Bool = false
    
    public init(updater: UpdateChecker) {
        self.updater = updater
    }
    
    public var body: some View {
        VStack(spacing: 18) {
            // Header with App Icon & Version Badge
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.scaled(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Version Available!")
                        .font(.scaled(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        Text("Installed: \(updater.currentVersion)")
                            .font(.scaled(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "arrow.right")
                            .font(.scaled(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(updater.latestRelease?.tagName ?? "Latest")
                            .font(.scaled(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
            }
            .padding(.top, 4)
            
            // Release Notes Card
            VStack(alignment: .leading, spacing: 8) {
                Text("Release Notes")
                    .font(.scaled(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text(cleanReleaseNotes(updater.latestRelease?.body))
                        .font(.scaled(size: 12, design: .default))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 140)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            
            // Homebrew Shortcut Notification if applicable
            if updater.isInstalledViaHomebrew {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.orange)
                        .font(.scaled(size: 13))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Homebrew Installation Detected")
                            .font(.scaled(size: 11.5, weight: .semibold))
                        Text("Run: brew upgrade secret-manager")
                            .font(.scaled(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew upgrade secret-manager", forType: .string)
                        copiedBrewCommand = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedBrewCommand = false
                        }
                    }) {
                        Text(copiedBrewCommand ? "Copied!" : "Copy")
                            .font(.scaled(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    if let releaseUrl = URL(string: updater.latestRelease?.htmlUrl ?? "https://github.com/\(updater.repoOwner)/\(updater.repoName)/releases") {
                        NSWorkspace.shared.open(releaseUrl)
                    }
                }) {
                    Text("View on GitHub")
                        .font(.scaled(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Later") {
                    updater.showUpdateSheet = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: {
                    if let dmgURL = updater.dmgDownloadURL {
                        NSWorkspace.shared.open(dmgURL)
                    } else if let releaseUrl = URL(string: updater.latestRelease?.htmlUrl ?? "") {
                        NSWorkspace.shared.open(releaseUrl)
                    }
                    updater.showUpdateSheet = false
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download DMG")
                            .font(.scaled(size: 12.5, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 480)
    }
    
    private func cleanReleaseNotes(_ body: String?) -> String {
        guard let body = body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No detailed release notes provided for this version."
        }
        return body
    }
}
