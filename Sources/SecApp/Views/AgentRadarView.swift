import SwiftUI

public struct AgentRadarView: View {
    @ObservedObject var store: SecAppStore
    @State private var isPulsing: Bool = false
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(alignment: .center, spacing: 8) {
                // Pulsing Dot
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(isPulsing ? 0.2 : 0.6))
                        .frame(width: 14, height: 14)
                        .scaleEffect(isPulsing ? 1.4 : 0.9)
                    
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                .accessibilityHidden(true)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                
                Text("ACTIVITY")
                    .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                
                Text("LIVE")
                    .font(.scaled(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .accessibilityHidden(true)
                
                Spacer()
                
                if !store.radarEvents.isEmpty {
                    Button(action: {
                        withAnimation {
                            store.clearRadarEvents()
                        }
                    }) {
                        Text("Clear")
                            .font(.scaled(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear recent activity events")
                    .accessibilityLabel("Clear activity events")
                }
            }
            .padding(.horizontal, 16)
            
            // Events List
            if store.radarEvents.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 5) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.scaled(size: 20))
                            .foregroundColor(.secondary.opacity(0.5))
                            .accessibilityHidden(true)
                        Text("Watching vault folders for changes")
                            .font(.scaled(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.radarEvents.prefix(3)) { event in
                        HStack(alignment: .top, spacing: 9) {
                            // Agent Icon
                            ZStack {
                                Circle()
                                    .fill(event.severity.color.opacity(0.15))
                                    .frame(width: 26, height: 26)
                                
                                Image(systemName: event.agentIcon)
                                    .font(.scaled(size: 12))
                                    .foregroundColor(event.severity.color)
                            }
                            .accessibilityHidden(true)
                            .padding(.top, 1)
                            
                            // Event Details
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(event.agentName)
                                        .font(.scaled(size: 12.5, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text(event.relativeTime)
                                        .font(.scaled(size: 11, weight: .regular))
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(event.action)
                                    .font(.scaled(size: 11.5, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(event.detail)
                                    .font(.scaled(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(event.agentName): \(event.action), \(event.detail), \(event.relativeTime)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
