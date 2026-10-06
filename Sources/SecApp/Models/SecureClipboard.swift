import AppKit

/// Copies secrets to the pasteboard without leaving them there indefinitely.
enum SecureClipboard {
    /// Seconds a copied secret stays on the pasteboard before it is cleared
    static let clearDelay: TimeInterval = 30
    
    // nspasteboard.org conventions honoured by clipboard managers: do not record or display this item
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    
    /// Copies a secret for this Mac only (no Universal Clipboard sync), marks it as concealed for
    /// clipboard managers, and clears it after `clearDelay` unless something else was copied since.
    static func copy(_ secret: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(secret, forType: .string)
        pasteboard.setString("", forType: concealedType)
        pasteboard.setString("", forType: transientType)
        
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
