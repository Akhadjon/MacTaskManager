import Darwin
import Foundation
import AppKit

// MARK: - SystemSampler actor

actor SystemSampler {

    // MARK: Previous-state for rate calculations

    private var prevCPUTicks: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNetIn:  UInt64 = 0
    private var prevNetOut: UInt64 = 0

    // Per-process CPU state: pid -> (user_ns + sys_ns)
    private var prevProcCPU: [Int32: UInt64] = [:]

    // Per-process network (from nettop): pid -> cumulative bytes
    private var prevProcNetIn:  [Int32: UInt64] = [:]
    private var prevProcNetOut: [Int32: UInt64] = [:]

    // Disk state from iostat (cumulative MB)
    private var prevDiskReadMB:  Double = -1
    private var prevDiskWriteMB: Double = -1

    // NSRunningApplication cache keyed by pid
    private var appCache: [Int32: (name: String, bundleID: String?, icon: NSImage?)] = [:]
    private var appCacheRefreshed = Date.distantPast

    // MARK: - Public entry point

    func sample() async -> (processes: [ProcessRow], snapshot: PerformanceSnapshot) {
        async let cpuResult   = sampleCPU()
        async let memResult   = sampleMemory()
        async let netResult   = sampleNetwork()
        async let procResult  = sampleProcesses()
        async let diskResult  = sampleDisk()
        async let netProcResult = sampleProcessNetwork()

        let cpu  = await cpuResult
        let mem  = await memResult
        let net  = await netResult
        var procs = await procResult
        let disk = await diskResult
        let procNet = await netProcResult

        // Merge per-process network
        for i in procs.indices {
            let pid = procs[i].pid
            if let rates = procNet[pid] {
                procs[i].networkBytesIn  = rates.bytesIn
                procs[i].networkBytesOut = rates.bytesOut
            }
        }

        let snapshot = PerformanceSnapshot(
            cpuUsage:         cpu.usage,
            cpuUserPercent:   cpu.user,
            cpuSystemPercent: cpu.sys,
            cpuIdlePercent:   cpu.idle,
            memUsed:          mem.used,
            memAvailable:     mem.available,
            memWired:         mem.wired,
            memCompressed:    mem.compressed,
            memTotal:         mem.total,
            swapUsed:         mem.swapUsed,
            swapTotal:        mem.swapTotal,
            netBytesIn:       net.bytesIn,
            netBytesOut:      net.bytesOut,
            diskReadBytes:    disk.readBytes,
            diskWriteBytes:   disk.writeBytes
        )

        return (procs, snapshot)
    }

    // MARK: - CPU

    private struct CPUResult {
        var usage: Double; var user: Double; var sys: Double; var idle: Double
    }

    private func sampleCPU() -> CPUResult {
        var cpuLoad = host_cpu_load_info()
        var count   = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return CPUResult(usage: 0, user: 0, sys: 0, idle: 100) }

        let u = cpuLoad.cpu_ticks.0
        let s = cpuLoad.cpu_ticks.1
        let d = cpuLoad.cpu_ticks.2 // idle
        let n = cpuLoad.cpu_ticks.3

        defer { prevCPUTicks = (u, s, d, n) }

        guard let prev = prevCPUTicks else { return CPUResult(usage: 0, user: 0, sys: 0, idle: 100) }

        let du = Double(u &- prev.user)
        let ds = Double(s &- prev.sys)
        let dd = Double(d &- prev.idle)
        let dn = Double(n &- prev.nice)
        let total = du + ds + dd + dn
        guard total > 0 else { return CPUResult(usage: 0, user: 0, sys: 0, idle: 100) }

        let userPct   = safeDouble(du / total * 100)
        let sysPct    = safeDouble(ds / total * 100)
        let idlePct   = safeDouble(dd / total * 100)
        let usagePct  = safeDouble((du + ds + dn) / total * 100)

        return CPUResult(usage: usagePct, user: userPct, sys: sysPct, idle: idlePct)
    }

    // MARK: - Memory

    private struct MemResult {
        var used: Int64; var available: Int64; var wired: Int64
        var compressed: Int64; var total: Int64
        var swapUsed: Int64; var swapTotal: Int64
    }

    private func sampleMemory() -> MemResult {
        let pageSize = UInt64(vm_page_size)
        var vmInfo  = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        guard kr == KERN_SUCCESS else {
            return MemResult(used: 0, available: 0, wired: 0, compressed: 0, total: 0, swapUsed: 0, swapTotal: 0)
        }

        let wired      = Int64(UInt64(vmInfo.wire_count)            * pageSize)
        let compressed = Int64(UInt64(vmInfo.compressor_page_count) * pageSize)
        let active     = Int64(UInt64(vmInfo.active_count)          * pageSize)
        let inactive   = Int64(UInt64(vmInfo.inactive_count)        * pageSize)
        let free_      = Int64(UInt64(vmInfo.free_count)            * pageSize)
        let used       = wired + compressed + active
        let available  = free_ + inactive
        let total      = Int64(ProcessInfo.processInfo.physicalMemory)

        // Swap
        var swapInfo = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapInfo, &swapSize, nil, 0)
        let swapUsed  = Int64(bitPattern: swapInfo.xsu_used)
        let swapTotal = Int64(bitPattern: swapInfo.xsu_total)

        return MemResult(
            used: max(0, used), available: max(0, available),
            wired: max(0, wired), compressed: max(0, compressed),
            total: max(0, total),
            swapUsed: max(0, swapUsed), swapTotal: max(0, swapTotal)
        )
    }

    // MARK: - Network (system-wide via getifaddrs)

    private struct NetResult { var bytesIn: Int64; var bytesOut: Int64 }

    private func sampleNetwork() -> NetResult {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0 else { return NetResult(bytesIn: 0, bytesOut: 0) }
        defer { freeifaddrs(ifaddr) }

        var totalIn:  UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr = ifaddr
        while let current = ptr {
            let iface = current.pointee
            let name  = String(cString: iface.ifa_name)
            if !name.hasPrefix("lo"), let dataPtr = iface.ifa_data {
                let d = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                totalIn  &+= UInt64(d.ifi_ibytes)
                totalOut &+= UInt64(d.ifi_obytes)
            }
            ptr = iface.ifa_next
        }

        let deltaIn  = totalIn  >= prevNetIn  ? totalIn  - prevNetIn  : totalIn
        let deltaOut = totalOut >= prevNetOut ? totalOut - prevNetOut : totalOut
        prevNetIn  = totalIn
        prevNetOut = totalOut

        return NetResult(
            bytesIn:  safeInt64(Double(deltaIn)),
            bytesOut: safeInt64(Double(deltaOut))
        )
    }

    // MARK: - Process list

    private func sampleProcesses() -> [ProcessRow] {
        // Refresh app metadata cache ~every 5 s
        let now = Date()
        if now.timeIntervalSince(appCacheRefreshed) > 5 {
            refreshAppCache()
            appCacheRefreshed = now
        }

        let pids = listAllPIDs()
        var rows: [ProcessRow] = []
        rows.reserveCapacity(pids.count)

        for pid in pids {
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            let ret  = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
            guard ret >= size else { continue }

            // CPU %
            let totalNS = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            let prevNS  = prevProcCPU[pid] ?? totalNS
            let deltaNS = totalNS >= prevNS ? Double(totalNS - prevNS) : 0
            prevProcCPU[pid] = totalNS
            // 1 second elapsed ≈ 1e9 ns
            let cpu = safeDouble(deltaNS / 1_000_000_000.0 * 100.0)

            let mem = Int64(bitPattern: taskInfo.pti_resident_size)

            var nameBuf = [CChar](repeating: 0, count: 1025)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let procName = String(cString: nameBuf)

            let meta = appCache[pid]
            let displayName = meta?.name ?? (procName.isEmpty ? "pid:\(pid)" : procName)

            rows.append(ProcessRow(
                pid:              pid,
                name:             displayName,
                bundleIdentifier: meta?.bundleID,
                icon:             meta?.icon,
                cpuPercent:       max(0, cpu),
                memoryBytes:      max(0, mem),
                networkBytesIn:   0,
                networkBytesOut:  0,
                threadCount:      taskInfo.pti_threadnum,
                isApp:            meta != nil
            ))
        }

        // Clean up stale CPU state for dead processes
        let pidSet = Set(pids)
        prevProcCPU = prevProcCPU.filter { pidSet.contains($0.key) }

        return rows
    }

    private func listAllPIDs() -> [Int32] {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [] }
        var buf = [Int32](repeating: 0, count: Int(needed) + 16)
        let actual = proc_listallpids(&buf, Int32(buf.count) * Int32(MemoryLayout<Int32>.size))
        guard actual > 0 else { return [] }
        return Array(buf.prefix(Int(actual)))
    }

    private func refreshAppCache() {
        var cache: [Int32: (name: String, bundleID: String?, icon: NSImage?)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            cache[pid] = (
                name:     app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                bundleID: app.bundleIdentifier,
                icon:     app.icon
            )
        }
        appCache = cache
    }

    // MARK: - Disk (via iostat)

    private struct DiskResult { var readBytes: Int64; var writeBytes: Int64 }

    private func sampleDisk() async -> DiskResult {
        // iostat -d -c 2 -w 1 gives two samples; delta comes from last line
        guard let output = try? await runCommand("/usr/sbin/iostat", args: ["-d", "-c", "2", "-w", "1"])
        else { return DiskResult(readBytes: 0, writeBytes: 0) }

        return parseIostatOutput(output)
    }

    private func parseIostatOutput(_ output: String) -> DiskResult {
        // Format (may have multiple disks):
        //           disk0           disk1
        //     KB/t  tps  MB/s   KB/t  tps  MB/s
        //    64.00   17  1.05   0.00    0  0.00
        //     0.00    0  0.00   0.00    0  0.00   <- interval sample
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        // The last non-empty line after the header lines is the interval sample
        // Find header line containing "MB/s"
        var headerIdx = -1
        for (i, line) in lines.enumerated() {
            if line.contains("MB/s") { headerIdx = i; break }
        }
        guard headerIdx >= 0, lines.count > headerIdx + 2 else { return DiskResult(readBytes: 0, writeBytes: 0) }

        let intervalLine = lines[headerIdx + 2]
        let parts = intervalLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Each disk takes 3 columns: KB/t, tps, MB/s (index 2, 5, 8 ...)
        // We want the MB/s columns (indices 2, 5, 8, ...)
        var totalMBs: Double = 0
        // Read MB/s is at positions 2, 5, 8... for each disk
        // iostat doesn't separate read/write by default; we'll assign to read
        var idx = 2
        while idx < parts.count {
            if let v = Double(parts[idx]) { totalMBs += safeDouble(v) }
            idx += 3
        }

        let readBytes = safeInt64(totalMBs * 1_048_576)
        return DiskResult(readBytes: readBytes, writeBytes: 0)
    }

    // MARK: - Per-process network (via nettop)

    private func sampleProcessNetwork() async -> [Int32: (bytesIn: Int64, bytesOut: Int64)] {
        guard let output = try? await runCommand(
            "/usr/bin/nettop",
            args: ["-P", "-L", "2", "-s", "1", "-n", "-x"]
        ) else { return [:] }

        return parseNettopOutput(output)
    }

    private func parseNettopOutput(_ raw: String) -> [Int32: (bytesIn: Int64, bytesOut: Int64)] {
        var result: [Int32: (bytesIn: Int64, bytesOut: Int64)] = [:]
        let lines = raw.components(separatedBy: "\n")

        // --- Strategy 1: tab-separated with header ---
        if let headerLine = lines.first(where: { l in
            let lo = l.lowercased()
            return lo.contains("bytes_in") || lo.contains("bytes in")
        }) {
            let cols = headerLine.components(separatedBy: "\t")
            var inIdx  = -1
            var outIdx = -1
            var pidIdx = -1
            for (i, c) in cols.enumerated() {
                let lo = c.lowercased().trimmingCharacters(in: .whitespaces)
                if lo == "pid"                                   { pidIdx  = i }
                if lo.contains("bytes_in")  || lo == "rx bytes" { inIdx   = i }
                if lo.contains("bytes_out") || lo == "tx bytes" { outIdx  = i }
            }
            if inIdx >= 0, outIdx >= 0 {
                var seenHeader = false
                for line in lines {
                    if line == headerLine { seenHeader = true; continue }
                    guard seenHeader else { continue }
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count > max(inIdx, outIdx) else { continue }
                    let pidVal: Int32?
                    if pidIdx >= 0, pidIdx < parts.count {
                        pidVal = Int32(parts[pidIdx].trimmingCharacters(in: .whitespaces))
                    } else {
                        pidVal = nil
                    }
                    guard let pid = pidVal else { continue }
                    let inB  = Int64(parts[inIdx ].trimmingCharacters(in: .whitespaces)) ?? 0
                    let outB = Int64(parts[outIdx].trimmingCharacters(in: .whitespaces)) ?? 0
                    // compute delta
                    let prevIn  = prevProcNetIn[pid]  ?? UInt64(inB)
                    let prevOut = prevProcNetOut[pid] ?? UInt64(outB)
                    let curIn   = UInt64(max(0, inB))
                    let curOut  = UInt64(max(0, outB))
                    let dIn  = curIn  >= prevIn  ? curIn  - prevIn  : curIn
                    let dOut = curOut >= prevOut ? curOut - prevOut : curOut
                    prevProcNetIn[pid]  = curIn
                    prevProcNetOut[pid] = curOut
                    if dIn > 0 || dOut > 0 {
                        result[pid] = (bytesIn: Int64(dIn), bytesOut: Int64(dOut))
                    }
                }
                if !result.isEmpty { return result }
            }
        }

        // --- Strategy 2: ==== processname.pid format ---
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("====") else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 4, parts[0] == "====" else { continue }
            // parts[1] = "processname.pid"
            let proc = parts[1]
            guard let dotIdx = proc.lastIndex(of: ".") else { continue }
            let pidStr = String(proc[proc.index(after: dotIdx)...])
            guard let pid = Int32(pidStr) else { continue }
            var numbers: [Int64] = []
            for p in parts.dropFirst(2) {
                if let n = Int64(p) { numbers.append(n) }
            }
            if numbers.count >= 2 {
                let curIn  = UInt64(max(0, numbers[0]))
                let curOut = UInt64(max(0, numbers[1]))
                let prevIn  = prevProcNetIn[pid]  ?? curIn
                let prevOut = prevProcNetOut[pid] ?? curOut
                let dIn  = curIn  >= prevIn  ? curIn  - prevIn  : curIn
                let dOut = curOut >= prevOut ? curOut - prevOut : curOut
                prevProcNetIn[pid]  = curIn
                prevProcNetOut[pid] = curOut
                if dIn > 0 || dOut > 0 {
                    result[pid] = (bytesIn: Int64(dIn), bytesOut: Int64(dOut))
                }
            }
        }

        return result
    }

    // MARK: - Subprocess helper

    private func runCommand(_ path: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments     = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError  = errPipe

            let timeout = DispatchWorkItem {
                if proc.isRunning { proc.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: timeout)

            proc.terminationHandler = { _ in
                timeout.cancel()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                try proc.run()
            } catch {
                timeout.cancel()
                cont.resume(throwing: error)
            }
        }
    }
}
