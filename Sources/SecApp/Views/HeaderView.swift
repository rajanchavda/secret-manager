import SwiftUI

public struct HeaderView: View {
    @ObservedObject var store: SecAppStore
    
    public init(store: SecAppStore) {
        self.store = store
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Brand Icon + Name
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.85), Color.teal.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 1)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.scaled(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                .accessibilityHidden(true)
                
                Text("Secret Manager")
                    .font(.scaled(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("PRO")
                    .font(.scaled(size: 11, weight: .black, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            Spacer()
            
            // Global Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(store.globalShieldActive ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                    .frame(width: 8, height: 8)
                
                Text(store.statusBadgeText)
                    .font(.scaled(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(store.statusBadgeText)")
            
            // Quick Timer Menu Pill
            Menu {
                Section("Auto-Lock Duration") {
                    Button(action: { store.selectGracePeriod(.strict) }) {
                        Label("Strict Mode", systemImage: store.selectedGraceOption == .strict ? "checkmark" : "hand.raised.fill")
                    }
                    Button(action: { store.selectGracePeriod(.m15) }) {
                        Label("15 Minutes", systemImage: store.selectedGraceOption == .m15 ? "checkmark" : "timer")
                    }
                    Button(action: { store.selectGracePeriod(.m30) }) {
                        Label("30 Minutes", systemImage: store.selectedGraceOption == .m30 ? "checkmark" : "timer")
                    }
                    Button(action: { store.selectGracePeriod(.h1) }) {
                        Label("1 Hour", systemImage: store.selectedGraceOption == .h1 ? "checkmark" : "timer")
                    }
                    Button(action: { store.selectGracePeriod(.untilSleep) }) {
                        Label("Until Sleep", systemImage: store.selectedGraceOption == .untilSleep ? "checkmark" : "moon.zzz.fill")
                    }
                }
                
                Section("Extend Unlocked Time") {
                    Button(action: { store.extendGracePeriod(minutes: 5) }) {
                        Label("+5 Minutes", systemImage: "plus.circle")
                    }
                    Button(action: { store.extendGracePeriod(minutes: 15) }) {
                        Label("+15 Minutes", systemImage: "plus.circle.fill")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.isGraceActive ? "timer" : "hand.raised.fill")
                        .font(.scaled(size: 11))
                        .foregroundColor(store.isGraceActive ? Color(nsColor: .systemOrange) : .secondary)
                    
                    Text(store.isGraceActive ? store.formattedRemainingTime : (store.selectedGraceOption == .strict ? "Strict" : "Locked"))
                        .font(.scaled(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(store.isGraceActive ? Color(nsColor: .systemOrange) : .primary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(store.isGraceActive ? Color.orange.opacity(0.14) : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(store.isGraceActive ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .help("Change auto-lock timer or extend session")
            
            // Panic Lock Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    store.lockAll()
                }
            }) {
                Image(systemName: "lock.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundColor(store.isGraceActive ? Color(nsColor: .systemOrange) : .secondary)
                    .frame(width: 30, height: 30)
                    .background(store.isGraceActive ? Color.orange.opacity(0.15) : Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Panic Lock: Revoke all active sessions and zeroize memory")
            .accessibilityLabel("Panic lock all vaults")
            
            // Settings Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.showSettings.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundColor(store.showSettings ? .blue : .secondary)
                    .frame(width: 30, height: 30)
                    .background(store.showSettings ? Color.blue.opacity(0.15) : Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Preferences & Options")
            .accessibilityLabel("Preferences and options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
