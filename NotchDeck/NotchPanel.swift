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

    var collapsedSize: CGSize { CGSize(width: notchWidth + 160, height: notchHeight + 24) }

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
    var pinned = false
    var collapseHandler: (() -> Void)?
    var expandHandler: (() -> Void)?
    var debugInfo: (() -> String)?
}

final class PanelManager {
    private let state: DeckState
    private(set) var panels: [NotchPanel] = []
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
    private let state: DeckState
    private weak var manager: PanelManager?
    let ui = PanelState()
    let metrics: NotchMetrics
    private var hoverTimer: Timer?
    private var hoverEnteredAt: Date?
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var hostingView: FirstMouseHostingView?

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
            DeckView(music: state.music, metrics: metrics)
                .environmentObject(state)
                .environmentObject(state.settings)
                .environmentObject(ui)
        ))
        hosting.frame = NSRect(origin: .zero, size: metrics.collapsedPanelFrame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        hostingView = hosting

        ui.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                self?.ignoresMouseEvents = !expanded
                self?.manager?.deckOpenStateChanged()
            }
            .store(in: &cancellables)

        ui.collapseHandler = { [weak self] in self?.collapse() }
        ui.expandHandler = { [weak self] in self?.expand(pinned: true) }
        ui.debugInfo = { [weak self] in
            guard let self else { return "no panel" }
            return "screen=\(self.metrics.screen.localizedName) notch=\(self.metrics.hasRealNotch) visible=\(self.isVisible) onActiveSpace=\(self.isOnActiveSpace) frame=\(self.frame) mouse=\(NSEvent.mouseLocation) hot=\(self.metrics.notchRectOnScreen) expanded=\(self.ui.isExpanded)"
        }

        startHoverTracking()
        startGestureMonitor()
    }

    deinit {
        hoverTimer?.invalidate()
        if let m = gestureMonitor { NSEvent.removeMonitor(m) }
    }

    func expand(pinned: Bool = false) {
        ui.pinned = pinned
        setFrame(metrics.panelFrame, display: true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            ui.isExpanded = true
        }
    }

    func collapse() {
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
            guard let self, self.ui.isExpanded, event.window === self else { return event }
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

    private func tickHover() {
        let mouse = NSEvent.mouseLocation
        if ui.isExpanded {
            let rect = metrics.expandedRectOnScreen.insetBy(dx: -24, dy: -24)
            if rect.contains(mouse) {
                ui.pinned = false
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
            } else if ui.pinned {
                return
            } else if collapseWorkItem == nil {
                let item = DispatchWorkItem { [weak self] in
                    guard let self else { return }
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
            guard state.settings.openOnHover else { hoverEnteredAt = nil; return }
            let pillShown = state.settings.pillNowPlaying && (state.music.nowPlaying?.isPlaying ?? false)
            let hot = metrics.notchRectOnScreen.insetBy(dx: pillShown ? -68 : -6, dy: -2)
            if hot.contains(mouse), !(manager?.anyExpanded ?? false) {
                if hoverEnteredAt == nil { hoverEnteredAt = Date() }
                guard Date().timeIntervalSince(hoverEnteredAt!) >= state.settings.hoverDelay else { return }
                hoverEnteredAt = nil
                setFrame(metrics.panelFrame, display: true)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    ui.isExpanded = true
                }
            } else {
                hoverEnteredAt = nil
            }
        }
    }
}

final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
