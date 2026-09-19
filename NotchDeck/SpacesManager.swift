import AppKit
import Combine
import ScreenCaptureKit
import ApplicationServices

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: Int32) -> UInt64

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct SpaceWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
}

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let managedID: Int
    let uuid: String
    let isFullscreen: Bool
    let desktopNumber: Int?
    let displayUUID: String
    var windows: [SpaceWindow] = []

    var appPIDs: [pid_t] {
        var seen: [pid_t] = []
        for w in windows where !seen.contains(w.pid) { seen.append(w.pid) }
        return seen
    }

    var title: String {
        if let n = desktopNumber { return "Desktop \(n)" }
        return "Full Screen"
    }

    static func == (lhs: SpaceInfo, rhs: SpaceInfo) -> Bool {
        lhs.id == rhs.id && lhs.windows == rhs.windows && lhs.desktopNumber == rhs.desktopNumber
    }
}

enum SwitchMethod: String {
    case hotkey, none
}

struct DisplaySpaces: Equatable {
    let uuid: String
    var spaces: [SpaceInfo]
    var activeSpaceID: UInt64

    var displayID: CGDirectDisplayID {
        if uuid == "Main" { return CGMainDisplayID() }
        guard let cf = CFUUIDCreateFromString(nil, uuid as CFString) else { return CGMainDisplayID() }
        return CGDisplayGetDisplayIDFromUUID(cf)
    }
}

final class SpacesManager: ObservableObject {
    @Published private(set) var spaces: [SpaceInfo] = []
    @Published private(set) var activeSpaceID: UInt64 = 0
    @Published private(set) var displays: [DisplaySpaces] = []
    private var currentDisplays: [DisplaySpaces] = []
    @Published private(set) var thumbnails: [UInt64: NSImage] = [:]
    @Published private(set) var hasScreenCapture = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var directHotkeysEnabled = false
    @Published var lastSwitch: SwitchMethod = .none
    @Published var lastError: String?

    var excludedWindowNumbers: Set<Int> = []
    static var debugLog: ((String) -> Void)?

    private let cid = CGSMainConnectionID()
    private var observers: [NSObjectProtocol] = []
    private var captureInFlight = false
    private var captureTimer: Timer?
    private var compositeInFlight = false
    private var compositeTimer: Timer?
    var isDeckOpen = false {
        didSet {
            if isDeckOpen && !oldValue { captureAllSpaces() }
        }
    }
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    func start() {
        refreshPermissions()
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                self?.captureActiveSpace()
            }
        })
        captureTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
            self?.captureActiveSpace()
        }
        RunLoop.main.add(captureTimer!, forMode: .common)
        compositeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.isDeckOpen else { return }
            self.captureAllSpaces()
        }
        RunLoop.main.add(compositeTimer!, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.captureActiveSpace()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.captureAllSpaces()
        }
    }

    // MARK: - Off-space previews (composited from per-window captures)

    func captureAllSpaces() {
        guard !compositeInFlight, CGPreflightScreenCaptureAccess() else { return }
        compositeInFlight = true
        refresh()
        var jobs: [(displayID: CGDirectDisplayID, wallpaper: NSImage?, targets: [SpaceInfo])] = []
        for d in currentDisplays {
            let targets = d.spaces.filter { $0.id != d.activeSpaceID }
            let screen = NSScreen.screens.first { SpacesManager.uuid(for: $0) == d.uuid } ?? NotchPanel.preferredScreen()
            let wallpaper = NSWorkspace.shared.desktopImageURL(for: screen).flatMap { NSImage(contentsOf: $0) }
            jobs.append((d.displayID, wallpaper, targets))
        }

        Task { [weak self] in
            defer { DispatchQueue.main.async { self?.compositeInFlight = false } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let byID = Dictionary(uniqueKeysWithValues: content.windows.map { (Int($0.windowID), $0) })
                for job in jobs {
                    guard let display = content.displays.first(where: { $0.displayID == job.displayID }) else { continue }
                    let scale = 720.0 / Double(display.width)
                    let canvasW = Int(Double(display.width) * scale)
                    let canvasH = Int(Double(display.height) * scale)

                    for space in job.targets {
                        var layers: [(CGImage, CGRect)] = []
                        for win in space.windows.reversed() {
                            guard let scWindow = byID[Int(win.id)] else { continue }
                            let f = scWindow.frame
                            guard f.width > 1, f.height > 1 else { continue }
                            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                            let config = SCStreamConfiguration()
                            config.width = max(8, Int(f.width * scale))
                            config.height = max(8, Int(f.height * scale))
                            config.showsCursor = false
                            config.capturesAudio = false
                            config.ignoreShadowsSingleWindow = true
                            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                                let rect = CGRect(x: (f.origin.x - display.frame.origin.x) * scale,
                                                  y: (f.origin.y - display.frame.origin.y) * scale,
                                                  width: f.width * scale,
                                                  height: f.height * scale)
                                layers.append((img, rect))
                            }
                        }
                        guard let composed = SpacesManager.compose(width: canvasW, height: canvasH, wallpaper: job.wallpaper, layers: layers) else { continue }
                        let image = NSImage(cgImage: composed, size: NSSize(width: canvasW, height: canvasH))
                        let sid = space.id
                        DispatchQueue.main.async { self?.thumbnails[sid] = image }
                    }
                }
            } catch {
                DispatchQueue.main.async { self?.lastError = error.localizedDescription }
            }
        }
    }

    private static func compose(width: Int, height: Int, wallpaper: NSImage?, layers: [(CGImage, CGRect)]) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
        ctx.fill(full)
        if let wp = wallpaper, let cg = wp.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let imgAspect = Double(cg.width) / Double(cg.height)
            let canvasAspect = Double(width) / Double(height)
            var drawRect = full
            if imgAspect > canvasAspect {
                let w = Double(height) * imgAspect
                drawRect = CGRect(x: (Double(width) - w) / 2, y: 0, width: w, height: Double(height))
            } else {
                let h = Double(width) / imgAspect
                drawRect = CGRect(x: 0, y: (Double(height) - h) / 2, width: Double(width), height: h)
            }
            ctx.draw(cg, in: drawRect)
        }
        for (img, rect) in layers {
            let flipped = CGRect(x: rect.origin.x,
                                 y: Double(height) - rect.origin.y - rect.height,
                                 width: rect.width,
                                 height: rect.height)
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: CGColor(gray: 0, alpha: 0.5))
            ctx.draw(img, in: flipped)
        }
        return ctx.makeImage()
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        captureTimer?.invalidate()
    }

    func refreshPermissions() {
        let sc = CGPreflightScreenCaptureAccess()
        let ax = AXIsProcessTrusted()
        let direct = DesktopHotkeys.allEnabled(count: max(1, min(9, spaces.filter { !$0.isFullscreen }.count)))
        if sc != hasScreenCapture { hasScreenCapture = sc }
        if ax != hasAccessibility { hasAccessibility = ax }
        if direct != directHotkeysEnabled { directHotkeysEnabled = direct }
    }

    func enableDirectHotkeys() {
        DesktopHotkeys.enable(count: 9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.refreshPermissions() }
    }

    func refresh() {
        let raw = CGSCopyManagedDisplaySpaces(cid).takeRetainedValue() as NSArray
        let active = CGSGetActiveSpace(cid)

        var built: [DisplaySpaces] = []
        var desktopCounter = 0
        for case let display as NSDictionary in raw {
            let ident = display["Display Identifier"] as? String ?? "Main"
            let list = display["Spaces"] as? [NSDictionary] ?? []
            var thisDisplaySpaces: [SpaceInfo] = []
            for entry in list {
                let type = (entry["type"] as? NSNumber)?.intValue ?? 0
                let id64 = (entry["id64"] as? NSNumber)?.uint64Value ?? 0
                let managed = (entry["ManagedSpaceID"] as? NSNumber)?.intValue ?? 0
                let uuid = entry["uuid"] as? String ?? ""
                let isFullscreen = type == 4
                var number: Int? = nil
                if !isFullscreen {
                    desktopCounter += 1
                    number = desktopCounter
                }
                thisDisplaySpaces.append(SpaceInfo(id: id64, managedID: managed, uuid: uuid, isFullscreen: isFullscreen, desktopNumber: number, displayUUID: ident))
            }
            let current = ((display["Current Space"] as? NSDictionary)?["id64"] as? NSNumber)?.uint64Value ?? active
            built.append(DisplaySpaces(uuid: ident, spaces: thisDisplaySpaces, activeSpaceID: current))
        }

        var all = built.flatMap(\.spaces)
        attachWindows(to: &all)
        for i in built.indices {
            built[i].spaces = all.filter { $0.displayUUID == built[i].uuid }
        }
        currentDisplays = built

        DispatchQueue.main.async {
            if self.displays != built { self.displays = built }
            if self.spaces != all { self.spaces = all }
            if self.activeSpaceID != active { self.activeSpaceID = active }
        }
    }

    static func uuid(for screen: NSScreen) -> String {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "Main" }
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value)) else { return "Main" }
        let uuid = uuidRef.takeRetainedValue()
        guard let str = CFUUIDCreateString(nil, uuid) else { return "Main" }
        return str as String
    }

    private func display(for screen: NSScreen) -> DisplaySpaces? {
        if displays.count == 1 { return displays.first }
        let uuid = SpacesManager.uuid(for: screen)
        return displays.first { $0.uuid == uuid }
    }

    func spaces(for screen: NSScreen) -> [SpaceInfo] {
        display(for: screen)?.spaces ?? spaces
    }

    func activeSpaceID(for screen: NSScreen) -> UInt64 {
        display(for: screen)?.activeSpaceID ?? activeSpaceID
    }

    private func activeSpace(of space: SpaceInfo) -> UInt64 {
        currentDisplays.first { $0.uuid == space.displayUUID }?.activeSpaceID ?? CGSGetActiveSpace(cid)
    }

    private func isNowActive(_ space: SpaceInfo) -> Bool {
        refresh()
        return activeSpace(of: space) == space.id
    }

    private func attachWindows(to spaces: inout [SpaceInfo]) {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        var bySpace: [UInt64: [SpaceWindow]] = [:]
        for w in windows {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = w[kCGWindowNumber as String] as? Int,
                  let pid = w[kCGWindowOwnerPID as String] as? Int,
                  let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }
            if pid_t(pid) == ownPID { continue }
            if excludedWindowNumbers.contains(wid) { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "universalAccessAuthWarn" || owner == "Window Server" || owner == "Dock" { continue }
            let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            if (bounds["Width"] ?? 0) < 80 || (bounds["Height"] ?? 0) < 60 { continue }
            let ids = CGSCopySpacesForWindows(cid, 0x7, [wid] as CFArray).takeRetainedValue() as NSArray
            if ids.count != 1 { continue }
            for case let sid as NSNumber in ids {
                bySpace[sid.uint64Value, default: []].append(SpaceWindow(id: CGWindowID(wid), pid: pid_t(pid)))
            }
        }
        for i in spaces.indices {
            spaces[i].windows = bySpace[spaces[i].id] ?? []
        }
    }

    // MARK: - Switching

    func switchTo(_ space: SpaceInfo) {
        refresh()
        let current = activeSpace(of: space)
        SpacesManager.debugLog?("switchTo \(space.title) id=\(space.id) active=\(current) ax=\(AXIsProcessTrusted())")
        guard space.id != current else { return }

        guard AXIsProcessTrusted() else {
            lastSwitch = .none
            SpacesManager.debugLog?("no Accessibility -> prompting, not switching")
            Permissions.requestAccessibilityIfNeeded()
            return
        }

        if space.isFullscreen, let win = space.windows.first {
            let raised = jumpToFullscreenWindow(in: space)
            if !raised { NSRunningApplication(processIdentifier: win.pid)?.activate() }
            lastSwitch = .hotkey
            SpacesManager.debugLog?("full-screen jump via \(raised ? "AXRaise" : "activate")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                let ok = self.isNowActive(space)
                SpacesManager.debugLog?("after=\(self.activeSpace(of: space)) ok=\(ok)")
                if !ok { self.switchByArrows(to: space) }
            }
            return
        }

        if isOnMainDisplay(space), let n = space.desktopNumber, n >= 1, n <= 9, DesktopHotkeys.isEnabled(n) {
            lastSwitch = .hotkey
            SpacesManager.debugLog?("ctrl+\(n) direct")
            KeyPoster.postControlDigit(n)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                let ok = self.isNowActive(space)
                SpacesManager.debugLog?("after=\(self.activeSpace(of: space)) ok=\(ok)")
            }
            return
        }

        switchByArrows(to: space)
    }

    private func isOnMainDisplay(_ space: SpaceInfo) -> Bool {
        if currentDisplays.count <= 1 || space.displayUUID == "Main" { return true }
        guard let main = NSScreen.screens.first else { return true }
        return SpacesManager.uuid(for: main) == space.displayUUID
    }

    private func ensureCursor(onDisplayOf space: SpaceInfo) {
        guard let screen = NSScreen.screens.first(where: { SpacesManager.uuid(for: $0) == space.displayUUID }),
              let primary = NSScreen.screens.first else { return }
        if screen.frame.contains(NSEvent.mouseLocation) { return }
        let target = CGPoint(x: screen.frame.midX, y: primary.frame.maxY - screen.frame.midY)
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
        SpacesManager.debugLog?("cursor moved to display \(screen.localizedName)")
    }

    private func switchByArrows(to space: SpaceInfo) {
        ensureCursor(onDisplayOf: space)
        let current = activeSpace(of: space)
        let list = currentDisplays.first { $0.uuid == space.displayUUID }?.spaces ?? spaces
        guard let from = list.firstIndex(where: { $0.id == current }),
              let to = list.firstIndex(where: { $0.id == space.id }) else {
            SpacesManager.debugLog?("index lookup failed")
            return
        }
        let delta = to - from
        guard delta != 0 else { return }
        let goRight = delta > 0
        let steps = abs(delta)
        lastSwitch = .hotkey
        SpacesManager.debugLog?("ctrl+\(goRight ? "right" : "left") x\(steps) (\(from) -> \(to))")
        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) {
                KeyPoster.postControlArrow(right: goRight)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 + Double(steps) * 0.25) { [weak self] in
            guard let self else { return }
            let ok = self.isNowActive(space)
            SpacesManager.debugLog?("after=\(self.activeSpace(of: space)) ok=\(ok)")
        }
    }

    private func jumpToFullscreenWindow(in space: SpaceInfo) -> Bool {
        for win in space.windows {
            let appElement = AXUIElementCreateApplication(win.pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let axWindows = value as? [AXUIElement] else { continue }
            for axWindow in axWindows {
                var wid: CGWindowID = 0
                guard _AXUIElementGetWindow(axWindow, &wid) == .success, wid == win.id else { continue }
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                NSRunningApplication(processIdentifier: win.pid)?.activate()
                return true
            }
        }
        return false
    }

    // MARK: - Thumbnails

    func captureActiveSpace() {
        guard !captureInFlight, CGPreflightScreenCaptureAccess() else { return }
        captureInFlight = true
        refresh()
        let targets = currentDisplays.map { ($0.displayID, $0.activeSpaceID) }
        let excluded = excludedWindowNumbers

        Task { [weak self] in
            defer { DispatchQueue.main.async { self?.captureInFlight = false } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let excludedWindows = content.windows.filter { excluded.contains(Int($0.windowID)) }
                for (displayID, spaceID) in targets {
                    guard let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }
                    let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                    let config = SCStreamConfiguration()
                    let scale = 720.0 / Double(display.width)
                    config.width = Int(Double(display.width) * scale)
                    config.height = Int(Double(display.height) * scale)
                    config.showsCursor = false
                    config.capturesAudio = false
                    guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
                    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    DispatchQueue.main.async {
                        self?.thumbnails[spaceID] = image
                    }
                }
            } catch {
                DispatchQueue.main.async { self?.lastError = error.localizedDescription }
            }
        }
    }
}

enum DesktopHotkeys {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    private static let digitKeyCodes: [Int] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    static func isEnabled(_ n: Int) -> Bool {
        guard n >= 1, n <= 9,
              let dict = CFPreferencesCopyAppValue(key, domain) as? [String: Any],
              let entry = dict["\(117 + n)"] as? [String: Any] else { return false }
        if let b = entry["enabled"] as? Bool { return b }
        if let i = entry["enabled"] as? Int { return i != 0 }
        return false
    }

    static func allEnabled(count: Int) -> Bool {
        (1...count).allSatisfy { isEnabled($0) }
    }

    static func enable(count: Int) {
        var dict = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
        for n in 1...min(count, 9) {
            let keyCode = digitKeyCodes[n - 1]
            dict["\(117 + n)"] = [
                "enabled": true,
                "value": [
                    "parameters": [48 + n, keyCode, 262144],
                    "type": "standard"
                ]
            ]
        }
        CFPreferencesSetAppValue(key, dict as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        task.arguments = ["-u"]
        try? task.run()
    }
}

enum KeyPoster {
    private static let digitKeyCodes: [Int: CGKeyCode] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25
    ]

    static func postControlDigit(_ n: Int) {
        guard let digit = digitKeyCodes[n] else { return }
        let control: CGKeyCode = 59
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: control, keyDown: true),
              let down = CGEvent(keyboardEventSource: src, virtualKey: digit, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: digit, keyDown: false),
              let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: control, keyDown: false) else { return }
        ctrlDown.flags = .maskControl
        down.flags = .maskControl
        up.flags = .maskControl
        ctrlUp.flags = []
        ctrlDown.post(tap: .cgSessionEventTap)
        usleep(20_000)
        down.post(tap: .cgSessionEventTap)
        usleep(20_000)
        up.post(tap: .cgSessionEventTap)
        usleep(20_000)
        ctrlUp.post(tap: .cgSessionEventTap)
    }

    static func postControlArrow(right: Bool) {
        let arrow: CGKeyCode = right ? 124 : 123
        let control: CGKeyCode = 59
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: control, keyDown: true),
              let down = CGEvent(keyboardEventSource: src, virtualKey: arrow, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: arrow, keyDown: false),
              let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: control, keyDown: false) else { return }
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        ctrlDown.flags = .maskControl
        down.flags = arrowFlags
        up.flags = arrowFlags
        ctrlUp.flags = []
        ctrlDown.post(tap: .cgSessionEventTap)
        usleep(20_000)
        down.post(tap: .cgSessionEventTap)
        usleep(20_000)
        up.post(tap: .cgSessionEventTap)
        usleep(20_000)
        ctrlUp.post(tap: .cgSessionEventTap)
    }
}
