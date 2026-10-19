import Foundation

public final class FinderInstaller {
    public static let shared = FinderInstaller()
    
    private init() {}
    
    private var servicesDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Services", isDirectory: true)
    }
    
    public func isInstalled() -> Bool {
        let workflow = servicesDirectory.appendingPathComponent("Lock Secrets with Touch ID (sec).workflow")
        return FileManager.default.fileExists(atPath: workflow.path)
    }
    
    public func uninstall() throws {
        let fm = FileManager.default
        let names = [
            "Lock Secrets with Touch ID (sec).workflow",
            "Unlock Secrets with Touch ID (sec).workflow",
            "Edit Secrets with Touch ID (sec).workflow",
            "View Secrets with Touch ID (sec).workflow"
        ]
        for name in names {
            let path = servicesDirectory.appendingPathComponent(name).path
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
        let refreshProcess = Process()
        refreshProcess.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        refreshProcess.arguments = ["-flush"]
        try? refreshProcess.run()
    }
    
    /// Installs macOS Quick Actions into ~/Library/Services for Finder right-click integration.
    /// File names and command output reach AppleScript only as `on run argv` items, and reach Terminal only
    /// through `quoted form of`, so a crafted file name cannot inject AppleScript or shell commands.
    public func install() throws {
        let fm = FileManager.default
        let servicesDir = servicesDirectory
        
        if !fm.fileExists(atPath: servicesDir.path) {
            try fm.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        }
        
        // 1. Install "Lock Secrets with Touch ID"
        try installWorkflow(
            name: "Lock Secrets with Touch ID (sec)",
            script: #"""
            export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
            SEC_BIN="sec"
            if ! command -v sec >/dev/null 2>&1; then
                if [ -f "$HOME/.local/bin/sec" ]; then
                    SEC_BIN="$HOME/.local/bin/sec"
                elif [ -f "/usr/local/bin/sec" ]; then
                    SEC_BIN="/usr/local/bin/sec"
                fi
            fi

            for f in "$@"; do
                is_locked=0
                if [[ "$f" == *.vault ]] || [[ -f "${f}.vault" ]]; then
                    is_locked=1
                elif [ -f "$f" ] && grep -q "PROTECTED BY sec" "$f" 2>/dev/null; then
                    is_locked=1
                fi

                if [ "$is_locked" -eq 1 ]; then
                    base=$(basename "$f")
                    res=$(osascript -e 'on run argv' -e 'try' -e 'button returned of (display dialog ((item 1 of argv) & " is already locked with Touch ID.\n\nWould you like to unlock it and restore plaintext to disk?") with title "sec: Already Locked" buttons {"Cancel", "Unlock Secrets"} default button "Unlock Secrets" with icon caution)' -e 'on error' -e 'return "Cancel"' -e 'end try' -e 'end run' -- "$base" 2>&1)
                    if [ "$res" = "Unlock Secrets" ]; then
                        if ! output=$("$SEC_BIN" unlock --yes "$f" 2>&1); then
                            osascript -e 'on run argv' -e 'display alert "sec Unlock Failed" message (item 1 of argv) as critical' -e 'end run' -- "$output"
                            exit 1
                        fi
                    fi
                    continue
                fi

                if ! output=$("$SEC_BIN" lock "$f" 2>&1); then
                    osascript -e 'on run argv' -e 'display alert "sec Lock Failed" message (item 1 of argv) as critical' -e 'end run' -- "$output"
                    exit 1
                fi
            done
            """#,
            in: servicesDir
        )
        
        // 2. Install "Unlock Secrets with Touch ID"
        try installWorkflow(
            name: "Unlock Secrets with Touch ID (sec)",
            script: #"""
            export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
            SEC_BIN="sec"
            if ! command -v sec >/dev/null 2>&1; then
                if [ -f "$HOME/.local/bin/sec" ]; then
                    SEC_BIN="$HOME/.local/bin/sec"
                elif [ -f "/usr/local/bin/sec" ]; then
                    SEC_BIN="/usr/local/bin/sec"
                fi
            fi

            for f in "$@"; do
                if ! output=$("$SEC_BIN" unlock --yes "$f" 2>&1); then
                    osascript -e 'on run argv' -e 'display alert "sec Unlock Failed" message (item 1 of argv) as critical' -e 'end run' -- "$output"
                    exit 1
                fi
            done
            """#,
            in: servicesDir
        )
        
        // 3. Install "Edit Secrets with Touch ID"
        try installWorkflow(
            name: "Edit Secrets with Touch ID (sec)",
            script: #"""
            export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
            SEC_BIN="sec"
            if ! command -v sec >/dev/null 2>&1; then
                if [ -f "$HOME/.local/bin/sec" ]; then
                    SEC_BIN="$HOME/.local/bin/sec"
                elif [ -f "/usr/local/bin/sec" ]; then
                    SEC_BIN="/usr/local/bin/sec"
                fi
            fi

            for f in "$@"; do
                osascript -e 'on run argv' -e 'tell application "Terminal"' -e 'activate' -e 'do script (quoted form of (item 1 of argv)) & " edit " & (quoted form of (item 2 of argv))' -e 'end tell' -e 'end run' -- "$SEC_BIN" "$f"
            done
            """#,
            in: servicesDir
        )
        
        // 4. Install "View Secrets with Touch ID"
        try installWorkflow(
            name: "View Secrets with Touch ID (sec)",
            script: #"""
            export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
            SEC_BIN="sec"
            if ! command -v sec >/dev/null 2>&1; then
                if [ -f "$HOME/.local/bin/sec" ]; then
                    SEC_BIN="$HOME/.local/bin/sec"
                elif [ -f "/usr/local/bin/sec" ]; then
                    SEC_BIN="/usr/local/bin/sec"
                fi
            fi

            for f in "$@"; do
                osascript -e 'on run argv' -e 'tell application "Terminal"' -e 'activate' -e 'do script (quoted form of (item 1 of argv)) & " view " & (quoted form of (item 2 of argv))' -e 'end tell' -e 'end run' -- "$SEC_BIN" "$f"
            done
            """#,
            in: servicesDir
        )
        
        // Flush macOS Services cache
        let refreshProcess = Process()
        refreshProcess.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        refreshProcess.arguments = ["-flush"]
        try? refreshProcess.run()
        refreshProcess.waitUntilExit()
        
        // Touch services dir to signal LaunchServices update
        let touchProcess = Process()
        touchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        touchProcess.arguments = [servicesDir.path]
        try? touchProcess.run()
        touchProcess.waitUntilExit()
        
        // Terminate ServicesUIAgent so it reloads workflow scripts from disk immediately
        let killAgentProcess = Process()
        killAgentProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killAgentProcess.arguments = ["ServicesUIAgent"]
        try? killAgentProcess.run()
        killAgentProcess.waitUntilExit()
    }
    
    private func installWorkflow(name: String, script: String, in servicesDir: URL) throws {
        let fm = FileManager.default
        let workflowURL = servicesDir.appendingPathComponent("\(name).workflow")
        let contentsURL = workflowURL.appendingPathComponent("Contents")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        
        try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        
        // 1. Info.plist with full Finder contextual declaration
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>\(name)</string>
            <key>CFBundleIdentifier</key>
            <string>com.sec.service.\(name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""))</string>
            <key>CFBundleDevelopmentRegion</key>
            <string>en_US</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>\(name)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSRequiredContext</key>
                    <dict>
                        <key>NSApplicationIdentifier</key>
                        <string>com.apple.finder</string>
                    </dict>
                    <key>NSSendFileTypes</key>
                    <array>
                        <string>public.item</string>
                    </array>
                    <key>NSSendTypes</key>
                    <array>
                        <string>public.item</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // 2. document.wflow with full Automator metadata
        let documentWflow = makeDocumentWflow(script: script)
        try documentWflow.write(to: contentsURL.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
        try documentWflow.write(to: resourcesURL.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
    }
    
    private func makeDocumentWflow(script: String) -> String {
        let escapedScript = script
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        
        let actionUUID = UUID().uuidString
        let inputUUID = UUID().uuidString
        let outputUUID = UUID().uuidString
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key>
            <string>523</string>
            <key>AMApplicationVersion</key>
            <string>2.10</string>
            <key>AMDocumentVersion</key>
            <string>2</string>
            <key>actions</key>
            <array>
                <dict>
                    <key>action</key>
                    <dict>
                        <key>AMAccepts</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Optional</key>
                            <true/>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.path</string>
                            </array>
                        </dict>
                        <key>AMActionVersion</key>
                        <string>2.0.3</string>
                        <key>AMParameterProperties</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <dict/>
                            <key>CheckedForUserDefaultShell</key>
                            <dict/>
                            <key>inputMethod</key>
                            <dict/>
                            <key>shell</key>
                            <dict/>
                            <key>source</key>
                            <dict/>
                        </dict>
                        <key>AMProvides</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.cocoa.path</string>
                            </array>
                        </dict>
                        <key>ActionBundlePath</key>
                        <string>/System/Library/Automator/Run Shell Script.action</string>
                        <key>ActionName</key>
                        <string>Run Shell Script</string>
                        <key>ActionParameters</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <string>\(escapedScript)</string>
                            <key>CheckedForUserDefaultShell</key>
                            <true/>
                            <key>inputMethod</key>
                            <integer>1</integer>
                            <key>shell</key>
                            <string>/bin/zsh</string>
                            <key>source</key>
                            <string></string>
                        </dict>
                        <key>BundleIdentifier</key>
                        <string>com.apple.RunShellScript</string>
                        <key>CFBundleVersion</key>
                        <string>2.0.3</string>
                        <key>CanShowSelectedItemsWhenRun</key>
                        <false/>
                        <key>CanShowWhenRun</key>
                        <true/>
                        <key>Category</key>
                        <array>
                            <string>AMCategoryUtilities</string>
                        </array>
                        <key>Class Name</key>
                        <string>RunShellScriptAction</string>
                        <key>InputUUID</key>
                        <string>\(inputUUID)</string>
                        <key>OutputUUID</key>
                        <string>\(outputUUID)</string>
                        <key>UUID</key>
                        <string>\(actionUUID)</string>
                    </dict>
                </dict>
            </array>
            <key>workflowMetaData</key>
            <dict>
                <key>serviceApplicationBundleID</key>
                <string>com.apple.finder</string>
                <key>serviceApplicationPath</key>
                <string>/System/Library/CoreServices/Finder.app</string>
                <key>serviceInputTypeIdentifier</key>
                <string>com.apple.Automator.fileSystemObject</string>
                <key>serviceOutputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>serviceProcessesInput</key>
                <integer>0</integer>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """
    }
}
