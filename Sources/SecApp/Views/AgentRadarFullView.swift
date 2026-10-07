import SwiftUI

public struct AgentRadarFullView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity Log")
                        .font(.scaled(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("What Secret Manager did with your vaults, and changes to vault files on disk")
                        .font(.scaled(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    store.clearRadarEvents()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.scaled(size: 12))
                        Text("Clear")
                            .font(.scaled(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 30)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Clear all activity events from log")
                .accessibilityLabel("Clear activity log")
            }
            .padding(18)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider().opacity(0.5)
            
            // Events List
            if store.radarEvents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.scaled(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                    Text("No Activity Recorded Yet")
                        .font(.scaled(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Locks, Touch ID unlocks, edits, dev-server runs and vault file changes appear here. macOS does not report file reads, so reads by other tools are not shown.")
                        .font(.scaled(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.radarEvents) { event in
                            RadarEventRowView(event: event)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Radar Event Row View
private struct RadarEventRowView: View {
    let event: RadarEvent
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(event.severity.color.opacity(0.14))
                    .frame(width: 36, height: 36)
                
                Image(systemName: event.agentIcon)
                    .font(.scaled(size: 15))
                    .foregroundColor(event.severity.color)
            }
            .accessibilityHidden(true)
            
            // Text Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(event.agentName)
                        .font(.scaled(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .font(.scaled(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(event.action)
                        .font(.scaled(size: 13))
                        .foregroundColor(.primary)
                }
                
                Text(event.detail)
                    .font(.scaled(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Relative Timestamp
            Text(event.relativeTime)
                .font(.scaled(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .background(isHovered ? Color.blue.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.agentName): \(event.action), \(event.detail), \(event.relativeTime)")
    }
}
