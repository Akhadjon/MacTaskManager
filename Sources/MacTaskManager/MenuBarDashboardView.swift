import SwiftUI
import AppKit

// MARK: - MenuBarDashboardView (popover content)

struct MenuBarDashboardView: View {
    @EnvironmentObject var store: MonitorStore
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("MacTaskManager")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // Live indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Summary metrics
            VStack(spacing: 8) {
                PopoverMetricRow(
                    label:   "CPU",
                    value:   formatPercent(store.snapshot.cpuUsage, decimals: 1),
                    history: store.cpuHistory,
                    maxVal:  100,
                    color:   PerformanceMetric.cpu.accentColor
                )
                PopoverMetricRow(
                    label:   "Memory",
                    value:   formatPercent(
                        memoryPercent(used: store.snapshot.memUsed, total: store.snapshot.memTotal),
                        decimals: 1
                    ),
                    history: store.memHistory,
                    maxVal:  100,
                    color:   PerformanceMetric.memory.accentColor
                )
                PopoverMetricRow(
                    label:   "Net ↓",
                    value:   formatBytesCompact(store.snapshot.netBytesIn) + "/s",
                    history: store.netInHistory,
                    maxVal:  store.netHistoryMax,
                    color:   PerformanceMetric.network.accentColor
                )
                PopoverMetricRow(
                    label:   "Disk",
                    value:   formatBytesCompact(store.snapshot.diskReadBytes) + "/s",
                    history: store.diskReadHistory,
                    maxVal:  store.diskHistoryMax,
                    color:   PerformanceMetric.disk.accentColor
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Top 5 processes (by CPU)
            VStack(alignment: .leading, spacing: 4) {
                Text("TOP PROCESSES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .padding(.bottom, 2)

                ForEach(Array(store.topCPUProcesses.prefix(5).enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 8) {
                        Text("\(i+1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, alignment: .trailing)

                        ProcessIconView(icon: p.icon, size: 14)

                        Text(p.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(formatCPUPercent(p.cpuPercent))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PerformanceMetric.cpu.accentColor)
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Open dashboard button
            Button {
                openDashboard()
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                    Text("Open Dashboard")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("⌥⌘M")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(PopoverButtonStyle())
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Popover metric row with mini sparkline

private struct PopoverMetricRow: View {
    var label:   String
    var value:   String
    var history: [Double]
    var maxVal:  Double
    var color:   Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            SparklineChart(data: history.isEmpty ? [0] : history,
                           color: color,
                           maxValue: maxVal,
                           showFill: false)
                .frame(width: 70, height: 22)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - Popover Button Style

private struct PopoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isHovered || configuration.isPressed
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear
            )
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
