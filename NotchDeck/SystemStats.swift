import Foundation
import AppKit
import IOKit.ps
import Combine

final class SystemStats: ObservableObject {
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotal: Double = 0
    @Published private(set) var batteryLevel: Double = 1
    @Published private(set) var isCharging = false
    @Published private(set) var hasBattery = false
    @Published private(set) var batteryMinutes: Int?
    @Published private(set) var now = Date()
    @Published private(set) var diskUsed: Double = 0
    @Published private(set) var diskTotal: Double = 0
    @Published private(set) var downRate: Double = 0
    @Published private(set) var upRate: Double = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var topProcessName = ""
    @Published private(set) var topProcessCPU: Double = 0
    @Published private(set) var outputVolume: Double = 0.5
    @Published private(set) var isMuted = false
    @Published private(set) var keepAwake = false

    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var timer: Timer?
    private var previousCPU: (idle: Double, total: Double) = (0, 0)
    private var tickCount = 0
    private var volumeHold = Date.distantPast
    private var caffeinate: Process?
    private let psQueue = DispatchQueue(label: "notchdeck.ps", qos: .utility)

    func start() {
        memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        now = Date()
        tickCount += 1
        sampleCPU()
        sampleMemory()
        sampleBattery()
        sampleDisk()
        sampleNetwork()
        thermalState = ProcessInfo.processInfo.thermalState
        if Date() > volumeHold { sampleVolume() }
        if tickCount % 2 == 1 { sampleTopProcess() }
    }

    private func sampleVolume() {
        let src = """
        set v to output volume of (get volume settings)
        set m to output muted of (get volume settings)
        return (v as string) & "|" & (m as string)
        """
        guard let r = NSAppleScript(source: src)?.executeAndReturnError(nil).stringValue else { return }
        let parts = r.split(separator: "|")
        guard parts.count == 2, let v = Double(parts[0]) else { return }
        outputVolume = v / 100
        isMuted = parts[1] == "true"
    }

    func setOutputVolume(_ frac: Double) {
        let v = Int((min(max(frac, 0), 1) * 100).rounded())
        outputVolume = Double(v) / 100
        if isMuted { isMuted = false }
        volumeHold = Date().addingTimeInterval(1.5)
        NSAppleScript(source: "set volume output volume \(v)")?.executeAndReturnError(nil)
    }

    func toggleMute() {
        isMuted.toggle()
        volumeHold = Date().addingTimeInterval(1.5)
        NSAppleScript(source: "set volume output muted \(isMuted)")?.executeAndReturnError(nil)
    }

    func toggleKeepAwake() {
        if let c = caffeinate {
            c.terminate()
            caffeinate = nil
            keepAwake = false
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-dis"]
        guard (try? p.run()) != nil else { return }
        caffeinate = p
        keepAwake = true
    }

    func stopKeepAwake() {
        caffeinate?.terminate()
        caffeinate = nil
        keepAwake = false
    }

    private func sampleTopProcess() {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        psQueue.async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-Aceo", "pid=,pcpu=,comm=", "-r"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                let cols = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard cols.count == 3, let pid = Int32(cols[0]) else { continue }
                if pid == ownPid || cols[2] == "ps" { continue }
                let cpu = Double(cols[1].replacingOccurrences(of: ",", with: ".")) ?? 0
                let name = String(cols[2])
                DispatchQueue.main.async {
                    self?.topProcessCPU = cpu / 100
                    self?.topProcessName = name
                }
                return
            }
        }
    }

    private func sampleDisk() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else { return }
        let total = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
        let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        diskTotal = total
        diskUsed = max(0, total - free)
    }

    private func sampleNetwork() {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return }
        defer { freeifaddrs(addrs) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
               let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
            cursor = ifa.pointee.ifa_next
        }
        let nowDate = Date()
        if let last = lastNet {
            let dt = nowDate.timeIntervalSince(last.at)
            if dt > 0 {
                downRate = rx >= last.rx ? Double(rx - last.rx) / dt : 0
                upRate = tx >= last.tx ? Double(tx - last.tx) / dt : 0
            }
        }
        lastNet = (rx, tx, nowDate)
    }

    private func sampleCPU() {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let user = Double(info.cpu_ticks.0), system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        let total = user + system + idle + nice
        let dTotal = total - previousCPU.total
        let dIdle = idle - previousCPU.idle
        if dTotal > 0 { cpuUsage = max(0, min(1, 1 - dIdle / dTotal)) }
        previousCPU = (idle, total)
    }

    private func sampleMemory() {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        memoryUsed = used
    }

    private func sampleBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any] else {
            hasBattery = false
            return
        }
        hasBattery = true
        let capacity = desc[kIOPSCurrentCapacityKey] as? Double ?? 100
        let max = desc[kIOPSMaxCapacityKey] as? Double ?? 100
        batteryLevel = max > 0 ? capacity / max : 1
        isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        if let m = desc[key] as? Int, m > 0 { batteryMinutes = m } else { batteryMinutes = nil }
    }
}

enum QuickActions {
    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    static func lockScreen() {
        run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
    }

    static func sleepDisplay() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    static func missionControl() {
        run("/usr/bin/open", ["-a", "Mission Control"])
    }

    static func toggleDarkMode() {
        let src = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }

    static func screenshot() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let path = NSHomeDirectory() + "/Desktop/Screenshot " + f.string(from: Date()) + ".png"
        run("/usr/sbin/screencapture", ["-i", path])
    }
}
