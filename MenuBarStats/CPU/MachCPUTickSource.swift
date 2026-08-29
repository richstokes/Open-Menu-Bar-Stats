import Darwin.Mach
import Foundation

enum MachCPUTickSourceError: LocalizedError {
    case hostProcessorInfo(kern_return_t)
    case missingProcessorData
    case malformedProcessorData(expectedAtLeast: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .hostProcessorInfo(let code):
            "Unable to read CPU counters (Mach error \(code))."
        case .missingProcessorData:
            "macOS returned no CPU counter data."
        case .malformedProcessorData(let expected, let actual):
            "macOS returned incomplete CPU counter data (expected \(expected), received \(actual))."
        }
    }
}

struct MachCPUTickSource {
    func read() throws -> [CPUTicks] {
        let host = mach_host_self()
        defer {
            unsafe mach_port_deallocate(mach_task_self_, host)
        }

        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = unsafe host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS else {
            throw MachCPUTickSourceError.hostProcessorInfo(result)
        }

        guard let processorInfo = unsafe processorInfo else {
            throw MachCPUTickSourceError.missingProcessorData
        }

        defer {
            let byteCount = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            unsafe vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                byteCount
            )
        }

        let statesPerProcessor = Int(CPU_STATE_MAX)
        let expectedCount = Int(processorCount) * statesPerProcessor
        guard processorCount > 0, Int(processorInfoCount) >= expectedCount else {
            throw MachCPUTickSourceError.malformedProcessorData(
                expectedAtLeast: expectedCount,
                actual: Int(processorInfoCount)
            )
        }

        let buffer = unsafe UnsafeBufferPointer(
            start: processorInfo,
            count: Int(processorInfoCount)
        )

        return (0..<Int(processorCount)).map { processorIndex in
            let offset = processorIndex * statesPerProcessor
            let user = unsafe buffer[offset + Int(CPU_STATE_USER)]
            let system = unsafe buffer[offset + Int(CPU_STATE_SYSTEM)]
            let idle = unsafe buffer[offset + Int(CPU_STATE_IDLE)]
            let nice = unsafe buffer[offset + Int(CPU_STATE_NICE)]

            return CPUTicks(
                user: UInt32(bitPattern: user),
                system: UInt32(bitPattern: system),
                idle: UInt32(bitPattern: idle),
                nice: UInt32(bitPattern: nice)
            )
        }
    }
}
