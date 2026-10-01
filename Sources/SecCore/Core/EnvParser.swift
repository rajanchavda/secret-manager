import Foundation

public struct EnvEntry {
    public let key: String
    public let value: String
}

public final class EnvParser {
    public static let shared = EnvParser()
    
    private init() {}
    
    /// Parses a .env format string, JSON payload, or YAML into a dictionary of key-value pairs
    public func parse(_ content: String) -> [String: String] {
        let cleanContent = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        let trimmed = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        // 2. Multiline .env and KEY=VALUE / YAML parsing
        var result: [String: String] = [:]
        let rawLines = cleanContent.components(separatedBy: .newlines)
        
        var currentKey: String? = nil
        var currentValue: String = ""
        var inQuotes: Character? = nil
        
        for rawLine in rawLines {
            let line = rawLine
            
            // Check if we are continuing a multiline quoted value
            if let quoteChar = inQuotes {
                currentValue.append("\n")
                if let endQuoteIdx = line.firstIndex(of: quoteChar) {
                    currentValue.append(String(line[..<endQuoteIdx]))
                    if let k = currentKey {
                        result[k] = currentValue
                    }
                    currentKey = nil
                    currentValue = ""
                    inQuotes = nil
                } else {
                    currentValue.append(line)
                }
                continue
            }
            
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            var cleanLine = trimmedLine
            if cleanLine.hasPrefix("export ") {
                cleanLine = String(cleanLine.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            
            // Find delimiter: = (.env) or : (YAML)
            var splitIndex: String.Index? = cleanLine.firstIndex(of: "=")
            if splitIndex == nil, let colonIdx = cleanLine.firstIndex(of: ":") {
                let afterColon = cleanLine.index(after: colonIdx)
                if afterColon == cleanLine.endIndex || cleanLine[afterColon] == " " {
                    splitIndex = colonIdx
                }
            }
            
            guard let delimiterIdx = splitIndex else {
                continue
            }
            
            let key = String(cleanLine[..<delimiterIdx]).trimmingCharacters(in: .whitespaces)
            var rawVal = String(cleanLine[cleanLine.index(after: delimiterIdx)...]).trimmingCharacters(in: .whitespaces)
            
            guard !key.isEmpty else { continue }
            
            // Handle quotes and inline comments
            if let firstChar = rawVal.first, (firstChar == "\"" || firstChar == "'") {
                let quoteChar = firstChar
                let afterFirst = rawVal.index(after: rawVal.startIndex)
                let remainder = rawVal[afterFirst...]
                if let closingIdx = remainder.lastIndex(of: quoteChar) {
                    // Closed on same line
                    var unquoted = String(remainder[..<closingIdx])
                    if quoteChar == "\"" {
                        unquoted = unquoted.replacingOccurrences(of: "\\n", with: "\n")
                    }
                    result[key] = unquoted
                } else {
                    // Multiline quote started
                    currentKey = key
                    currentValue = String(remainder)
                    inQuotes = quoteChar
                }
            } else {
                // Unquoted value: strip inline comments (e.g. `PORT=3000 # web port`)
                if let commentIdx = rawVal.range(of: " #")?.lowerBound ?? rawVal.range(of: "\t#")?.lowerBound {
                    rawVal = String(rawVal[..<commentIdx]).trimmingCharacters(in: .whitespaces)
                }
                result[key] = rawVal
            }
        }
        
        if let k = currentKey {
            result[k] = currentValue
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
    /// Supports .env files, JSON files, YAML files, and arbitrary secret files (keys, certs, raw text).
    public func generateDummyTemplate(from originalContent: String, fileName: String = ".env") -> String {
        let cleanContent = originalContent.replacingOccurrences(of: "\u{FEFF}", with: "")
        let trimmed = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        // 2. YAML Support (.yaml or .yml files)
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ext == "yaml" || ext == "yml" {
            var outputLines: [String] = []
            outputLines.append("# ====================================================================")
            outputLines.append("# 🔒 PROTECTED BY sec (Touch ID Secret Vault)")
            outputLines.append("# Real secrets are encrypted in \(fileName).vault")
            outputLines.append("# Edit secrets: sec edit \(fileName)")
            outputLines.append("# ====================================================================")
            
            let lines = cleanContent.components(separatedBy: .newlines)
            for rawLine in lines {
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                    outputLines.append(rawLine)
                    continue
                }
                if let colonIdx = rawLine.firstIndex(of: ":") {
                    let key = String(rawLine[..<colonIdx])
                    let remainder = String(rawLine[rawLine.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    if remainder.isEmpty {
                        // Grouping / object key
                        outputLines.append(rawLine)
                    } else {
                        // Scalar value
                        let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
                        let cleanKey = key.trimmingCharacters(in: .whitespaces)
                        outputLines.append("\(leadingSpaces)\(cleanKey): \"locked_by_sec\"")
                    }
                } else {
                    outputLines.append(rawLine)
                }
            }
            return outputLines.joined(separator: "\n")
        }
        
        // 3. .env / KEY=VALUE Support
        let parsed = parse(originalContent)
        if !parsed.isEmpty {
            var outputLines: [String] = []
            outputLines.append("# ====================================================================")
            outputLines.append("# 🔒 PROTECTED BY sec (Touch ID Secret Vault)")
            outputLines.append("# Real secrets are encrypted in \(fileName).vault")
            outputLines.append("# Run commands: sec npm run dev   |   Edit secrets: sec edit \(fileName)")
            outputLines.append("# ====================================================================")
            outputLines.append("")
            
            let lines = cleanContent.components(separatedBy: .newlines)
            var skippingMultiline = false
            for rawLine in lines {
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
                if skippingMultiline {
                    if trimmedLine.hasSuffix("\"") || trimmedLine.hasSuffix("'") {
                        skippingMultiline = false
                    }
                    continue
                }
                
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
                    let val = String(cleanLine[cleanLine.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                    
                    if (val.hasPrefix("\"") && !val.dropFirst().contains("\"")) ||
                       (val.hasPrefix("'") && !val.dropFirst().contains("'")) {
                        skippingMultiline = true
                    }
                    outputLines.append("\(linePrefix)\(key)=locked_by_sec")
                } else {
                    outputLines.append("# [secret content locked by sec]")
                }
            }
            return outputLines.joined(separator: "\n")
        }
        
        // 4. Arbitrary File Support (e.g. certificates, private keys, SSH keys, raw tokens, etc.)
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
