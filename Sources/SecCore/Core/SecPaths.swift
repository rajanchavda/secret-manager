import Foundation

/// Location of sec's data directory (`~/.sec`): master key, vault registry, backups, trash and rescue copies.
enum SecPaths {
    /// Redirects all sec data to another directory. Set only from the test suite via `@testable import`,
    /// so tests never read or write the developer's real `~/.sec`. Never derive this from the
    /// environment: a caller could then point sec at a directory holding a key of its choosing.
    static var overrideForTesting: URL?
    
    static var dataDirectory: URL {
        if let override = overrideForTesting {
            return override
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sec", isDirectory: true)
    }
}
