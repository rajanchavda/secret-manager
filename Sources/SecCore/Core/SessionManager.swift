import Foundation
import LocalAuthentication

/// Biometric grace period, held in memory only. A session lives inside the process that
/// performed Touch ID, so other processes (AI agents, scripts) can neither reuse nor forge it.
/// The authenticated LAContext is passed to the Secure Enclave so it does not prompt twice.
public final class SessionManager {
    public static let shared = SessionManager()

    /// User-configured session duration (in seconds). Defaults to nil (CLI single-use).
    /// SecApp sets this to the user's chosen auto-lock policy (e.g. 15 minutes).
    public var configuredSessionDuration: Double? = nil

    public var sessionDurationSeconds: Double {
        return configuredSessionDuration ?? 0 // Strict Zero-Cache (Single-Use) by default
    }

    public func setSessionDuration(seconds: Double) {
        self.configuredSessionDuration = max(0, seconds)
    }

    public func setSessionDuration(minutes: Double) {
        self.configuredSessionDuration = max(0, minutes * 60)
    }

    private let lock = NSLock()
    private var context: LAContext?
    private var expiresAt: Double?

    /// Context from the most recent successful Touch ID / password prompt (set by BiometricAuth).
    var authContext: LAContext? {
        get { lock.withLock { context } }
        set { lock.withLock { context = newValue } }
    }

    private init() {
        // Older versions kept a forgeable session file on disk; make sure none is left behind.
        let legacyFile = SecPaths.dataDirectory.appendingPathComponent("session.json")
        try? FileManager.default.removeItem(at: legacyFile)
    }

    /// Checks whether an active unexpired session exists
    public func isSessionActive() -> Bool {
        guard sessionDurationSeconds > 0 else {
            return false // Strict Single-Use
        }
        return lock.withLock {
            guard context != nil, let expiry = expiresAt else { return false }
            if Date().timeIntervalSince1970 < expiry { return true }
            context?.invalidate()
            context = nil
            expiresAt = nil
            return false
        }
    }

    /// Starts or refreshes an active session if TTL > 0. Only effective after a successful authentication.
    public func startSession(duration: Double? = nil) {
        let durationToUse = duration ?? sessionDurationSeconds
        lock.withLock {
            expiresAt = durationToUse > 0 ? Date().timeIntervalSince1970 + durationToUse : nil
        }
    }

    /// Extends an active session by additional seconds
    public func extendSession(additionalSeconds: Double) {
        guard sessionDurationSeconds > 0 else { return }
        guard isSessionActive() else {
            startSession(duration: additionalSeconds)
            return
        }
        lock.withLock {
            expiresAt = (expiresAt ?? Date().timeIntervalSince1970) + additionalSeconds
        }
    }

    /// Clears the session immediately
    public func clearSession() {
        lock.withLock {
            context?.invalidate()
            context = nil
            expiresAt = nil
        }
    }

    /// Returns exact remaining seconds if session is active
    public func remainingTimeSeconds() -> Double? {
        guard isSessionActive(), let expiry = lock.withLock({ expiresAt }) else {
            return nil
        }
        let diff = expiry - Date().timeIntervalSince1970
        return diff > 0 ? diff : nil
    }

    /// Returns human-readable remaining time if session is active
    public func remainingTimeDescription() -> String? {
        guard let diff = remainingTimeSeconds() else {
            return nil
        }

        let mins = Int(diff) / 60
        let secs = Int(diff) % 60
        return "\(mins)m \(secs)s"
    }

    public var isZeroCacheMode: Bool {
        return sessionDurationSeconds == 0
    }
}
