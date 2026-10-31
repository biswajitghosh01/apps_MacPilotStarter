import Foundation

struct SystemInfoService {
    func snapshot() -> SystemSnapshot {
        let fileSystem = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = (fileSystem?[.systemSize] as? NSNumber)?.int64Value
        let free = (fileSystem?[.systemFreeSize] as? NSNumber)?.int64Value

        return SystemSnapshot(
            computerName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            totalDiskBytes: total,
            freeDiskBytes: free
        )
    }
}
