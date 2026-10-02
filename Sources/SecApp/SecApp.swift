import SwiftUI
import AppKit
import Combine

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?
    var statusItem: NSStatusItem!
    let store = SecAppStore.shared
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Configure as a regular standalone macOS application (shows in Dock)
        NSApplication.shared.setActivationPolicy(.regular)
        
        // 2. Set beautiful Dock icon matching header (emerald green to teal gradient shield)
        setupDockIcon()
        
        // 3. Build standard macOS main menu (App, Edit for Copy/Paste, Security, Window)
        setupMainMenu()
        
        // 4. Initialize and show the Standalone Main Window
        showMainWindow()
        
        // 5. Setup Menu Bar Status Item as companion
        setupStatusItem()
        
        // 6. Observe store state changes to update menu bar icon dynamically
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
            
        // 7. Check for application updates in background (throttled once daily)
        UpdateChecker.shared.performBackgroundCheckIfStale()
    }
    
    // MARK: - Main Standalone Window
    public func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = MainWindowView(store: store)
            .preferredColorScheme(.light) // Crisp professional white/light theme
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.minSize = NSSize(width: 880, height: 580)
        window.title = "Secret Manager"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: contentView)
        window.setFrameAutosaveName("secret_manager_main_window")
        
        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Menu Bar Companion
    private func setupStatusItem() {
        let posKey = "NSStatusItem Preferred Position secret_manager_status_item"
        let currentPos = UserDefaults.standard.double(forKey: posKey)
        if currentPos < 200.0 {
            UserDefaults.standard.set(450.0, forKey: posKey)
        }
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible secret_manager_status_item")
        UserDefaults.standard.synchronize()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "secret_manager_status_item"
        statusItem.isVisible = true
        
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateStatusButton()
    }
    
    func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let symbolName = store.menuBarIcon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Secret Manager") {
            let configured = baseImage.withSymbolConfiguration(config) ?? baseImage
            configured.isTemplate = true
            button.image = configured
            button.imagePosition = .imageOnly
            button.toolTip = "Secret Manager - \(store.statusBadgeText)"
        }
    }
    
    @objc func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            showMainWindow()
            return
        }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let openItem = NSMenuItem(title: "Open Secret Manager", action: #selector(showMainWindowFromMenu), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
            
            let lockItem = NSMenuItem(title: "Lock All Vaults", action: #selector(triggerLockAll), keyEquivalent: "l")
            lockItem.target = self
            menu.addItem(lockItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Quit Secret Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            showMainWindow()
        }
    }
    
    @objc func checkForUpdatesAction() {
        showMainWindow()
        Task {
            await UpdateChecker.shared.checkForUpdates(userInitiated: true)
        }
    }
    
    @objc func showMainWindowFromMenu() {
        showMainWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in dock/menu bar even if window is closed
        return false
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let firstURL = urls.first else { return }
        showMainWindow()
        store.handleIncomingFile(url: firstURL)
    }
    
    // MARK: - Native macOS Menu Bar
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Secret Manager")
        appMenu.addItem(withTitle: "About Secret Manager", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        
        let updateMenuItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updateMenuItem.target = self
        appMenu.addItem(updateMenuItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Secret Manager", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Secret Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let protectItem = NSMenuItem(title: "Protect File...", action: #selector(triggerProtectFile), keyEquivalent: "n")
        protectItem.target = self
        fileMenu.addItem(protectItem)
        let lockAllItem = NSMenuItem(title: "Lock All Vaults", action: #selector(triggerLockAll), keyEquivalent: "l")
        lockAllItem.target = self
        fileMenu.addItem(lockAllItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // Edit Menu (Crucial for Copy, Cut, Paste, Select All in text fields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // Security & Timers Menu
        let securityMenuItem = NSMenuItem()
        let securityMenu = NSMenu(title: "Security")
        
        let lockItem = NSMenuItem(title: "Lock All Vaults Now", action: #selector(triggerLockAll), keyEquivalent: "l")
        lockItem.target = self
        securityMenu.addItem(lockItem)
        securityMenu.addItem(NSMenuItem.separator())
        
        let strictItem = NSMenuItem(title: "Strict Mode (Lock Immediately)", action: #selector(triggerStrictTimer), keyEquivalent: "0")
        strictItem.keyEquivalentModifierMask = [.command, .shift]
        strictItem.target = self
        securityMenu.addItem(strictItem)
        
        let m15Item = NSMenuItem(title: "Auto-Lock: 15 Minutes", action: #selector(trigger15mTimer), keyEquivalent: "1")
        m15Item.target = self
        securityMenu.addItem(m15Item)
        
        let m30Item = NSMenuItem(title: "Auto-Lock: 30 Minutes", action: #selector(trigger30mTimer), keyEquivalent: "2")
        m30Item.target = self
        securityMenu.addItem(m30Item)
        
        let h1Item = NSMenuItem(title: "Auto-Lock: 1 Hour", action: #selector(trigger1hTimer), keyEquivalent: "3")
        h1Item.target = self
        securityMenu.addItem(h1Item)
        
        let sleepItem = NSMenuItem(title: "Auto-Lock: Until Mac Sleeps", action: #selector(triggerSleepTimer), keyEquivalent: "4")
        sleepItem.target = self
        securityMenu.addItem(sleepItem)
        
        securityMenu.addItem(NSMenuItem.separator())
        let ext5Item = NSMenuItem(title: "Extend Unlocked Time (+5m)", action: #selector(triggerExtend5m), keyEquivalent: "")
        ext5Item.target = self
        securityMenu.addItem(ext5Item)
        
        let ext15Item = NSMenuItem(title: "Extend Unlocked Time (+15m)", action: #selector(triggerExtend15m), keyEquivalent: "")
        ext15Item.target = self
        securityMenu.addItem(ext15Item)
        
        securityMenuItem.submenu = securityMenu
        mainMenu.addItem(securityMenuItem)
        
        // View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let reloadItem = NSMenuItem(title: "Reload Vaults", action: #selector(triggerReloadVaults), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        
        viewMenu.addItem(NSMenuItem.separator())
        
        let zoomInItem = NSMenuItem(title: "Zoom In (Bigger Font)", action: #selector(triggerIncreaseFontSize), keyEquivalent: "+")
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)
        
        let zoomInAltItem = NSMenuItem(title: "Zoom In", action: #selector(triggerIncreaseFontSize), keyEquivalent: "=")
        zoomInAltItem.target = self
        zoomInAltItem.isAlternate = true
        zoomInAltItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomInAltItem)
        
        let zoomOutItem = NSMenuItem(title: "Zoom Out (Smaller Font)", action: #selector(triggerDecreaseFontSize), keyEquivalent: "-")
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)
        
        let resetZoomItem = NSMenuItem(title: "Actual Size (Reset Font)", action: #selector(triggerResetFontSize), keyEquivalent: "0")
        resetZoomItem.target = self
        viewMenu.addItem(resetZoomItem)
        
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    // MARK: - Dock Icon Matching Left Header
    private func setupDockIcon() {
        if let icon = generateDockIcon() {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    
    private func generateDockIcon() -> NSImage? {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        // Draw macOS Squircle with Shadow
        let margin = size * 0.08
        let squircleRect = CGRect(x: margin, y: margin, width: size - (margin * 2), height: size - (margin * 2))
        let cornerRadius = squircleRect.width * 0.225
        let path = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0.10, green: 0.76, blue: 0.50, alpha: 1.0), // #19C280 (green)
            CGColor(red: 0.05, green: 0.58, blue: 0.55, alpha: 1.0)  // #0D948C (teal)
        ] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
                end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
                options: []
            )
        }
        ctx.restoreGState()
        
        // Inner Highlight
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        ctx.setLineWidth(size * 0.015)
        ctx.strokePath()
        ctx.restoreGState()
        
        // Draw Crisp White "lock.shield.fill" Emblem in Center
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .bold)
        if let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
            let symbolImage = NSImage(size: NSSize(width: size, height: size))
            symbolImage.lockFocus()
            NSColor.white.set()
            symbol.draw(at: NSPoint(x: (size - symbol.size.width) / 2.0, y: (size - symbol.size.height) / 2.0 - (size * 0.01)), from: .zero, operation: .sourceOver, fraction: 1.0)
            symbolImage.unlockFocus()
            
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.035, color: CGColor(red: 0, green: 0.25, blue: 0.2, alpha: 0.45))
            symbolImage.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            ctx.restoreGState()
        }
        
        image.unlockFocus()
        return image
    }
    
    @objc private func triggerProtectFile() {
        store.showProtectFileModal = true
    }
    
    @objc private func triggerLockAll() {
        store.lockAll()
    }
    
    @objc private func triggerReloadVaults() {
        store.loadVaultsFromRegistry()
    }
    
    @objc private func triggerStrictTimer() {
        store.selectGracePeriod(.strict)
    }
    
    @objc private func trigger15mTimer() {
        store.selectGracePeriod(.m15)
    }
    
    @objc private func trigger30mTimer() {
        store.selectGracePeriod(.m30)
    }
    
    @objc private func trigger1hTimer() {
        store.selectGracePeriod(.h1)
    }
    
    @objc private func triggerSleepTimer() {
        store.selectGracePeriod(.untilSleep)
    }
    
    @objc private func triggerExtend5m() {
        store.extendGracePeriod(minutes: 5)
    }
    
    @objc private func triggerExtend15m() {
        store.extendGracePeriod(minutes: 15)
    }
    
    @objc private func triggerIncreaseFontSize() {
        store.increaseFontSize()
    }
    
    @objc private func triggerDecreaseFontSize() {
        store.decreaseFontSize()
    }
    
    @objc private func triggerResetFontSize() {
        store.resetFontSize()
    }
}

// Strong global reference to prevent ARC deallocation during runloop
private var strongAppDelegate: AppDelegate?

@main
enum SecAppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        strongAppDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
