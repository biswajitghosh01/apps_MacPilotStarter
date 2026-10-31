import Foundation
import Combine
import Darwin
import Mach

struct PerformanceReading {
    let sampledAt: Date
    let oneMinuteLoadAverage: Double?
    let fiveMinuteLoadAverage: Double?
    let fifteenMinuteLoadAverage: Double?
    let memoryUsedBytes: UInt64?
    let memoryAvailableBytes: UInt64?
    let logicalProcessorCount: Int
    let physicalMemoryBytes: UInt64

    var normalizedOneMinuteLoad: Double? {
        guard let oneMinuteLoadAverage, logicalProcessorCount > 0 else { return nil }
        return oneMinuteLoadAverage / Double(logicalProcessorCount)
    }

    static func percent(_ fraction: Double?) -> Double? {
        guard let fraction, fraction.isFinite else { return nil }
        return min(1, max(0, fraction)) * 100
    }
}

/// Read-only system telemetry. Load average is deliberately labelled as load,
/// not CPU utilisation: it includes runnable and uninterruptible tasks.
final class PerformanceMonitor: ObservableObject {
    @Published private(set) var reading: PerformanceReading?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        var loads = [Double](repeating: 0, count: 3)
        let loadCount = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return getloadavg(baseAddress, 3)
        }

        let memory = Self.memorySnapshot()
        reading = PerformanceReading(
            sampledAt: Date(),
            oneMinuteLoadAverage: loadCount > 0 ? loads[0] : nil,
            fiveMinuteLoadAverage: loadCount > 1 ? loads[1] : nil,
            fifteenMinuteLoadAverage: loadCount > 2 ? loads[2] : nil,
            memoryUsedBytes: memory.used,
            memoryAvailableBytes: memory.available,
            logicalProcessorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    private static func memorySnapshot() -> (used: UInt64?, available: UInt64?) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (nil, nil) }

        let pageSize = UInt64(vm_page_size)
        let active = UInt64(statistics.active_count)
        let inactive = UInt64(statistics.inactive_count)
        let wired = UInt64(statistics.wire_count)
        let compressed = UInt64(statistics.compressor_page_count)
        let free = UInt64(statistics.free_count)

        let usedPages = active.addingReportingOverflow(inactive)
        let usedWithWired = usedPages.partialValue.addingReportingOverflow(wired)
        let usedWithCompressed = usedWithWired.partialValue.addingReportingOverflow(compressed)
        guard !usedPages.overflow, !usedWithWired.overflow, !usedWithCompressed.overflow else {
            return (nil, nil)
        }

        return (
            usedWithCompressed.partialValue.multipliedReportingOverflow(by: pageSize).overflow
                ? nil : usedWithCompressed.partialValue * pageSize,
            free.multipliedReportingOverflow(by: pageSize).overflow ? nil : free * pageSize
        )
    }
}
