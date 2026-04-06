import Foundation

// MARK: - Safe numeric helpers

/// Clamps a Double to a finite value; returns `fallback` for NaN/Inf.
func safeDouble(_ value: Double, fallback: Double = 0) -> Double {
    value.isFinite ? value : fallback
}

/// Safe Int64 from Double – avoids undefined behaviour on out-of-range values.
func safeInt64(_ value: Double) -> Int64 {
    let clamped = safeDouble(value)
    if clamped < Double(Int64.min) { return 0 }
    if clamped > Double(Int64.max) { return Int64.max }
    return Int64(clamped)
}

/// Safe positive delta between two UInt64 counters (handles wrap / reset).
func safeDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
    current >= previous ? current - previous : 0
}

// MARK: - Bytes / throughput

func formatBytes(_ bytes: Int64) -> String {
    guard bytes >= 0 else { return "0 B" }
    let b = Double(bytes)
    switch b {
    case ..<1024:           return "\(bytes) B"
    case ..<(1024 * 1024):  return String(format: "%.1f KB", b / 1024)
    case ..<(1024 * 1024 * 1024): return String(format: "%.1f MB", b / (1024 * 1024))
    default:                return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
    }
}

func formatBytesPerSec(_ bytes: Int64) -> String {
    formatBytes(bytes) + "/s"
}

func formatBytesCompact(_ bytes: Int64) -> String {
    guard bytes >= 0 else { return "0 B" }
    let b = Double(bytes)
    if b < 1024 { return "\(bytes) B" }
    if b < 1_048_576 { return String(format: "%.0f KB", b / 1024) }
    if b < 1_073_741_824 { return String(format: "%.1f MB", b / 1_048_576) }
    return String(format: "%.2f GB", b / 1_073_741_824)
}

// MARK: - Percentages

func formatPercent(_ value: Double, decimals: Int = 1) -> String {
    let v = safeDouble(value)
    let clamped = max(0, min(100, v))
    return String(format: "%.\(decimals)f%%", clamped)
}

func formatCPUPercent(_ value: Double) -> String {
    let v = safeDouble(value)
    if v < 0 { return "0.0%" }
    return String(format: "%.1f%%", v)
}

// MARK: - Network rate display

func formatNetRate(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "–" }
    return formatBytesPerSec(bytes)
}

// MARK: - Memory

func formatMemoryGB(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 GB" }
    return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
}

func memoryPercent(used: Int64, total: Int64) -> Double {
    guard total > 0 else { return 0 }
    return safeDouble(Double(used) / Double(total) * 100)
}

// MARK: - Thread count

func formatThreads(_ count: Int32) -> String {
    count > 0 ? "\(count)" : "–"
}

// MARK: - Disk rate

func formatDiskRate(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 B/s" }
    return formatBytesPerSec(bytes)
}
