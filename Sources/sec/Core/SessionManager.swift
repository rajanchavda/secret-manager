import Foundation
import Darwin

public final class SessionManager {
    public static let shared = SessionManager()
    
    private let sessionDurationSeconds: Double = 15 * 60 // 15 minutes
    
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
        ensureSecDirectory()
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
        guard let data = try? Data(contentsOf: sessionFileURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return false
        }
        
        let now = Date().timeIntervalSince1970
        let currentBootTime = getSystemBootTime()
        
        // Ensure not expired and boot time matches
        if now < session.expiresAt && session.bootTime == currentBootTime {
            return true
        } else {
            clearSession()
            return false
        }
    }
    
    /// Starts or refreshes an active 15-minute session
    public func startSession() {
        ensureSecDirectory()
        let now = Date().timeIntervalSince1970
        let session = SessionData(
            sessionId: UUID().uuidString,
            createdAt: now,
            expiresAt: now + sessionDurationSeconds,
            bootTime: getSystemBootTime()
        )
        
        if let encoded = try? JSONEncoder().encode(session) {
            try? encoded.write(to: sessionFileURL, options: .atomic)
            // Set 0600 permissions
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFileURL.path)
        }
    }
    
    /// Clears the session immediately
    public func clearSession() {
        try? FileManager.default.removeItem(at: sessionFileURL)
    }
    
    /// Returns human-readable remaining time if session is active
    public func remainingTimeDescription() -> String? {
        guard let data = try? Data(contentsOf: sessionFileURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return nil
        }
        
        let now = Date().timeIntervalSince1970
        let diff = session.expiresAt - now
        guard diff > 0 else { return nil }
        
        let mins = Int(diff) / 60
        let secs = Int(diff) % 60
        return "\(mins)m \(secs)s"
    }
}
