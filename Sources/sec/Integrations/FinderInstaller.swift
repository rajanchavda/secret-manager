import Foundation

public final class FinderInstaller {
    public static let shared = FinderInstaller()
    
    private init() {}
    
    private var servicesDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Services", isDirectory: true)
    }
    
    /// Installs macOS Quick Actions into ~/Library/Services for Finder right-click integration
    public func install() throws {
        let fm = FileManager.default
        let servicesDir = servicesDirectory
        
        if !fm.fileExists(atPath: servicesDir.path) {
            try fm.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        }
        
        // 1. Install "Lock Secrets with Touch ID"
        try installLockWorkflow(in: servicesDir)
        
        // 2. Install "Edit Secrets with Touch ID"
        try installEditWorkflow(in: servicesDir)
        
        // Refresh macOS Services cache
        let refreshProcess = Process()
        refreshProcess.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        refreshProcess.arguments = ["-flush"]
        try? refreshProcess.run()
        refreshProcess.waitUntilExit()
    }
    
    private func installLockWorkflow(in servicesDir: URL) throws {
        let workflowURL = servicesDir.appendingPathComponent("Lock Secrets with Touch ID (sec).workflow")
        let contentsURL = workflowURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>Lock Secrets with Touch ID (sec)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSSendFileTypes</key>
                    <array>
                        <string>public.item</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        let script = """
        export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
        for f in "$@"; do
            sec lock "$f"
        done
        """
        
        let documentWflow = makeDocumentWflow(script: script, title: "Lock Secrets with Touch ID (sec)")
        try documentWflow.write(to: contentsURL.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
    }
    
    private func installEditWorkflow(in servicesDir: URL) throws {
        let workflowURL = servicesDir.appendingPathComponent("Edit Secrets with Touch ID (sec).workflow")
        let contentsURL = workflowURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>Edit Secrets with Touch ID (sec)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSSendFileTypes</key>
                    <array>
                        <string>public.item</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // When triggered from Finder, launch in terminal or preferred editor
        let script = """
        export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
        for f in "$@"; do
            osascript -e "tell application \\"Terminal\\" to do script \\"sec edit '$f'\\""
        done
        """
        
        let documentWflow = makeDocumentWflow(script: script, title: "Edit Secrets with Touch ID (sec)")
        try documentWflow.write(to: contentsURL.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
    }
    
    private func makeDocumentWflow(script: String, title: String) -> String {
        let escapedScript = script
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        
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
                            <key>inputMethod</key>
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
                    </dict>
                </dict>
            </array>
            <key>workflowMetaData</key>
            <dict>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """
    }
}
