import AppKit
import SwiftUI

@main
struct NotchDeckMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: PanelManager!
    private var statusItem: NSStatusItem!
    private let state = DeckState()
    private var debugBridge: DebugBridge?
    private var onboarding: OnboardingWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {

        panels = PanelManager(state: state)
        onboarding = OnboardingWindowController(state: state)

        setupStatusItem()

        state.spaces.start()
        state.music.start()
        state.stats.start()
        state.clipboard.start()
        state.faceEvents.start(stats: state.stats)
        state.lyrics.start(music: state.music, settings: state.settings)
        state.weather.start(settings: state.settings)
        state.glowSource.start(music: state.music)
        state.songVibe.start(music: state.music, glow: state.glowSource, lyrics: state.lyrics)
        state.focus.start()
        if state.settings.focusIndicator { state.focus.requestAccessIfNeeded() }
        SoundKit.enabled = { [weak state] in state?.settings.sounds ?? false }
        state.menuProvider = { [weak self] in self?.statusItem.menu }

        if !OnboardingWindowController.hasCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.onboarding.show() }
        }

        #if DEBUG
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Projects/NotchDeck")
        if FileManager.default.fileExists(atPath: dir.path) {
            debugBridge = DebugBridge(state: state, panels: panels, directory: dir)
            SpacesManager.debugLog = { [weak self] in self?.debugBridge?.log($0) }
            debugBridge?.start()
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stats.stopKeepAwake()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchDeck")

        let menu = NSMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        menu.addItem(withTitle: "About NotchDeck \(version)", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Welcome & Permissions…", action: #selector(showOnboarding), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Refresh Spaces", action: #selector(refreshSpaces), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Screen Recording Settings", action: #selector(openScreenRecording), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Mission Control Shortcuts", action: #selector(openKeyboardShortcuts), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showOnboarding() { onboarding.show() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Your notch, upgraded.\nSpaces · Music · System — one hover away.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
            .applicationName: "NotchDeck"
        ])
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(URL(string: "https://notchdeck-kappa.vercel.app/#download")!)
    }

    @objc private func refreshSpaces() {
        state.spaces.refresh()
        state.spaces.captureActiveSpace()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecording() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func openKeyboardShortcuts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!)
    }
}

final class DeckState: ObservableObject {
    let spaces = SpacesManager()
    let music = MusicController()
    let stats = SystemStats()
    let settings = DeckSettings()
    let audio = AudioLevelMonitor()
    let clipboard = ClipboardManager()
    let timer = TimerManager()
    let shelf = ShelfManager()
    let faceEvents = FaceEvents()
    let lyrics = LyricsController()
    let weather = WeatherController()
    let glowSource = GlowSource()
    let songVibe = SongVibeController()
    let focus = FocusMonitor()
    @Published var chargePing = 0
    var menuProvider: (() -> NSMenu?)?
    static let pageCount = 7
}

enum Permissions {
    static func requestAccessibilityIfNeeded() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
    }

    static func requestScreenCaptureIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }
}
