import AppKit
import SwiftUI
import Combine

struct NotchMetrics {
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasRealNotch: Bool

    static let expandedSize = CGSize(width: 720, height: 350)
    static let collapsedExtraWidth: CGFloat = 0

    init(screen: NSScreen) {
        self.screen = screen
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasRealNotch = true
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = top
        } else {
            hasRealNotch = false
            notchWidth = 160
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchHeight = max(24, min(menuBar, 32))
        }
    }

    /// Wide enough for the face, a charge or timer line and the now-playing pill at once.
    /// The extra width is fully transparent and passes clicks through.
    // Extra height below the notch leaves room for the collapsed lyric strip. The area is
    // transparent and passes clicks through unless the notch itself is hovered, so it never
    // blocks whatever sits under the notch.
    var collapsedSize: CGSize { CGSize(width: notchWidth + 320, height: notchHeight + 58) }

    var collapsedPanelFrame: NSRect {
        let s = collapsedSize
        return NSRect(x: screen.frame.midX - s.width / 2,
                      y: screen.frame.maxY - s.height,
                      width: s.width,
                      height: s.height)
    }

    var panelFrame: NSRect {
        let s = NotchMetrics.expandedSize
        return NSRect(x: screen.frame.midX - s.width / 2,
                      y: screen.frame.maxY - s.height,
                      width: s.width,
                      height: s.height)
    }

    var notchRectOnScreen: NSRect {
        NSRect(x: screen.frame.midX - notchWidth / 2,
               y: screen.frame.maxY - notchHeight,
               width: notchWidth,
               height: notchHeight)
    }

    var expandedRectOnScreen: NSRect { panelFrame }
}

final class PanelState: ObservableObject {
    @Published var isExpanded = false
    @Published var page = 0
    @Published var volumeFlash: Double?
    /// True while the pointer is over/near the collapsed notch — the lyric strip ducks out so
    /// the notch shrinks back to normal before it can hide or intercept anything.
    @Published var notchHovered = false
    var pinned = false
    var suppressHover = false
    var hitRect: CGRect?
    var collapseHandler: (() -> Void)?
    var expandHandler: (() -> Void)?
    var debugInfo: (() -> String)?
}

final class PanelManager {
    private let state: DeckState
    private(set) var panels: [NotchPanel] = []
    private var audioTimer: Timer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var rebuildItem: DispatchWorkItem?

    init(state: DeckState) {
        self.state = state
        rebuild()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        startKeyMonitors()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateAudioMonitor() }
        RunLoop.main.add(audioTimer!, forMode: .common)
    }

    func updateAudioMonitor() {
        let want = state.settings.waveWithMusic && state.settings.glowBorder && (state.music.nowPlaying?.isPlaying ?? false) && !anyExpanded
        if want && !state.audio.isRunning { state.audio.start() }
        if !want && state.audio.isRunning { state.audio.stop() }
    }

    var primary: NotchPanel? {
        panels.first(where: { $0.metrics.hasRealNotch }) ?? panels.first
    }

    var anyExpanded: Bool { panels.contains { $0.ui.isExpanded } }

    func panelUnderMouse() -> NotchPanel? {
        let mouse = NSEvent.mouseLocation
        return panels.first(where: { $0.metrics.screen.frame.contains(mouse) }) ?? primary
    }

    func rebuild() {
        for p in panels { p.orderOut(nil); p.close() }
        panels = NSScreen.screens.map { screen in
            let panel = NotchPanel(state: state, manager: self, screen: screen)
            panel.orderFrontRegardless()
            return panel
        }
        state.spaces.excludedWindowNumbers = Set(panels.map(\.windowNumber))
    }

    @objc private func screenChanged() {
        rebuildItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.rebuild() }
        rebuildItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func deckOpenStateChanged() {
        updateAudioMonitor()
        let open = anyExpanded
        state.music.isForeground = open
        state.spaces.isDeckOpen = open
        if open {
            state.music.poll()
            state.spaces.refresh()
            state.spaces.captureActiveSpace()
        }
    }

    private func startKeyMonitors() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkey(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, let open = self.panels.first(where: { $0.ui.isExpanded }) {
                open.collapse()
                return nil
            }
            if self.handleHotkey(event) { return nil }
            return event
        }
    }

    @discardableResult
    private func handleHotkey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 49, mods == [.control, .option] else { return false }
        if let open = panels.first(where: { $0.ui.isExpanded }) {
            open.collapse()
        } else {
            panelUnderMouse()?.expand(pinned: true)
        }
        return true
    }
}

final class NotchPanel: NSPanel {
    static let dragLevel = NSWindow.Level.popUpMenu
    private let state: DeckState
    private weak var manager: PanelManager?
    let ui = PanelState()
    let metrics: NotchMetrics
    private var hoverTimer: Timer?
    private var hoverEnteredAt: Date?
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var hostingView: FirstMouseHostingView?
    private var dropContainer: DropContainerView?

    init(state: DeckState, manager: PanelManager, screen: NSScreen) {
        self.state = state
        self.manager = manager
        self.metrics = NotchMetrics(screen: screen)

        super.init(contentRect: metrics.collapsedPanelFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none

        let hosting = FirstMouseHostingView(rootView: AnyView(
            DeckView(music: state.music, timer: state.timer, shelf: state.shelf, glow: state.glowSource, focus: state.focus, vibe: state.songVibe, metrics: metrics)
                .environmentObject(state)
                .environmentObject(state.settings)
                .environmentObject(state.audio)
                .environmentObject(ui)
        ))
        hosting.frame = NSRect(origin: .zero, size: metrics.collapsedPanelFrame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.hitProvider = { [weak self] in self?.ui.hitRect }

        let container = DropContainerView(frame: NSRect(origin: .zero, size: metrics.collapsedPanelFrame.size))
        container.autoresizesSubviews = true
        container.addSubview(hosting)
        container.onDragEnter = { [weak self] in
            guard let self else { return }
            self.state.shelf.isDragTarget = true
            if !self.ui.isExpanded { self.expand(pinned: true) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { self.ui.page = 3 }
        }
        container.onDragExit = { [weak self] in
            self?.state.shelf.isDragTarget = false
        }
        container.onDropURLs = { [weak self] urls in
            guard let self else { return false }
            self.state.shelf.isDragTarget = false
            guard !urls.isEmpty else { return false }
            self.state.shelf.add(urls: urls)
            SoundKit.play(.drop)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { self.ui.page = 3 }
            return true
        }
        contentView = container
        dropContainer = container
        hostingView = hosting

        ui.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.manager?.deckOpenStateChanged()
            }
            .store(in: &cancellables)

        ui.collapseHandler = { [weak self] in self?.collapse() }
        ui.expandHandler = { [weak self] in self?.expand(pinned: true) }
        ui.debugInfo = { [weak self] in
            guard let self else { return "no panel" }
            return "screen=\(self.metrics.screen.localizedName) notch=\(self.metrics.hasRealNotch) visible=\(self.isVisible) onActiveSpace=\(self.isOnActiveSpace) frame=\(self.frame) mouse=\(NSEvent.mouseLocation) hot=\(self.liveRectOnScreen.map { NSStringFromRect($0) } ?? NSStringFromRect(self.metrics.notchRectOnScreen)) expanded=\(self.ui.isExpanded) hit=\(self.ui.hitRect.map { NSStringFromRect($0) } ?? "all") passthrough=\(self.ignoresMouseEvents) audio=\(self.state.audio.isRunning) level=\(String(format: "%.2f", self.state.audio.level))"
        }

        startHoverTracking()
        startGestureMonitor()
    }

    deinit {
        hoverTimer?.invalidate()
        if let m = gestureMonitor { NSEvent.removeMonitor(m) }
    }

    func expand(pinned: Bool = false) {
        guard !ui.isExpanded else { ui.pinned = pinned; return }
        ui.pinned = pinned
        ignoresMouseEvents = false
        SoundKit.play(.open)
        setFrame(metrics.panelFrame, display: true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            ui.isExpanded = true
        }
    }

    func collapse() {
        if ui.isExpanded { SoundKit.play(.close) }
        ui.pinned = false
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            ui.isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.ui.isExpanded else { return }
            self.setFrame(self.metrics.collapsedPanelFrame, display: true)
        }
    }

    private var gestureMonitor: Any?
    private var gestureAccumulator: CGFloat = 0
    private var gestureFired = false
    private var wheelResetItem: DispatchWorkItem?

    private func startGestureMonitor() {
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self, event.window === self else { return event }
            if event.type == .scrollWheel, self.state.settings.scrollVolume,
               abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
               event.momentumPhase == [],
               self.scrollBelongsToNotch(event) {
                self.adjustVolume(with: event)
                return nil
            }
            guard self.ui.isExpanded else { return event }
            return self.handleGesture(event)
        }
    }

    private func handleGesture(_ event: NSEvent) -> NSEvent? {
        if event.type == .swipe {
            if event.deltaX > 0 { turnPage(+1) } else if event.deltaX < 0 { turnPage(-1) }
            return nil
        }

        if event.momentumPhase != [] { return nil }

        if event.phase == .began || event.phase == .mayBegin {
            gestureAccumulator = 0
            gestureFired = false
            return nil
        }
        if event.phase == .ended || event.phase == .cancelled {
            gestureAccumulator = 0
            gestureFired = false
            return nil
        }

        if abs(event.scrollingDeltaX) < abs(event.scrollingDeltaY) { return event }

        gestureAccumulator += event.scrollingDeltaX

        if event.phase == [] {
            wheelResetItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.gestureAccumulator = 0
                self?.gestureFired = false
            }
            wheelResetItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }

        if !gestureFired {
            if gestureAccumulator < -40 {
                gestureFired = true
                turnPage(+1)
            } else if gestureAccumulator > 40 {
                gestureFired = true
                turnPage(-1)
            }
        }
        return nil
    }

    private func turnPage(_ delta: Int) {
        let next = max(0, min(DeckState.pageCount - 1, ui.page + delta))
        guard next != ui.page else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            ui.page = next
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        guard !ui.isExpanded, let menu = state.menuProvider?() else { super.rightMouseDown(with: event); return }
        menu.popUp(positioning: nil, at: event.locationInWindow, in: contentView)
    }

    private func scrollBelongsToNotch(_ event: NSEvent) -> Bool {
        if ui.isExpanded {
            return event.locationInWindow.y > frame.height - (metrics.notchHeight + 12)
        }
        guard let rect = ui.hitRect else { return true }
        return rect.insetBy(dx: -2, dy: -2).contains(event.locationInWindow)
    }

    private func adjustVolume(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 60 : event.scrollingDeltaY / 6
        let v = min(1, max(0, state.stats.outputVolume + delta))
        state.stats.setOutputVolume(v)
        ui.volumeFlash = v
        volumeFlashItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.ui.volumeFlash = nil }
        volumeFlashItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: item)
    }
    private var volumeFlashItem: DispatchWorkItem?

    static func preferredScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func startHoverTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickHover()
        }
        RunLoop.main.add(hoverTimer!, forMode: .common)
    }

    /// The visible notch in screen coordinates, or nil when the whole panel is live.
    private var liveRectOnScreen: CGRect? {
        guard !ui.isExpanded, let r = ui.hitRect else { return nil }
        let base = metrics.collapsedPanelFrame
        return CGRect(x: base.minX + r.minX, y: base.minY + r.minY, width: r.width, height: r.height)
            .insetBy(dx: -3, dy: -3)
    }

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var dragBaseline = 0
    private var mouseWasDown = false
    private var wasDragging = false

    /// True while the user is dragging something with the mouse held down.
    /// The baseline is refreshed on every idle tick, so a drag that starts and writes the
    /// drag pasteboard between two ticks is still caught.
    private func fileDragInProgress() -> Bool {
        let down = NSEvent.pressedMouseButtons & 1 != 0
        guard down else {
            mouseWasDown = false
            dragBaseline = dragPasteboard.changeCount
            return false
        }
        mouseWasDown = true
        return dragPasteboard.changeCount != dragBaseline
    }

    /// Clicks on the transparent part of the panel must reach whatever is underneath,
    /// but a drag has to be able to land anywhere on the deck.
    private func updatePassthrough(mouse: NSPoint) {
        let dragging = fileDragInProgress()
        let ignore: Bool
        if dragging {
            ignore = false
        } else if let live = liveRectOnScreen {
            ignore = !live.contains(mouse)
        } else {
            ignore = false
        }
        if ignoresMouseEvents != ignore { ignoresMouseEvents = ignore }
        if dragging != wasDragging {
            wasDragging = dragging
            hostingView?.dragPassthrough = dragging
            // Windows at .screenSaver are never offered drags, so drop to a level that is
            // still above the menu bar but inside the drag manager's reach.
            level = dragging ? NotchPanel.dragLevel : .screenSaver
        }
    }

    private func tickHover() {
        let mouse = NSEvent.mouseLocation
        updatePassthrough(mouse: mouse)
        if ui.isExpanded {
            if ui.notchHovered { ui.notchHovered = false }
            let rect = metrics.expandedRectOnScreen.insetBy(dx: -24, dy: -24)
            if rect.contains(mouse) {
                ui.pinned = false
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
            } else if ui.pinned || state.shelf.isDragTarget {
                return
            } else if collapseWorkItem == nil {
                let item = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    SoundKit.play(.close)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        self.ui.isExpanded = false
                    }
                    self.collapseWorkItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        guard let self, !self.ui.isExpanded else { return }
                        self.setFrame(self.metrics.collapsedPanelFrame, display: true)
                    }
                }
                collapseWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
            }
        } else {
            // Duck the lyric strip as soon as the pointer comes near the notch, independent of
            // whether hover-to-open is on, so the notch shrinks back before it hides anything.
            let near = (liveRectOnScreen ?? metrics.notchRectOnScreen).insetBy(dx: -24, dy: -16)
            let over = near.contains(mouse)
            if ui.notchHovered != over { ui.notchHovered = over }
            guard state.settings.openOnHover else { hoverEnteredAt = nil; return }
            let hot = liveRectOnScreen ?? metrics.notchRectOnScreen.insetBy(dx: -6, dy: -2)
            if hot.contains(mouse), !(manager?.anyExpanded ?? false) {
                guard !ui.suppressHover else { hoverEnteredAt = nil; return }
                if hoverEnteredAt == nil { hoverEnteredAt = Date() }
                guard Date().timeIntervalSince(hoverEnteredAt!) >= state.settings.hoverDelay else { return }
                hoverEnteredAt = nil
                setFrame(metrics.panelFrame, display: true)
                SoundKit.play(.open)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    ui.isExpanded = true
                }
            } else {
                hoverEnteredAt = nil
                ui.suppressHover = false
            }
        }
    }
}

final class DropContainerView: NSView {
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?
    var onDropURLs: (([URL]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let list = urls(from: sender)
        guard !list.isEmpty else { return [] }
        onDragEnter?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(from: sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return onDropURLs?(urls(from: sender)) ?? false
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

final class FirstMouseHostingView: NSHostingView<AnyView> {
    var hitProvider: (() -> CGRect?)?
    var dragPassthrough = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if dragPassthrough { return nil }
        if let rect = hitProvider?(), !rect.insetBy(dx: -2, dy: -2).contains(point) { return nil }
        return super.hitTest(point)
    }
}
