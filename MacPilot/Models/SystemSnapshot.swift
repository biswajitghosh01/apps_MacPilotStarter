import Foundation

struct SystemSnapshot {
    let computerName: String
    let operatingSystem: String
    let processorCount: Int
    let physicalMemoryBytes: UInt64
    let totalDiskBytes: Int64?
    let freeDiskBytes: Int64?

    var usedDiskBytes: Int64? {
        guard let totalDiskBytes, let freeDiskBytes else { return nil }
        return max(0, totalDiskBytes - freeDiskBytes)
    }

    var diskUsageFraction: Double? {
        guard let totalDiskBytes, let usedDiskBytes, totalDiskBytes > 0 else { return nil }
        return min(1, max(0, Double(usedDiskBytes) / Double(totalDiskBytes)))
    }

    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
