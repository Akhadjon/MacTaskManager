import SwiftUI
import AppKit

// MARK: - PerformanceView

struct PerformanceView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(spacing: 0) {
            // Metric picker bar
            HStack(spacing: 6) {
                ForEach(PerformanceMetric.allCases) { metric in
                    MetricPickerButton(metric: metric,
                                       isSelected: store.selectedMetric == metric)
                    { store.selectedMetric = metric }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Scrollable detail
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch store.selectedMetric {
                    case .cpu:     CPUDetailView()
                    case .memory:  MemoryDetailView()
                    case .network: NetworkDetailView()
                    case .disk:    DiskDetailView()
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Metric Picker Button

private struct MetricPickerButton: View {
    let metric: PerformanceMetric
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemIcon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text(metric.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? metric.accentColor
                    : Color(NSColor.controlBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CPU Detail

private struct CPUDetailView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Big value
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(formatPercent(store.snapshot.cpuUsage, decimals: 1))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(PerformanceMetric.cpu.accentColor)
                Text("CPU Usage")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Chart
            LargeChartPanel(
                title:      "CPU Utilisation — 60 second history",
                data:       store.cpuHistory,
                maxValue:   100,
                color:      PerformanceMetric.cpu.accentColor,
                leftLabel:  "0%",
                rightLabel: "100%"
            )

            // Breakdown
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()),
                          GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                StatTile(label: "User",   value: formatPercent(store.snapshot.cpuUserPercent,   decimals: 1),
                         color: PerformanceMetric.cpu.accentColor)
                StatTile(label: "System", value: formatPercent(store.snapshot.cpuSystemPercent, decimals: 1),
                         color: .orange)
                StatTile(label: "Idle",   value: formatPercent(store.snapshot.cpuIdlePercent,   decimals: 1))
                StatTile(label: "Processes", value: "\(store.processes.count)")
            }

            // Top CPU consumers
            Panel(title: "Top CPU Consumers") {
                ForEach(Array(store.topCPUProcesses.enumerated()), id: \.element.id) { i, p in
                    TopProcessRow(rank: i + 1, process: p,
                                  value: formatCPUPercent(p.cpuPercent),
                                  color: PerformanceMetric.cpu.accentColor)
                    if i < store.topCPUProcesses.count - 1 { Divider() }
                }
            }
        }
    }
}

// MARK: - Memory Detail

private struct MemoryDetailView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let pct = memoryPercent(used: store.snapshot.memUsed, total: store.snapshot.memTotal)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(formatPercent(pct, decimals: 1))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(PerformanceMetric.memory.accentColor)
                Text("Memory Pressure")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Memory bar
            MemoryBar(snapshot: store.snapshot)

            LargeChartPanel(
                title:      "Memory Usage — 60 second history",
                data:       store.memHistory,
                maxValue:   100,
                color:      PerformanceMetric.memory.accentColor,
                leftLabel:  "0%",
                rightLabel: "100%"
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 3),
                spacing: 8
            ) {
                StatTile(label: "Used",       value: formatBytes(store.snapshot.memUsed),
                         color: PerformanceMetric.memory.accentColor)
                StatTile(label: "Wired",      value: formatBytes(store.snapshot.memWired))
                StatTile(label: "Compressed", value: formatBytes(store.snapshot.memCompressed))
                StatTile(label: "Available",  value: formatBytes(store.snapshot.memAvailable))
                StatTile(label: "Swap Used",  value: formatBytes(store.snapshot.swapUsed),
                         color: store.snapshot.swapUsed > 0 ? .orange : .primary)
                StatTile(label: "Total RAM",  value: formatMemoryGB(store.snapshot.memTotal))
            }

            Panel(title: "Top Memory Consumers") {
                ForEach(Array(store.topMemoryProcesses.enumerated()), id: \.element.id) { i, p in
                    TopProcessRow(rank: i + 1, process: p,
                                  value: formatBytes(p.memoryBytes),
                                  color: PerformanceMetric.memory.accentColor)
                    if i < store.topMemoryProcesses.count - 1 { Divider() }
                }
            }
        }
    }
}

// MARK: - Memory Bar (stacked)

private struct MemoryBar: View {
    let snapshot: PerformanceSnapshot
    var body: some View {
        GeometryReader { geo in
            let total = max(Double(snapshot.memTotal), 1)
            let wiredW      = geo.size.width * CGFloat(Double(snapshot.memWired)      / total)
            let activeW     = geo.size.width * CGFloat(Double(snapshot.memUsed - snapshot.memWired - snapshot.memCompressed) / total)
            let compW       = geo.size.width * CGFloat(Double(snapshot.memCompressed) / total)
            HStack(spacing: 0) {
                Rectangle().fill(Color.orange).frame(width: max(0, wiredW))
                Rectangle().fill(PerformanceMetric.memory.accentColor).frame(width: max(0, activeW))
                Rectangle().fill(Color.purple.opacity(0.7)).frame(width: max(0, compW))
                Spacer()
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .background(Color(NSColor.separatorColor).opacity(0.3).clipShape(RoundedRectangle(cornerRadius: 4)))
        .overlay(
            HStack(spacing: 16) {
                legendDot(.orange, "Wired")
                legendDot(PerformanceMetric.memory.accentColor, "Active")
                legendDot(.purple.opacity(0.7), "Compressed")
                Spacer()
            }
            .font(.system(size: 10))
            .offset(y: 18),
            alignment: .leading
        )
        .padding(.bottom, 24)
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Network Detail

private struct NetworkDetailView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(formatBytesCompact(store.snapshot.netBytesIn) + "/s")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(PerformanceMetric.network.accentColor)
                Text("Download")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            LargeChartPanel(
                title:      "Network Download — 60 second history",
                data:       store.netInHistory,
                maxValue:   store.netHistoryMax,
                color:      PerformanceMetric.network.accentColor,
                leftLabel:  "0",
                rightLabel: formatBytesCompact(safeInt64(store.netHistoryMax)) + "/s"
            )
            LargeChartPanel(
                title:      "Network Upload — 60 second history",
                data:       store.netOutHistory,
                maxValue:   store.netHistoryMax,
                color:      PerformanceMetric.network.accentColor.opacity(0.6),
                leftLabel:  "0",
                rightLabel: formatBytesCompact(safeInt64(store.netHistoryMax)) + "/s"
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                StatTile(label: "Download",  value: formatBytesPerSec(store.snapshot.netBytesIn),
                         color: PerformanceMetric.network.accentColor)
                StatTile(label: "Upload",    value: formatBytesPerSec(store.snapshot.netBytesOut),
                         color: PerformanceMetric.network.accentColor.opacity(0.7))
            }

            Panel(title: "Top Network Activity") {
                let topNet = store.topNetworkProcesses
                if topNet.allSatisfy({ $0.networkBytesIn + $0.networkBytesOut == 0 }) {
                    Text("No per-process network data available")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(topNet.enumerated()), id: \.element.id) { i, p in
                        TopProcessRow(rank: i + 1, process: p,
                                      value: formatBytesCompact(p.networkBytesIn + p.networkBytesOut) + "/s",
                                      color: PerformanceMetric.network.accentColor)
                        if i < topNet.count - 1 { Divider() }
                    }
                }
            }
        }
    }
}

// MARK: - Disk Detail

private struct DiskDetailView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(formatBytesCompact(store.snapshot.diskReadBytes) + "/s")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(PerformanceMetric.disk.accentColor)
                Text("Disk Read")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            LargeChartPanel(
                title:      "Disk Read — 60 second history",
                data:       store.diskReadHistory,
                maxValue:   store.diskHistoryMax,
                color:      PerformanceMetric.disk.accentColor,
                leftLabel:  "0",
                rightLabel: formatBytesCompact(safeInt64(store.diskHistoryMax)) + "/s"
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                StatTile(label: "Read",  value: formatDiskRate(store.snapshot.diskReadBytes),
                         color: PerformanceMetric.disk.accentColor)
                StatTile(label: "Write", value: formatDiskRate(store.snapshot.diskWriteBytes),
                         color: PerformanceMetric.disk.accentColor.opacity(0.7))
            }

            Text("Disk throughput is measured via `iostat -d`. Write rate is not separately available from iostat's default output.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
