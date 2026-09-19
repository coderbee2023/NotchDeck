import AppKit
import SwiftUI
import Combine

final class PermissionStatus: ObservableObject {
    @Published var accessibility = false
    @Published var screenRecording = false
    @Published var automation: Bool? = nil
    @Published var hotkeys = false
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        hotkeys = DesktopHotkeys.allEnabled(count: 9)
        automation = PermissionStatus.automationState()
    }

    static func automationState() -> Bool? {
        let players: [MusicPlayer] = [.spotify, .appleMusic]
        var sawRunning = false
        for p in players where p.isRunning {
            sawRunning = true
            let target = NSAppleEventDescriptor(bundleIdentifier: p.rawValue)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
            if status == noErr { return true }
        }
        return sawRunning ? false : nil
    }

    func requestAccessibility() {
        Permissions.requestAccessibilityIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !AXIsProcessTrusted() {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    func requestScreenRecording() {
        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
        }
    }

    func requestAutomation() {
        for p in [MusicPlayer.spotify, .appleMusic] where p.isRunning {
            let target = NSAppleEventDescriptor(bundleIdentifier: p.rawValue)
            _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
            if self?.automation == false {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
        }
    }
}

final class OnboardingWindowController {
    private var window: NSWindow?
    private let state: DeckState

    init(state: DeckState) { self.state = state }

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarded") }
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView:
                OnboardingView(onDone: { [weak self] in
                    OnboardingWindowController.hasCompleted = true
                    self?.window?.close()
                })
                .environmentObject(state)
                .environmentObject(state.settings)
            )
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var state: DeckState
    @EnvironmentObject var settings: DeckSettings
    @StateObject private var perms = PermissionStatus()
    let onDone: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.02), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [settings.accent.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 420)
                .blendMode(.screen)

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 84, height: 84)
                        .shadow(color: settings.accent.opacity(0.35), radius: 24, y: 8)
                    Text("Welcome to NotchDeck")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Your notch becomes a deck: Spaces, Music and System, one hover away.\nA few permissions make it work.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.top, 34)
                .padding(.bottom, 22)

                VStack(spacing: 10) {
                    PermissionCard(symbol: "hand.raised.fill",
                                   title: "Accessibility",
                                   detail: "Lets NotchDeck press the Mission Control shortcuts that jump to a desktop.",
                                   granted: perms.accessibility,
                                   action: { perms.requestAccessibility() })
                    PermissionCard(symbol: "rectangle.dashed.badge.record",
                                   title: "Screen Recording",
                                   detail: "Live previews of every desktop in the Spaces tab. Nothing leaves your Mac.",
                                   granted: perms.screenRecording,
                                   action: { perms.requestScreenRecording() })
                    PermissionCard(symbol: "music.note",
                                   title: "Automation · Spotify & Apple Music",
                                   detail: perms.automation == nil ? "Asked the first time you control playback. Open Spotify or Music to grant it now." : "Play, skip, seek and volume from the Music tab.",
                                   granted: perms.automation == true,
                                   pending: perms.automation == nil,
                                   action: { perms.requestAutomation() })
                    PermissionCard(symbol: "keyboard",
                                   title: "Direct desktop jumps  ⌃1 – ⌃9",
                                   detail: "Enables the built-in “Switch to Desktop n” shortcuts so clicks land instantly instead of sliding.",
                                   granted: perms.hotkeys,
                                   buttonTitle: "Enable",
                                   action: { state.spaces.enableDirectHotkeys(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { perms.refresh() } })
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    Button { settings.setLaunchAtLogin(!settings.launchAtLogin) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: settings.launchAtLogin ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(settings.launchAtLogin ? settings.accent : .white.opacity(0.4))
                            Text("Launch at login").foregroundStyle(.white.opacity(0.8))
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Hover the notch · ⌃⌥Space")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                    Button(action: onDone) {
                        Text(allGranted ? "Get started" : "Continue anyway")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(allGranted ? settings.onAccent : .white)
                            .padding(.horizontal, 18)
                            .frame(height: 34)
                            .background(Capsule().fill(allGranted ? settings.accent : Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 560, height: 620)
        .onAppear { perms.start(); settings.refreshLaunchAtLogin() }
        .onDisappear { perms.stop() }
    }

    private var allGranted: Bool { perms.accessibility && perms.screenRecording }
}

struct PermissionCard: View {
    @EnvironmentObject var settings: DeckSettings
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    var pending: Bool = false
    var buttonTitle: String = "Allow"
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(granted ? settings.accent.opacity(0.18) : Color.white.opacity(0.07))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(granted ? settings.accent : .white.opacity(0.85))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            if granted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Granted")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.accent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(settings.accent.opacity(0.14)))
            } else {
                Button(action: action) {
                    Text(pending ? "Grant" : buttonTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(hovering ? 1 : 0.9)))
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(granted ? settings.accent.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: granted)
    }
}
