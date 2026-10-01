import SwiftUI

public struct RunnerStudioView: View {
    @ObservedObject var store: SecAppStore
    
    let presets = [
        "npm run dev",
        "pnpm dev",
        "yarn dev",
        "cargo run",
        "python app.py",
        "docker compose up"
    ]
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Configuration Banner
            VStack(spacing: 12) {
                // Row 1: Target Project & Presets
                HStack(spacing: 12) {
                    // Project Picker
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.scaled(size: 12))
                            .foregroundColor(.blue)
                        
                        Text("Project:")
                            .font(.scaled(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $store.runnerSelectedVault) {
                            ForEach(store.vaults) { vault in
                                Text(vault.projectName).tag(Optional(vault))
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 140)
                    }
                    
                    Spacer()
                    
                    // Presets
                    HStack(spacing: 5) {
                        Text("Presets:")
                            .font(.scaled(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        ForEach(presets, id: \.self) { preset in
                            Button(action: {
                                store.runnerCommand = preset
                            }) {
                                Text(preset)
                                    .font(.scaled(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(store.runnerCommand == preset ? Color.blue.opacity(0.15) : Color.primary.opacity(0.05))
                                    .foregroundColor(store.runnerCommand == preset ? .blue : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help("Set command to '\(preset)'")
                        }
                    }
                }
                
                // Row 2: Command Input + Action Buttons
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text("$")
                            .font(.scaled(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        TextField("Command to execute (e.g. npm run dev)", text: $store.runnerCommand)
                            .textFieldStyle(.plain)
                            .font(.scaled(size: 12, design: .monospaced))
                            .disabled(store.isProcessRunning)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    if store.isProcessRunning {
                        Button(action: {
                            store.stopRunnerProcess()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                    .font(.scaled(size: 10))
                                Text("Stop Process")
                                    .font(.scaled(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("Stop running process and revoke injected memory")
                    } else {
                        Button(action: {
                            store.startRunnerProcess()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.scaled(size: 10))
                                Text("Run with Secrets")
                                    .font(.scaled(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(color: Color.green.opacity(0.25), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .help("Inject decrypted secrets into process RAM and execute command")
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider().opacity(0.4)
            
            // Status Strip
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.isProcessRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(store.isProcessRunning ? "RUNNING" : "IDLE")
                        .font(.scaled(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(store.isProcessRunning ? .green : .secondary)
                }
                
                if let pid = store.runningPID {
                    Text("PID: \(pid)")
                        .font(.scaled(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "memorychip.fill")
                        .font(.scaled(size: 10))
                    Text("In-Memory Injection Active • Plaintext never on disk • Hidden from ps -E")
                        .font(.scaled(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    store.clearRunnerLogs()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.scaled(size: 9))
                        Text("Clear Logs")
                            .font(.scaled(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear runner terminal output")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider().opacity(0.4)
            
            // Live Terminal Console Output
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if store.runnerLogs.isEmpty {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "terminal")
                                    .font(.scaled(size: 28))
                                    .foregroundColor(.secondary.opacity(0.3))
                                Text("Select a project and click 'Run with Secrets' to launch dev server.")
                                    .font(.scaled(size: 12))
                                    .foregroundColor(.secondary.opacity(0.7))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                        } else {
                            ForEach(store.runnerLogs) { entry in
                                Text(entry.text)
                                    .font(.scaled(size: 11, design: .monospaced))
                                    .foregroundColor(entry.isError ? Color.red.opacity(0.9) : Color.primary)
                                    .textSelection(.enabled)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: store.runnerLogs.count) { _, _ in
                    if let last = store.runnerLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
