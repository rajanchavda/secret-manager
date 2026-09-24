import Foundation

public final class Notifier {
    public static let shared = Notifier()
    
    private init() {}
    
    /// Displays a native macOS notification banner
    public func notify(title: String = "sec", message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
