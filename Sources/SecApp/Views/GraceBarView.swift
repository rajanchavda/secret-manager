import SwiftUI

public struct GraceBarView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // Label + Countdown
            HStack {
                Text("AUTO-LOCK TIMER")
                    .font(.scaled(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                
                Spacer()
                
                if store.isGraceActive && store.remainingGraceSeconds > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.scaled(size: 11, weight: .bold))
                            .foregroundColor(Color(nsColor: .systemOrange))
                        
                        Text(store.formattedRemainingTime)
                            .font(.scaled(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(nsColor: .systemOrange))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    Text(store.selectedGraceOption == .strict ? "Strict Mode" : "Locked (\(store.selectedGraceOption.rawValue))")
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            
            // Segmented Pills
            HStack(spacing: 6) {
                ForEach(GracePeriodOption.allCases) { option in
                    let isSelected = store.selectedGraceOption == option
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            store.selectGracePeriod(option)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: option.iconName)
                                .font(.scaled(size: 11, weight: isSelected ? .bold : .regular))
                            
                            Text(option.rawValue)
                                .font(.scaled(size: 12.5, weight: isSelected ? .semibold : .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.blue)
                                        .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 1)
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                }
                            }
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Set auto-lock duration to \(option.rawValue)")
                    .accessibilityLabel("Set auto-lock duration to \(option.rawValue)")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}
