import SwiftUI
import AppKit

// MARK: - ProcessesView

struct ProcessesView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ProcessToolbar()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Notice banner (force-quit feedback)
            if let msg = store.forceQuitState.noticeMessage {
                NoticeBanner(message: msg, isSuccess: store.forceQuitState.isSuccess)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            // Column header
            ProcessColumnHeader()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // Process rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredProcesses) { row in
                        ProcessRowView(row: row)
                            .contextMenu {
                                Button("Force Quit \(row.name)") {
                                    store.initiateForceQuit(row)
                                }
                                .disabled(row.pid == ProcessInfo.processInfo.processIdentifier)
                            }
                        Divider()
                    }
                }
            }
        }
        // Force-quit confirmation dialog
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get:  { store.forceQuitState.isConfirming },
                set:  { if !$0 { store.cancelForceQuit() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) { store.confirmForceQuit() }
            Button("Cancel",     role: .cancel)       { store.cancelForceQuit() }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmTitle: String {
        if case .confirming(let r) = store.forceQuitState { return "Force Quit \"\(r.name)\"?" }
        return "Force Quit?"
    }
    private var confirmMessage: String {
        if case .confirming(let r) = store.forceQuitState {
            return "Are you sure you want to force quit \(r.name) (PID \(r.pid))? Unsaved work will be lost."
        }
        return "This action cannot be undone."
    }
}

// MARK: - Toolbar

private struct ProcessToolbar: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search processes…", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .frame(maxWidth: 240)

            Spacer()

            // Sort picker
            Menu {
                ForEach(ProcessSortKey.allCases) { key in
                    Button {
                        if store.sortKey == key {
                            store.sortAscending.toggle()
                        } else {
                            store.sortKey = key
                            store.sortAscending = false
                        }
                    } label: {
                        HStack {
                            Text(key.rawValue)
                            if store.sortKey == key {
                                Spacer()
                                Image(systemName: store.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                    Text("Sort: \(store.sortKey.rawValue)")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)

            Text("\(store.filteredProcesses.count) processes")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Column Header

private struct ProcessColumnHeader: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            // Icon + Name
            Text("Process")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)
            columnHeader("CPU",     key: .cpu,     width: 72)
            columnHeader("Memory",  key: .memory,  width: 88)
            columnHeader("Network", key: .network, width: 96)
            columnHeader("Threads", key: .threads, width: 64)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func columnHeader(_ title: String, key: ProcessSortKey, width: CGFloat) -> some View {
        Button {
            if store.sortKey == key { store.sortAscending.toggle() }
            else { store.sortKey = key; store.sortAscending = false }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if store.sortKey == key {
                    Image(systemName: store.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .frame(width: width, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.sortKey == key ? Color.accentColor : .secondary)
    }
}

// MARK: - Single Process Row

private struct ProcessRowView: View {
    @EnvironmentObject var store: MonitorStore
    let row: ProcessRow
    @State private var isHovered = false

    var isSelf: Bool { row.pid == ProcessInfo.processInfo.processIdentifier }

    var body: some View {
        HStack(spacing: 0) {
            // Icon
            ProcessIconView(icon: row.icon, size: 18)
                .padding(.leading, 12)
                .padding(.trailing, 6)

            // Name + identifier
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.bundleIdentifier ?? "PID \(row.pid)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // CPU
            Text(formatCPUPercent(row.cpuPercent))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(row.cpuPercent > 50 ? .orange :
                                 row.cpuPercent > 20 ? Color(red: 1, green: 0.65, blue: 0) : .primary)
                .frame(width: 72, alignment: .trailing)

            // Memory
            Text(formatBytesCompact(row.memoryBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(PerformanceMetric.memory.accentColor)
                .frame(width: 88, alignment: .trailing)

            // Network
            let netTotal = row.networkBytesIn + row.networkBytesOut
            Text(netTotal > 0 ? formatBytesCompact(netTotal) + "/s" : "–")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(netTotal > 0 ? PerformanceMetric.network.accentColor : .secondary)
                .frame(width: 96, alignment: .trailing)

            // Threads
            Text(formatThreads(row.threadCount))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .padding(.vertical, 5)
        .background(
            Group {
                if isHovered && !isSelf {
                    Color.accentColor.opacity(0.08)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard !isSelf else { return }
            store.initiateForceQuit(row)
        }
        .help(isSelf ? "This is MacTaskManager itself" : "Click to force quit")
        .opacity(isSelf ? 0.5 : 1)
    }
}
