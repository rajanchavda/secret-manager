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
    
    private let placeholder = "locked_by_sec"
    private let lockedMarker = "# [secret content locked by sec]"
    
    /// True when a value is a decoy placeholder written by sec
    private func isPlaceholderValue(_ value: String) -> Bool {
        return value == placeholder || value.hasSuffix("_sec_locked")
    }
    
    private func jsonContainsPlaceholder(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            return dict.values.contains(where: { jsonContainsPlaceholder($0) })
        } else if let arr = value as? [Any] {
            return arr.contains(where: { jsonContainsPlaceholder($0) })
        } else if let str = value as? String {
            return isPlaceholderValue(str)
        }
        return false
    }
    
    /// Checks whether any value in the content is exactly a decoy placeholder.
    /// A file that merely mentions the placeholder inside a longer value or a comment does not count.
    public func containsPlaceholderValue(_ content: String) -> Bool {
        let trimmed = content.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
           let data = trimmed.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: data, options: []) {
            return jsonContainsPlaceholder(jsonObj)
        }
        return parse(content).values.contains(where: { isPlaceholderValue($0) })
    }
    
    /// Appends a line unless it would repeat the previous one (keeps the decoy from mirroring the secret's line count)
    private func appendCollapsing(_ line: String, to lines: inout [String]) {
        if lines.last != line {
            lines.append(line)
        }
    }
    
    /// A conventional variable name: letters, digits, `_`, `.`, `-`, not starting with a digit
    private func isSafeEnvKey(_ key: String) -> Bool {
        guard let first = key.first, first.isASCII, first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-") }
    }
    
    /// Heuristic for a bare base64 line such as `c2VjcmV0dG9rZW4=`, which would otherwise be
    /// read as a variable named after the secret with an empty value.
    private func looksLikeEncodedData(key: String, value: String) -> Bool {
        guard value.allSatisfy({ $0 == "=" }) else { return false }
        return key.contains(where: { $0.isUppercase }) && key.contains(where: { $0.isLowercase })
    }
    
    /// Splits `key: value` at the first colon that is followed by whitespace or the end of the line
    private func splitYAMLKey(_ body: Substring) -> (key: String, value: String)? {
        guard let first = body.first, first != "{", first != "[" else { return nil }
        var idx = body.startIndex
        if first == "\"" || first == "'" {
            guard let close = body.dropFirst().firstIndex(of: first) else { return nil }
            idx = body.index(after: close)
        }
        while idx < body.endIndex {
            let next = body.index(after: idx)
            if body[idx] == ":" && (next == body.endIndex || body[next] == " " || body[next] == "\t") {
                let key = body[..<idx].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return nil }
                return (key, body[next...].trimmingCharacters(in: .whitespaces))
            }
            idx = next
        }
        return nil
    }
    
    /// Returns the text to keep after a YAML key when it carries no secret: nothing (a grouping key,
    /// possibly with a trailing comment), a lone anchor, or a lone alias. Returns nil for a scalar value.
    private func yamlStructuralValue(_ value: String) -> String? {
        if value.isEmpty || value.hasPrefix("#") {
            return ""
        }
        var token = value
        if let commentIdx = value.range(of: " #")?.lowerBound {
            token = String(value[..<commentIdx]).trimmingCharacters(in: .whitespaces)
        }
        if let first = token.first, first == "&" || first == "*",
           token.dropFirst().allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
           token.count > 1 {
            return token
        }
        return nil
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
            return placeholder
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
            var openQuote: Character? = nil
            var skipDeeperThan: Int? = nil
            for rawLine in lines {
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
                
                // Continuation of a multi-line quoted scalar
                if let quote = openQuote {
                    if trimmedLine.contains(quote) {
                        openQuote = nil
                    }
                    continue
                }
                
                // Body of a block scalar (| or >) or continuation of a plain multi-line scalar
                let indent = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                if let limit = skipDeeperThan {
                    if trimmedLine.isEmpty || indent > limit {
                        continue
                    }
                    skipDeeperThan = nil
                }
                
                if trimmedLine.isEmpty {
                    appendCollapsing("", to: &outputLines)
                    continue
                }
                // Comments are dropped: they routinely hold old keys and credential notes
                if trimmedLine.hasPrefix("#") {
                    continue
                }
                if trimmedLine == "---" || trimmedLine == "..." {
                    outputLines.append(trimmedLine)
                    continue
                }
                
                // Peel list markers so `- key: value` and `- value` are both masked
                var prefix = String(rawLine.prefix(indent))
                var body = Substring(trimmedLine)
                var keyColumn = indent
                var isListItem = false
                while body == "-" || body.hasPrefix("- ") {
                    isListItem = true
                    let rest = body.dropFirst().drop(while: { $0 == " " })
                    keyColumn += body.count - rest.count
                    prefix += "- "
                    body = rest
                }
                if body.isEmpty || body.hasPrefix("#") {
                    outputLines.append(String(rawLine.prefix(indent)) + prefix.dropFirst(indent).trimmingCharacters(in: .whitespaces))
                    continue
                }
                
                if let (key, value) = splitYAMLKey(body) {
                    if let quote = value.first, (quote == "\"" || quote == "'"), !value.dropFirst().contains(quote) {
                        openQuote = quote
                    }
                    let structural = yamlStructuralValue(value)
                    if let structural = structural {
                        // Grouping / object key (optionally carrying an anchor or alias)
                        outputLines.append("\(prefix)\(key):\(structural.isEmpty ? "" : " \(structural)")")
                    } else {
                        // Scalar value
                        outputLines.append("\(prefix)\(key): \"\(placeholder)\"")
                        skipDeeperThan = keyColumn
                    }
                } else if isListItem {
                    if let quote = body.first, (quote == "\"" || quote == "'"), !body.dropFirst().contains(quote) {
                        openQuote = quote
                    }
                    outputLines.append("\(prefix)\"\(placeholder)\"")
                    skipDeeperThan = indent
                } else {
                    appendCollapsing(lockedMarker, to: &outputLines)
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
            var openQuote: Character? = nil
            for rawLine in lines {
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
                
                // Inside a multi-line quoted value: ends on the same quote that opened it (mirrors parse)
                if let quote = openQuote {
                    if rawLine.contains(quote) {
                        openQuote = nil
                    }
                    continue
                }
                
                if trimmedLine.isEmpty {
                    appendCollapsing("", to: &outputLines)
                    continue
                }
                // Comments are dropped: they routinely hold old keys and credential notes
                if trimmedLine.hasPrefix("#") {
                    continue
                }
                
                var linePrefix = ""
                var cleanLine = trimmedLine
                if cleanLine.hasPrefix("export ") {
                    linePrefix = "export "
                    cleanLine = String(cleanLine.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                }
                
                guard let equalIndex = cleanLine.firstIndex(of: "=") else {
                    appendCollapsing(lockedMarker, to: &outputLines)
                    continue
                }
                
                let key = String(cleanLine[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(cleanLine[cleanLine.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                
                if let quote = val.first, (quote == "\"" || quote == "'"), !val.dropFirst().contains(quote) {
                    openQuote = quote
                }
                
                // Only a plain variable name is safe to echo. Anything else is secret material
                // that happens to contain "=" (base64 padding, PEM bodies, JSON fragments).
                if isSafeEnvKey(key) && !looksLikeEncodedData(key: key, value: val) {
                    outputLines.append("\(linePrefix)\(key)=\(placeholder)")
                } else {
                    appendCollapsing(lockedMarker, to: &outputLines)
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
