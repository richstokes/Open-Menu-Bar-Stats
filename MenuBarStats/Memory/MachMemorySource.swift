import Darwin.Mach
import Foundation

protocol MemoryReading {
    func read(at timestamp: Date) throws -> MemorySnapshot
}

enum MachMemorySourceError: LocalizedError {
    case hostStatistics(kern_return_t)
    case hostPageSize(kern_return_t)
    case invalidPhysicalMemory

    var errorDescription: String? {
        switch self {
        case .hostStatistics(let code):
            "Unable to read memory counters (Mach error \(code))."
        case .hostPageSize(let code):
            "Unable to read the memory page size (Mach error \(code))."
        case .invalidPhysicalMemory:
            "macOS returned invalid physical-memory data."
        }
    }
}

struct MachMemorySource: MemoryReading {
    func read(at timestamp: Date = Date()) throws -> MemorySnapshot {
        let host = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, host)
        }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let statisticsResult = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard statisticsResult == KERN_SUCCESS else {
            throw MachMemorySourceError.hostStatistics(statisticsResult)
        }

        var pageSize: vm_size_t = 0
        let pageSizeResult = host_page_size(host, &pageSize)
        guard pageSizeResult == KERN_SUCCESS else {
            throw MachMemorySourceError.hostPageSize(pageSizeResult)
        }

        guard let snapshot = MemoryUsageCalculator.makeSnapshot(
            activePages: UInt64(statistics.active_count),
            wiredPages: UInt64(statistics.wire_count),
            compressedPages: UInt64(statistics.compressor_page_count),
            pageSize: UInt64(pageSize),
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            timestamp: timestamp
        ) else {
            throw MachMemorySourceError.invalidPhysicalMemory
        }

        return snapshot
    }
}
