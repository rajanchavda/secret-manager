import Foundation
import Darwin

/// Describes which processes asked sec to act, so the Touch ID prompt can tell the user
/// whether they are approving their own terminal or a command issued by a tool or AI agent.
/// Process names are informational only: a same-user process can choose its own name.
public enum CallerInfo {
    
    /// Names of the ancestor processes, nearest first (e.g. `["zsh", "node", "Cursor Helper"]`).
    /// Stops at launchd, so an app launched from Finder or the Dock reports no ancestors.
    public static func ancestorNames(maxDepth: Int = 4) -> [String] {
        var names: [String] = []
        var pid = getppid()
        while pid > 1 && names.count < maxDepth {
            guard let name = processName(of: pid) else { break }
            names.append(name)
            guard let parent = parentPID(of: pid), parent != pid else { break }
            pid = parent
        }
        return names
    }
    
    /// Human-readable ancestry for a prompt (e.g. `zsh ← node ← Cursor Helper`), or nil when there is none
    public static func requesterDescription() -> String? {
        let names = ancestorNames()
        return names.isEmpty ? nil : names.joined(separator: " ← ")
    }
    
    /// Appends the requesting process chain to a Touch ID prompt reason
    public static func annotate(reason: String) -> String {
        guard let requester = requesterDescription() else { return reason }
        return "\(reason) (started by: \(requester))"
    }
    
    /// A single-line, length-limited rendering of a command that is safe to show in a prompt
    public static func displayCommand(_ command: [String], limit: Int = 80) -> String {
        let joined = command.joined(separator: " ")
        let singleLine = String(joined.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : Character(scalar)
        })
        if singleLine.count <= limit {
            return singleLine
        }
        return String(singleLine.prefix(limit)) + "…"
    }
    
    static func processName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
        return name.isEmpty ? nil : displayCommand([name], limit: 40)
    }
    
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
