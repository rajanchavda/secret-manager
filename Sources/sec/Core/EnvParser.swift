import Foundation

public struct EnvEntry {
    public let key: String
    public let value: String
}

public final class EnvParser {
    public static let shared = EnvParser()
    
    private init() {}
    
    /// Parses a .env format string or JSON payload into a dictionary of key-value pairs
    public func parse(_ content: String) -> [String: String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. JSON Support: extract top-level keys for environment injection
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            var jsonResult: [String: String] = [:]
            for (key, val) in json {
                if let str = val as? String {
                    jsonResult[key] = str
                } else if let num = val as? NSNumber {
                    if CFGetTypeID(num as CFTypeRef) == CFBooleanGetTypeID() {
                        jsonResult[key] = num.boolValue ? "true" : "false"
                    } else {
                        jsonResult[key] = num.stringValue
                    }
                } else if let subData = try? JSONSerialization.data(withJSONObject: val, options: []),
                          let subStr = String(data: subData, encoding: .utf8) {
                    jsonResult[key] = subStr
                }
            }
            if !jsonResult.isEmpty {
                return jsonResult
            }
        }
        
        // 2. Standard .env KEY=VALUE parsing
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
    
    /// Recursively masks all scalar values in a parsed JSON structure
    private func maskJSONValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var maskedDict: [String: Any] = [:]
            for (k, v) in dict {
                maskedDict[k] = maskJSONValue(v)
            }
            return maskedDict
        } else if let arr = value as? [Any] {
            return arr.map { maskJSONValue($0) }
        } else if value is NSNull {
            return NSNull()
        } else if value is Bool {
            return false
        } else {
            return "locked_by_sec"
        }
    }
    
    /// Generates a sanitized dummy placeholder file keeping structure, but replacing all secrets.
    /// Supports .env files, JSON files, and arbitrary secret files (keys, certs, raw text).
    public func generateDummyTemplate(from originalContent: String, fileName: String = ".env") -> String {
        let trimmed = originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. JSON Support (.json files or JSON payloads)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
           let data = trimmed.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: data, options: []) {
            let masked = maskJSONValue(jsonObj)
            if let maskedData = try? JSONSerialization.data(withJSONObject: masked, options: [.prettyPrinted, .sortedKeys]),
               let maskedStr = String(data: maskedData, encoding: .utf8) {
                return maskedStr
            }
        }
        
        // 2. .env / KEY=VALUE Support
        let parsed = parse(originalContent)
        if !parsed.isEmpty {
            var outputLines: [String] = []
            outputLines.append("# ====================================================================")
            outputLines.append("# 🔒 PROTECTED BY sec (Touch ID Secret Vault)")
            outputLines.append("# Real secrets are encrypted in \(fileName).vault")
            outputLines.append("# Run commands: sec npm run dev   |   Edit secrets: sec edit \(fileName)")
            outputLines.append("# ====================================================================")
            outputLines.append("")
            
            let lines = originalContent.components(separatedBy: .newlines)
            for rawLine in lines {
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                    outputLines.append(rawLine)
                    continue
                }
                
                var linePrefix = ""
                var cleanLine = trimmedLine
                if cleanLine.hasPrefix("export ") {
                    linePrefix = "export "
                    cleanLine = String(cleanLine.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                }
                
                if let equalIndex = cleanLine.firstIndex(of: "=") {
                    let key = String(cleanLine[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                    outputLines.append("\(linePrefix)\(key)=locked_by_sec")
                } else {
                    outputLines.append("# [secret content locked by sec]")
                }
            }
            return outputLines.joined(separator: "\n")
        }
        
        // 3. Arbitrary File Support (e.g. certificates, private keys, SSH keys, raw tokens, etc.)
        return """
        # ====================================================================
        # 🔒 PROTECTED BY sec (Touch ID Secret Vault)
        # Plaintext content is shielded from AI agents and background tools.
        # Real secrets are encrypted in \(fileName).vault
        # View or edit: sec edit \(fileName)
        # Unlock to disk: sec unlock \(fileName)
        # ====================================================================
        """
    }
}
