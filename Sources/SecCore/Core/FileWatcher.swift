import Foundation

/// FileWatcher monitors directories for file system changes (e.g. deletions, additions, renames in Finder)
/// using Grand Central Dispatch's DispatchSourceFileSystemObject.
public final class FileWatcher {
    public static let shared = FileWatcher()
    
    private var watchedSources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private let queue = DispatchQueue(label: "com.sec.filewatcher", qos: .utility)
    
    public var onChange: (() -> Void)? = nil
    
    public init() {}
    
    deinit {
        stopAll()
    }
    
    /// Starts watching a list of directory URLs for filesystem events (delete, write, rename, extend)
    public func watchDirectories(_ urls: [URL]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let standardizedPaths = Set(urls.map { $0.standardizedFileURL.path })
            
            // Remove watchers for directories no longer in the list
            for (path, source) in self.watchedSources {
                if !standardizedPaths.contains(path) {
                    source.cancel()
                    self.watchedSources.removeValue(forKey: path)
                    if let fd = self.fileDescriptors.removeValue(forKey: path) {
                        close(fd)
                    }
                }
            }
            
            // Add watchers for new directories
            for path in standardizedPaths {
                if self.watchedSources[path] == nil {
                    self.startWatchingPath(path)
                }
            }
        }
    }
    
    /// Starts watching a specific directory path
    private func startWatchingPath(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            // Debounce or dispatch change event
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        fileDescriptors[path] = fd
        watchedSources[path] = source
        source.resume()
    }
    
    /// Stops all active directory watchers
    public func stopAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            for (_, source) in self.watchedSources {
                source.cancel()
            }
            self.watchedSources.removeAll()
            self.fileDescriptors.removeAll()
        }
    }
}
