import Foundation
import AppKit
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {

    // MARK: Navigation & UI state

    @Published var selectedSection: AppSection   = .overview
    @Published var selectedMetric: PerformanceMetric = .cpu
    @Published var appearance: AppearanceSetting = .system
    @Published var showingSettings: Bool         = false

    // MARK: Process state

    @Published var processes: [ProcessRow] = []
    @Published var searchText: String      = ""
    @Published var sortKey: ProcessSortKey = .cpu
    @Published var sortAscending: Bool     = false

    // MARK: Performance state

    @Published var snapshot: PerformanceSnapshot = .zero

    // 60-second rolling histories (values are metric-appropriate)
    @Published var cpuHistory:       [Double] = []   // 0–100
    @Published var memHistory:       [Double] = []   // 0–100
    @Published var netInHistory:     [Double] = []   // bytes/s
    @Published var netOutHistory:    [Double] = []   // bytes/s
    @Published var diskReadHistory:  [Double] = []   // bytes/s
    @Published var diskWriteHistory: [Double] = []   // bytes/s

    // MARK: Force-quit flow

    @Published var forceQuitState: ForceQuitState = .idle

    // MARK: Private

    private let sampler = SystemSampler()
    private var samplerTask: Task<Void, Never>?
    private let historyMax = 60

    // MARK: Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: "appearance"),
           let saved = AppearanceSetting(rawValue: raw) {
            appearance = saved
            NSApp.appearance = saved.nsAppearance
        }
    }

    // MARK: Sampling

    func startSampling() {
        guard samplerTask == nil else { return }
        samplerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let (procs, snap) = await self.sampler.sample()
                await MainActor.run {
                    self.processes = procs
                    self.snapshot  = snap
                    self.appendHistory(snap)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSampling() {
        samplerTask?.cancel()
        samplerTask = nil
    }

    private func appendHistory(_ snap: PerformanceSnapshot) {
        func append(_ arr: inout [Double], _ v: Double) {
            arr.append(safeDouble(v))
            if arr.count > historyMax { arr.removeFirst() }
        }
        let memPct = snap.memTotal > 0
            ? safeDouble(Double(snap.memUsed) / Double(snap.memTotal) * 100)
            : 0
        append(&cpuHistory,       snap.cpuUsage)
        append(&memHistory,       memPct)
        append(&netInHistory,     Double(max(0, snap.netBytesIn)))
        append(&netOutHistory,    Double(max(0, snap.netBytesOut)))
        append(&diskReadHistory,  Double(max(0, snap.diskReadBytes)))
        append(&diskWriteHistory, Double(max(0, snap.diskWriteBytes)))
    }

    // MARK: Appearance

    func setAppearance(_ setting: AppearanceSetting) {
        appearance = setting
        UserDefaults.standard.set(setting.rawValue, forKey: "appearance")
        NSApp.appearance = setting.nsAppearance
    }

    // MARK: Derived process lists

    var filteredProcesses: [ProcessRow] {
        let base: [ProcessRow]
        if searchText.isEmpty {
            base = processes
        } else {
            let q = searchText.lowercased()
            base = processes.filter {
                $0.name.lowercased().contains(q) ||
                ($0.bundleIdentifier?.lowercased().contains(q) ?? false) ||
                "\($0.pid)".contains(q)
            }
        }
        return base.sorted { a, b in
            let asc: Bool
            switch sortKey {
            case .name:    asc = a.name < b.name
            case .cpu:     asc = a.cpuPercent > b.cpuPercent
            case .memory:  asc = a.memoryBytes > b.memoryBytes
            case .network: asc = (a.networkBytesIn + a.networkBytesOut) > (b.networkBytesIn + b.networkBytesOut)
            case .threads: asc = a.threadCount > b.threadCount
            }
            return sortAscending ? !asc : asc
        }
    }

    var topCPUProcesses: [ProcessRow] {
        Array(processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
    }

    var topMemoryProcesses: [ProcessRow] {
        Array(processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
    }

    var topNetworkProcesses: [ProcessRow] {
        Array(processes.sorted {
            ($0.networkBytesIn + $0.networkBytesOut) > ($1.networkBytesIn + $1.networkBytesOut)
        }.prefix(5))
    }

    // MARK: Force Quit

    func initiateForceQuit(_ row: ProcessRow) {
        let myPid = ProcessInfo.processInfo.processIdentifier
        guard row.pid != myPid else { return }
        forceQuitState = .confirming(row)
    }

    func confirmForceQuit() {
        guard case .confirming(let row) = forceQuitState else { return }
        let myPid = ProcessInfo.processInfo.processIdentifier
        guard row.pid != myPid else {
            forceQuitState = .failure("Cannot quit this app.")
            scheduleNoticeReset()
            return
        }

        var succeeded = false
        // Try NSRunningApplication first
        if let app = NSRunningApplication(processIdentifier: row.pid) {
            succeeded = app.forceTerminate()
        }
        // Fall back to SIGKILL
        if !succeeded {
            succeeded = (kill(row.pid, SIGKILL) == 0)
        }

        forceQuitState = succeeded
            ? .success("Terminated \(row.name).")
            : .failure("Failed to terminate \(row.name).")
        scheduleNoticeReset()
    }

    func cancelForceQuit() {
        forceQuitState = .idle
    }

    private func scheduleNoticeReset() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { self?.forceQuitState = .idle }
        }
    }

    // MARK: History max for charts

    var cpuHistoryMax: Double { 100 }

    var memHistoryMax: Double { 100 }

    var netHistoryMax: Double {
        let combined = netInHistory + netOutHistory
        return max(combined.max() ?? 1, 1)
    }

    var diskHistoryMax: Double {
        let combined = diskReadHistory + diskWriteHistory
        return max(combined.max() ?? 1, 1)
    }
}
