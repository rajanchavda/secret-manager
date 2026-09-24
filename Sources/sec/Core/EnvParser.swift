import Foundation

public struct EnvEntry {
    public let key: String
    public let value: String
}

public final class EnvParser {
    public static let shared = EnvParser()
    
    private init() {}
    
    /// Parses a .env format string into a dictionary of key-value pairs
    public func parse(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            
            // Handle optional "export " prefix
            var cleanLine = line
            if cleanLine.hasPrefix("export ") {
                cleanLine = String(cleanLine.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            
            guard let equalIndex = cleanLine.firstIndex(of: "=") else {
                continue
            }
            
            let key = String(cleanLine[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(cleanLine[cleanLine.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
            
            // Remove enclosing quotes if present
            if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2) ||
               (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
                value = String(value.dropFirst().dropLast())
            }
            
            // Handle escaped newlines
            value = value.replacingOccurrences(of: "\\n", with: "\n")
            
            if !key.isEmpty {
                result[key] = value
            }
        }
        
        return result
    }
    
    /// Generates a sanitized dummy .env file keeping keys and structure, but replacing values with dummy placeholders
    public func generateDummyTemplate(from originalContent: String) -> String {
        var outputLines: [String] = []
        
        outputLines.append("# ====================================================================")
        outputLines.append("# 🔒 PROTECTED BY sec (Touch ID Secret Vault)")
        outputLines.append("# Real secrets are encrypted in .env.vault")
        outputLines.append("# Run commands: sec npm run dev   |   Edit secrets: sec edit")
        outputLines.append("# ====================================================================")
        outputLines.append("")
        
        let lines = originalContent.components(separatedBy: .newlines)
        
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Keep empty lines and comments intact
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                outputLines.append(rawLine)
                continue
            }
            
            var linePrefix = ""
            var cleanLine = trimmed
            if cleanLine.hasPrefix("export ") {
                linePrefix = "export "
                cleanLine = String(cleanLine.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            
            if let equalIndex = cleanLine.firstIndex(of: "=") {
                let key = String(cleanLine[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let dummyVal = "locked_by_sec"
                outputLines.append("\(linePrefix)\(key)=\(dummyVal)")
            } else {
                outputLines.append(rawLine)
            }
        }
        
        return outputLines.joined(separator: "\n")
    }
}
