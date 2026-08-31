import Darwin.Mach
import Foundation

protocol MemoryReading: Sendable {
    func read(at timestamp: Date) throws -> MemorySnapshot
}

actor MemorySampler {
    private let source: any MemoryReading

    init(source: any MemoryReading) {
        self.source = source
    }

    func sample(at timestamp: Date) throws -> MemorySnapshot {
        try source.read(at: timestamp)
    }
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
    private let pageSize: UInt64
    private let pageSizeResult: kern_return_t
    private let totalBytes: UInt64

    init() {
        let host = mach_host_self()
        defer {
            unsafe mach_port_deallocate(mach_task_self_, host)
        }

        var pageSize: vm_size_t = 0
        pageSizeResult = unsafe host_page_size(host, &pageSize)
        self.pageSize = UInt64(pageSize)
        totalBytes = ProcessInfo.processInfo.physicalMemory
    }

    func read(at timestamp: Date = Date()) throws -> MemorySnapshot {
        guard pageSizeResult == KERN_SUCCESS else {
            throw MachMemorySourceError.hostPageSize(pageSizeResult)
        }

        let host = mach_host_self()
        defer {
            unsafe mach_port_deallocate(mach_task_self_, host)
        }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let statisticsResult = unsafe withUnsafeMutablePointer(to: &statistics) { pointer in
            unsafe pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                reboundPointer in
                unsafe host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard statisticsResult == KERN_SUCCESS else {
            throw MachMemorySourceError.hostStatistics(statisticsResult)
        }

        guard let snapshot = MemoryUsageCalculator.makeSnapshot(
            internalPages: UInt64(statistics.internal_page_count),
            purgeablePages: UInt64(statistics.purgeable_count),
            wiredPages: UInt64(statistics.wire_count),
            compressedPages: UInt64(statistics.compressor_page_count),
            pageSize: pageSize,
            totalBytes: totalBytes,
            timestamp: timestamp
        ) else {
            throw MachMemorySourceError.invalidPhysicalMemory
        }

        return snapshot
    }
}
