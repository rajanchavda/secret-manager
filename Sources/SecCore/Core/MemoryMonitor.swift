import Foundation
import Darwin
import MachO

public struct ProcessMemoryInfo: Equatable {
    public let residentBytes: UInt64
    public let virtualBytes: UInt64
    
    public init(residentBytes: UInt64 = 0, virtualBytes: UInt64 = 0) {
        self.residentBytes = residentBytes
        self.virtualBytes = virtualBytes
    }
    
    public var formattedResident: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(residentBytes))
    }
    
    public var formattedVirtual: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(virtualBytes))
    }
}

public enum MemoryMonitor {
    /// Queries the Mach kernel for current process resident and virtual memory statistics.
    public static func currentProcessMemory() -> ProcessMemoryInfo {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return ProcessMemoryInfo(
                residentBytes: info.resident_size,
                virtualBytes: info.virtual_size
            )
        }
        
        return ProcessMemoryInfo(residentBytes: 0, virtualBytes: 0)
    }
}
