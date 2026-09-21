import AppKit
import ScreenCaptureKit

final class DebugBridge {
    private let commandURL: URL
    private let logURL: URL
    private let state: DeckState
    private let panels: PanelManager
    private var timer: Timer?

    init(state: DeckState, panels: PanelManager, directory: URL) {
        self.state = state
        self.panels = panels
        commandURL = directory.appendingPathComponent(".notchdeck-cmd")
        logURL = directory.appendingPathComponent(".notchdeck-log")
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
        log("bridge started pid=\(ProcessInfo.processInfo.processIdentifier) ax=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
    }

    private func poll() {
        guard let data = try? Data(contentsOf: commandURL),
              let text = String(data: data, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: commandURL)
        for line in text.split(separator: "\n") {
            handle(String(line).trimmingCharacters(in: .whitespaces))
        }
    }

    private func handle(_ command: String) {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        log("> \(command)")
        switch verb {
        case "spaces":
            state.spaces.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.dumpSpaces() }
        case "switch":
            guard parts.count > 1, let n = Int(parts[1]) else { return }
            state.spaces.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let target = self.state.spaces.spaces.first(where: { $0.desktopNumber == n }) else {
                    self.log("no desktop \(n)")
                    return
                }
                let before = self.state.spaces.activeSpaceID
                self.state.spaces.switchTo(target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.state.spaces.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.log("switch \(n): before=\(before) target=\(target.id) after=\(self.state.spaces.activeSpaceID) method=\(self.state.spaces.lastSwitch.rawValue) ok=\(self.state.spaces.activeSpaceID == target.id)")
                    }
                }
            }
        case "goto":
            guard parts.count > 1, let id = UInt64(parts[1]) else { return }
            state.spaces.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let target = self.state.spaces.spaces.first(where: { $0.id == id }) else { self.log("no space \(id)"); return }
                self.state.spaces.switchTo(target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.state.spaces.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.log("goto \(id): after=\(self.state.spaces.activeSpaceID) method=\(self.state.spaces.lastSwitch.rawValue) ok=\(self.state.spaces.activeSpaceID == id)")
                    }
                }
            }
        case "enablehotkeys":
            state.spaces.enableDirectHotkeys()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.log("direct hotkeys enabled=\(self.state.spaces.directHotkeysEnabled) ctrl1=\(DesktopHotkeys.isEnabled(1))")
            }
        case "as":
            let src = command.dropFirst(3).replacingOccurrences(of: "\\n", with: "\n")
            var err: NSDictionary?
            let res = NSAppleScript(source: String(src))?.executeAndReturnError(&err)
            log("as -> \(res?.stringValue ?? "nil") err=\(err.map { "\($0[NSAppleScript.errorMessage] ?? "") (\($0[NSAppleScript.errorNumber] ?? ""))" } ?? "-")")
        case "expand":
            panels.primary?.expand(pinned: true)
        case "collapse":
            panels.primary?.collapse()
        case "glow":
            if parts.count > 1 { state.settings.glowMode = parts[1] }
            log("glowMode=\(state.settings.glowMode) album=\(String(describing: state.glowSource.albumColor)) wallpaper=\(String(describing: state.glowSource.wallpaperColor))")
        case "charge":
            state.chargePing += 1
            log("charge ping")
        case "shelfadd":
            let path = String(command.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            state.shelf.add(urls: [URL(fileURLWithPath: path)])
            log("shelf add -> \(state.shelf.items.map(\.name))")
        case "shelf":
            log("shelf: \(state.shelf.items.map(\.name))")
        case "timer":
            let mins = parts.count > 1 ? (Double(parts[1]) ?? 1) : 1
            state.timer.set(minutes: mins)
            state.timer.start()
            log("timer started \(state.timer.display)")
        case "stoptimer":
            state.timer.reset()
        case "page":
            if parts.count > 1, let p = Int(parts[1]) { panels.primary?.ui.page = p }
        case "music":
            state.music.poll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.log("music player=\(self.state.music.activePlayer?.appName ?? "none") np=\(String(describing: self.state.music.nowPlaying)) err=\(self.state.music.lastError ?? "-")")
            }
        case "vibe":
            let v = state.songVibe
            log("vibe modelReady=\(v.modelReady) mood=\(v.mood ?? "-") emoji=\(v.emoji ?? "-") energy=\(v.energy.map(String.init) ?? "-") color=\(v.color != nil) suggested=\(v.suggestedDynamic?.rawValue ?? "-") caption=\(v.caption ?? "-")")
        case "sh":
            let cmd = String(command.dropFirst(3))
            let outURL = logURL.deletingLastPathComponent().appendingPathComponent(".notchdeck-sh.out")
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", cmd]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    try? (text + "\n[exit \(p.terminationStatus)]\n").write(to: outURL, atomically: true, encoding: .utf8)
                    self.log("sh done exit=\(p.terminationStatus) bytes=\(data.count)")
                } catch {
                    try? "error: \(error)\n[exit -1]\n".write(to: outURL, atomically: true, encoding: .utf8)
                    self.log("sh failed \(error)")
                }
            }
        case "state":
            for p in panels.panels { log("state: \(p.ui.debugInfo?() ?? "-")") }
        case "warp":
            guard parts.count > 2, let x = Double(parts[1]), let y = Double(parts[2]) else { return }
            CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
            CGAssociateMouseAndMouseCursorPosition(1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { for p in self.panels.panels { self.log("after warp: \(p.ui.debugInfo?() ?? "-")") } }
        case "shot":
            let out = logURL.deletingLastPathComponent().appendingPathComponent(".notchdeck-shot.png")
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    let idx = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                    guard idx < content.displays.count else { return }
                    let display = content.displays[idx]
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    let h = parts.count > 2 ? (Int(parts[2]) ?? 420) : 420
                    config.width = display.width * 2
                    config.height = min(h, display.height) * 2
                    config.sourceRect = CGRect(x: 0, y: 0, width: display.width, height: min(h, display.height))
                    config.showsCursor = false
                    let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try data.write(to: out)
                        self.log("shot saved \(cg.width)x\(cg.height)")
                    }
                } catch {
                    self.log("shot failed \(error)")
                }
            }
        case "quit":
            NSApp.terminate(nil)
        default:
            log("unknown command")
        }
    }

    private func dumpSpaces() {
        let s = state.spaces
        log("active=\(s.activeSpaceID) count=\(s.spaces.count) displays=\(s.displays.count)")
        for d in s.displays {
            log(" display \(d.uuid) current=\(d.activeSpaceID)")
            for sp in d.spaces {
                let apps = sp.windows.map { w -> String in
                    let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "?"
                    return "\(name)#\(w.id)"
                }
                log("  \(sp.title) id=\(sp.id) managed=\(sp.managedID) fs=\(sp.isFullscreen) active=\(sp.id == d.activeSpaceID) windows=\(apps)")
            }
        }
    }

    func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
