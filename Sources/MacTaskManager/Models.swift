import Foundation
import AppKit

// MARK: - Navigation

enum AppSection: String, CaseIterable, Identifiable {
    case overview    = "Overview"
    case processes   = "Processes"
    case performance = "Performance"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .overview:    return "square.grid.2x2.fill"
        case .processes:   return "list.bullet.rectangle"
        case .performance: return "chart.xyaxis.line"
        }
    }
}

// MARK: - Performance Metric

enum PerformanceMetric: String, CaseIterable, Identifiable {
    case cpu     = "CPU"
    case memory  = "Memory"
    case network = "Network"
    case disk    = "Disk"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .cpu:     return "cpu"
        case .memory:  return "memorychip"
        case .network: return "network"
        case .disk:    return "internaldrive"
        }
    }
}

// MARK: - Appearance

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system = "System"
    case dark   = "Dark"
    case light  = "Light"

    var id: String { rawValue }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark:   return NSAppearance(named: .darkAqua)
        case .light:  return NSAppearance(named: .aqua)
        }
    }
}

// MARK: - Process Row

struct ProcessRow: Identifiable, Equatable {
    let pid: Int32
    var name: String
    var bundleIdentifier: String?
    var icon: NSImage?
    var cpuPercent: Double     // 0..n*100 (multi-core)
    var memoryBytes: Int64
    var networkBytesIn: Int64
    var networkBytesOut: Int64
    var threadCount: Int32
    var isApp: Bool

    var id: Int32 { pid }

    static func == (lhs: ProcessRow, rhs: ProcessRow) -> Bool { lhs.pid == rhs.pid }
}

// MARK: - Performance Snapshot

struct PerformanceSnapshot {
    var cpuUsage: Double          // 0–100
    var cpuUserPercent: Double
    var cpuSystemPercent: Double
    var cpuIdlePercent: Double

    var memUsed: Int64
    var memAvailable: Int64
    var memWired: Int64
    var memCompressed: Int64
    var memTotal: Int64

    var swapUsed: Int64
    var swapTotal: Int64

    var netBytesIn: Int64         // bytes/sec
    var netBytesOut: Int64

    var diskReadBytes: Int64      // bytes/sec
    var diskWriteBytes: Int64

    static let zero = PerformanceSnapshot(
        cpuUsage: 0, cpuUserPercent: 0, cpuSystemPercent: 0, cpuIdlePercent: 100,
        memUsed: 0, memAvailable: 0, memWired: 0, memCompressed: 0, memTotal: 0,
        swapUsed: 0, swapTotal: 0,
        netBytesIn: 0, netBytesOut: 0,
        diskReadBytes: 0, diskWriteBytes: 0
    )
}

// MARK: - Sort Key

enum ProcessSortKey: String, CaseIterable, Identifiable {
    case name    = "Name"
    case cpu     = "CPU"
    case memory  = "Memory"
    case network = "Network"
    case threads = "Threads"

    var id: String { rawValue }
}

// MARK: - Force Quit State

enum ForceQuitState {
    case idle
    case confirming(ProcessRow)
    case success(String)
    case failure(String)

    var isConfirming: Bool {
        if case .confirming = self { return true }
        return false
    }
    var noticeMessage: String? {
        switch self {
        case .success(let m): return m
        case .failure(let m): return m
        default: return nil
        }
    }
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
