import SwiftUI
import AppKit

// MARK: - ContentView (main dashboard window)

struct ContentView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            // Left navigation rail
            VStack(spacing: 0) {
                // App branding
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Task Manager")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .padding(.bottom, 8)

                // Navigation items
                VStack(spacing: 2) {
                    ForEach(AppSection.allCases) { section in
                        NavRailItem(
                            section:    section,
                            isSelected: store.selectedSection == section,
                            action:     { store.selectedSection = section }
                        )
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                Divider()
                    .padding(.top, 8)

                // Summary status footer
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(store.processes.count) processes")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text("CPU \(formatPercent(store.snapshot.cpuUsage, decimals: 0))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Settings button
                Button {
                    store.showingSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .frame(width: 20)
                        Text("Settings")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 180)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content area
            Group {
                switch store.selectedSection {
                case .overview:    OverviewView()
                case .processes:   ProcessesView()
                case .performance: PerformanceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 520)
        .preferredColorScheme(store.appearance == .system ? nil :
                              store.appearance == .dark   ? .dark : .light)
        .sheet(isPresented: $store.showingSettings) {
            SettingsSheetView()
                .environmentObject(store)
                .preferredColorScheme(store.appearance == .system ? nil :
                                      store.appearance == .dark   ? .dark : .light)
        }
    }
}

// MARK: - Overview Section

struct OverviewView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Top summary cards
                SectionHeader(title: "System Overview")
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()),
                              GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    MetricCard(
                        title:      "CPU",
                        value:      formatPercent(store.snapshot.cpuUsage, decimals: 1),
                        subtitle:   "User \(formatPercent(store.snapshot.cpuUserPercent, decimals: 0))  Sys \(formatPercent(store.snapshot.cpuSystemPercent, decimals: 0))",
                        color:      PerformanceMetric.cpu.accentColor,
                        history:    store.cpuHistory,
                        historyMax: 100
                    )
                    MetricCard(
                        title:      "Memory",
                        value:      formatPercent(
                            memoryPercent(used: store.snapshot.memUsed, total: store.snapshot.memTotal),
                            decimals: 1
                        ),
                        subtitle:   formatBytes(store.snapshot.memUsed) + " used",
                        color:      PerformanceMetric.memory.accentColor,
                        history:    store.memHistory,
                        historyMax: 100
                    )
                    MetricCard(
                        title:      "Network ↓",
                        value:      formatBytesCompact(store.snapshot.netBytesIn) + "/s",
                        subtitle:   "↑ " + formatBytesCompact(store.snapshot.netBytesOut) + "/s",
                        color:      PerformanceMetric.network.accentColor,
                        history:    store.netInHistory,
                        historyMax: store.netHistoryMax
                    )
                    MetricCard(
                        title:      "Disk",
                        value:      formatBytesCompact(store.snapshot.diskReadBytes) + "/s",
                        subtitle:   "Read rate",
                        color:      PerformanceMetric.disk.accentColor,
                        history:    store.diskReadHistory,
                        historyMax: store.diskHistoryMax
                    )
                }
                .padding(.horizontal, 16)

                // Top processes panels
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Top CPU") {
                        ForEach(Array(store.topCPUProcesses.enumerated()), id: \.element.id) { i, p in
                            TopProcessRow(
                                rank:    i + 1,
                                process: p,
                                value:   formatCPUPercent(p.cpuPercent),
                                color:   PerformanceMetric.cpu.accentColor
                            )
                            if i < store.topCPUProcesses.count - 1 {
                                Divider()
                            }
                        }
                    }
                    Panel(title: "Top Memory") {
                        ForEach(Array(store.topMemoryProcesses.enumerated()), id: \.element.id) { i, p in
                            TopProcessRow(
                                rank:    i + 1,
                                process: p,
                                value:   formatBytesCompact(p.memoryBytes),
                                color:   PerformanceMetric.memory.accentColor
                            )
                            if i < store.topMemoryProcesses.count - 1 {
                                Divider()
                            }
                        }
                    }
                    Panel(title: "Top Network") {
                        let topNet = store.topNetworkProcesses
                        if topNet.allSatisfy({ $0.networkBytesIn + $0.networkBytesOut == 0 }) {
                            Text("No network activity")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array(topNet.enumerated()), id: \.element.id) { i, p in
                                TopProcessRow(
                                    rank:    i + 1,
                                    process: p,
                                    value:   formatBytesCompact(p.networkBytesIn + p.networkBytesOut) + "/s",
                                    color:   PerformanceMetric.network.accentColor
                                )
                                if i < topNet.count - 1 { Divider() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Memory & Disk stats panel
                Panel(title: "Memory & Disk") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        spacing: 8
                    ) {
                        StatTile(
                            label: "Available",
                            value: formatBytes(store.snapshot.memAvailable),
                            color: PerformanceMetric.memory.accentColor
                        )
                        StatTile(
                            label: "Wired",
                            value: formatBytes(store.snapshot.memWired)
                        )
                        StatTile(
                            label: "Compressed",
                            value: formatBytes(store.snapshot.memCompressed)
                        )
                        StatTile(
                            label: "Swap Used",
                            value: formatBytes(store.snapshot.swapUsed),
                            color: store.snapshot.swapUsed > 0 ? .orange : .primary
                        )
                        StatTile(
                            label: "Swap Total",
                            value: formatBytes(store.snapshot.swapTotal)
                        )
                        StatTile(
                            label: "Disk Read",
                            value: formatBytesPerSec(store.snapshot.diskReadBytes),
                            color: PerformanceMetric.disk.accentColor
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
