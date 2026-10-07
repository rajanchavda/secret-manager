import Foundation

public final class Notifier {
    public static let shared = Notifier()
    
    private init() {}
    
    /// osascript arguments for a notification. The text travels as `on run argv` items and is never
    /// spliced into AppleScript source, so file names and error messages cannot inject script.
    func notificationArguments(title: String, message: String) -> [String] {
        return [
            "-e", "on run argv",
            "-e", "display notification (item 1 of argv) with title (item 2 of argv)",
            "-e", "end run",
            "--", message, title
        ]
    }
    
    /// Displays a native macOS notification banner
    public func notify(title: String = "sec", message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = notificationArguments(title: title, message: message)
        try? process.run()
    }
}
