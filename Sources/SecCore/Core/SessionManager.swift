import Foundation
import Darwin

public final class SessionManager {
    public static let shared = SessionManager()
    
    /// User-configured session duration (in seconds). Defaults to nil (CLI single-use).
    /// SecApp sets this to the user's chosen auto-lock policy (e.g. 15 minutes).
    public var configuredSessionDuration: Double? = nil
    
    public var sessionDurationSeconds: Double {
        if let custom = configuredSessionDuration {
            return custom
        }
        if let envVal = ProcessInfo.processInfo.environment["SEC_SESSION_TTL_MINUTES"],
           let mins = Double(envVal), mins > 0 {
            return mins * 60
        }
        return 0 // Strict Zero-Cache (Single-Use) by default
    }
    
    public func setSessionDuration(seconds: Double) {
        self.configuredSessionDuration = max(0, seconds)
    }
    
    public func setSessionDuration(minutes: Double) {
        self.configuredSessionDuration = max(0, minutes * 60)
    }
    
    private var secDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".sec", isDirectory: true)
    }
    
    private var sessionFileURL: URL {
        return secDirectory.appendingPathComponent("session.json")
    }
    
    private struct SessionData: Codable {
        let sessionId: String
        let createdAt: Double
        let expiresAt: Double
        let bootTime: Int
    }
    
    private init() {
        // Clear any legacy session file upon initialization if strict zero-cache
        if sessionDurationSeconds == 0 {
            clearSession()
        }
    }
    
    private func ensureSecDirectory() {
        let path = secDirectory.path
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(at: secDirectory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
    }
    
    /// Returns current system boot timestamp to ensure sessions don't survive reboots
    private func getSystemBootTime() -> Int {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        let result = sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Int(bootTime.tv_sec)
    }
    
    /// Checks whether an active unexpired session exists
    public func isSessionActive() -> Bool {
        guard sessionDurationSeconds > 0 else {
            return false // Strict Single-Use
        }
        
        guard let data = try? Data(contentsOf: sessionFileURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return false
        }
        
        let now = Date().timeIntervalSince1970
        let currentBootTime = getSystemBootTime()
        
        if now < session.expiresAt && session.bootTime == currentBootTime {
            return true
        } else {
            clearSession()
            return false
        }
    }
    
    /// Starts or refreshes an active session if TTL > 0
    public func startSession(duration: Double? = nil) {
        let durationToUse = duration ?? sessionDurationSeconds
        guard durationToUse > 0 else {
            clearSession()
            return
        }
        
        ensureSecDirectory()
        let now = Date().timeIntervalSince1970
        let session = SessionData(
            sessionId: UUID().uuidString,
            createdAt: now,
            expiresAt: now + durationToUse,
            bootTime: getSystemBootTime()
        )
        
        if let encoded = try? JSONEncoder().encode(session) {
            try? encoded.write(to: sessionFileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFileURL.path)
        }
    }
    
    /// Extends an active session by additional seconds
    public func extendSession(additionalSeconds: Double) {
        guard sessionDurationSeconds > 0 else { return }
        
        guard let data = try? Data(contentsOf: sessionFileURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            startSession(duration: additionalSeconds)
            return
        }
        
        let now = Date().timeIntervalSince1970
        guard now < session.expiresAt && session.bootTime == getSystemBootTime() else {
            startSession(duration: additionalSeconds)
            return
        }
        
        let updated = SessionData(
            sessionId: session.sessionId,
            createdAt: session.createdAt,
            expiresAt: max(now, session.expiresAt) + additionalSeconds,
            bootTime: session.bootTime
        )
        if let encoded = try? JSONEncoder().encode(updated) {
            try? encoded.write(to: sessionFileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFileURL.path)
        }
    }
    
    /// Clears the session immediately
    public func clearSession() {
        try? FileManager.default.removeItem(at: sessionFileURL)
    }
    
    /// Returns exact remaining seconds if session is active
    public func remainingTimeSeconds() -> Double? {
        guard sessionDurationSeconds > 0 else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: sessionFileURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return nil
        }
        
        let now = Date().timeIntervalSince1970
        let diff = session.expiresAt - now
        guard diff > 0, session.bootTime == getSystemBootTime() else {
            clearSession()
            return nil
        }
        return diff
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
