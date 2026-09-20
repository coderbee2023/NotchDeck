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

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(_ cid: Int32, _ display: CFString, _ space: UInt64)

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
    // Stable left-to-right order of the tiles, keyed by space id. macOS reshuffles its own
    // Space order on use ("Automatically rearrange Spaces based on most recent use"); we keep
    // the deck's tiles put by remembering the first order we saw and appending new spaces at
    // the end. The per-space `desktopNumber` still tracks the live Mission Control position,
    // so Ctrl+N goes to the right desktop regardless of where its tile sits.
    private var spaceOrder: [UInt64] = []
    // Space ids we hold a REAL screenshot for — captured by `captureActiveSpace` while the
    // space was actually on screen. The reconstructed composite (`captureAllSpaces`) must
    // never overwrite these, otherwise a good thumbnail from your last visit gets clobbered
    // by a worse, stale reconstruction (the "it reverts to the initial image" bug).
    private var realThumbnailIDs: Set<UInt64> = []
    private var observers: [NSObjectProtocol] = []
    private var captureInFlight = false
    private var captureTimer: Timer?
    private var compositeInFlight = false
    private var compositeTimer: Timer?
    var isDeckOpen = false {
        didSet {
            guard isDeckOpen, !oldValue else { return }
            captureActiveSpace()
            captureAllSpaces()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, self.isDeckOpen else { return }
                self.captureAllSpaces()
            }
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
        compositeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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
        // Forget real-screenshot marks for spaces that no longer exist, then snapshot the set:
        // any space we already have a live screenshot of is left untouched by the composite.
        let presentIDs = Set(currentDisplays.flatMap { $0.spaces.map(\.id) })
        realThumbnailIDs.formIntersection(presentIDs)
        let realIDs = realThumbnailIDs
        var jobs: [(displayID: CGDirectDisplayID, wallpaper: NSImage?, targets: [SpaceInfo])] = []
        for d in currentDisplays {
            let targets = d.spaces.filter { $0.id != d.activeSpaceID && !realIDs.contains($0.id) }
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
                        if layers.isEmpty, !space.windows.isEmpty {
                            let sid = space.id
                            let hasExisting = await MainActor.run { self?.thumbnails[sid] != nil }
                            if hasExisting { continue }
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

        // Keep tile positions stable across macOS's own reshuffling: drop ids that vanished,
        // append freshly-created ones in their current order, then sort everything by this
        // remembered order.
        let presentIDs = all.map(\.id)
        spaceOrder.removeAll { !presentIDs.contains($0) }
        for id in presentIDs where !spaceOrder.contains(id) { spaceOrder.append(id) }
        let orderIndex = Dictionary(spaceOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        all.sort { (orderIndex[$0.id] ?? .max) < (orderIndex[$1.id] ?? .max) }

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
            guard ids.count > 0 else { continue }
            // A window can legitimately belong to several spaces (assigned to all desktops,
            // or shown on every display). Dropping those left busy desktops looking empty.
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
        let leavingFullscreen = currentDisplays.first { $0.uuid == space.displayUUID }?
            .spaces.first { $0.id == current }?.isFullscreen ?? false
        SpacesManager.debugLog?("switchTo \(space.title) id=\(space.id) active=\(current) fs=\(space.isFullscreen) leavingFS=\(leavingFullscreen)")
        guard space.id != current else { return }
        lastSwitch = .hotkey

        if space.isFullscreen {
            // Full-screen → pin its exact space id, then activate its app to composite it in.
            // The pin is the only thing that tells two full-screen windows of the same app apart.
            jumpToFullscreen(to: space)
            return
        }

        guard let n = space.desktopNumber, n >= 1, n <= 9 else { return }

        // Leaving a full-screen space straight onto an EMPTY desktop leaves the WindowServer
        // showing the space we came from — the empty desktop has nothing of its own to paint.
        // (A desktop that has real app windows paints itself and is fine, so we skip the bounce
        // there.) A desktop→desktop jump always repaints cleanly, so for the empty case we hop
        // through another desktop first. Costs one brief blur-through, only in this exact case.
        if leavingFullscreen, !desktopHasOwnWindow(space),
           let hop = intermediateDesktopNumber(avoiding: space), hop != n {
            // Fire the second jump while the first is still animating so macOS blurs straight
            // through the intermediate desktop. postControlDigit itself takes ~60ms to emit,
            // so the gap has to clear that plus a margin or the second press is dropped mid-jump.
            SpacesManager.debugLog?("leaving fullscreen via ctrl+\(hop) -> ctrl+\(n)")
            KeyPoster.postControlDigit(hop)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                KeyPoster.postControlDigit(n)
            }
        } else {
            SpacesManager.debugLog?("switch via ctrl+\(n)")
            KeyPoster.postControlDigit(n)
        }
    }

    /// Whether a desktop paints itself when reached from a full-screen space. True when it has
    /// a real (.regular) app window that lives on this desktop alone — that window is the
    /// desktop's own content and renders it. A window pinned to every desktop doesn't count
    /// (it isn't drawn as this desktop's content), and a bare desktop has nothing; those need
    /// the bounce to render, everything else does not.
    private func desktopHasOwnWindow(_ space: SpaceInfo) -> Bool {
        let desktops = (currentDisplays.first { $0.uuid == space.displayUUID }?.spaces ?? [])
            .filter { !$0.isFullscreen }
        var spacesPerWindow: [CGWindowID: Int] = [:]
        for d in desktops { for w in d.windows { spacesPerWindow[w.id, default: 0] += 1 } }
        return space.windows.contains { w in
            spacesPerWindow[w.id] == 1 && w.pid != ownPID &&
            NSRunningApplication(processIdentifier: w.pid)?.activationPolicy == .regular
        }
    }

    /// Desktop number to bounce through when leaving a full-screen space — prefer a populated
    /// desktop (one with a real app window) so the intermediate frame itself looks right, else
    /// any other desktop. Returns nil when there is no other desktop to use.
    private func intermediateDesktopNumber(avoiding target: SpaceInfo) -> Int? {
        let desktops = (currentDisplays.first { $0.uuid == target.displayUUID }?.spaces ?? [])
            .filter { !$0.isFullscreen && $0.id != target.id }
        let populated = desktops.first { d in
            d.windows.contains { $0.pid != ownPID && NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular }
        }
        if let n = (populated ?? desktops.first)?.desktopNumber, n >= 1, n <= 9 { return n }
        return nil
    }

    /// Reach a specific full-screen space. `CGSManagedDisplaySetCurrentSpace` pins the exact
    /// space — the only way to tell two full-screen windows of the same app apart — and then
    /// activating the app brings its window for this space forward so it composites cleanly
    /// (the pin on its own leaves the previous space's window overlaid on top).
    private func jumpToFullscreen(to space: SpaceInfo) {
        let ident = currentDisplays.first { $0.uuid == space.displayUUID }?.uuid ?? space.displayUUID
        SpacesManager.debugLog?("fullscreen jump id=\(space.id) display=\(ident)")
        CGSManagedDisplaySetCurrentSpace(cid, ident as CFString, space.id)
        guard let win = space.windows.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.activate(pid: win.pid)
        }
    }

    /// Bring an app forward reliably. NotchDeck is an accessory (LSUIElement) app, and
    /// `NSRunningApplication.activate()` from an accessory is merely advisory — macOS often
    /// defers it, so the space never changes. Re-opening the bundle with `activates: true`
    /// is the forceful nudge that actually pulls the app (and its space) to the front; it is
    /// the same lever the full-screen path relies on.
    private func activate(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
        guard let url = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
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
                        self?.realThumbnailIDs.insert(spaceID)
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

    static func postCommandV() {
        let cmd: CGKeyCode = 55, v: CGKeyCode = 9
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmd, keyDown: true),
              let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmd, keyDown: false) else { return }
        cmdDown.flags = .maskCommand
        down.flags = .maskCommand
        up.flags = .maskCommand
        cmdUp.flags = []
        cmdDown.post(tap: .cgSessionEventTap)
        usleep(15_000)
        down.post(tap: .cgSessionEventTap)
        usleep(15_000)
        up.post(tap: .cgSessionEventTap)
        usleep(15_000)
        cmdUp.post(tap: .cgSessionEventTap)
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
