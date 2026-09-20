import AppKit
import Combine
import Intents

/// Reports whether a Focus (or Do Not Disturb) is currently on.
///
/// This uses the public Focus-status API rather than the files in ~/Library/DoNotDisturb:
/// that folder is protected and reading it would mean asking for Full Disk Access, which is
/// far too much to ask for a moon glyph. The trade-off is that macOS only tells us *whether*
/// a Focus is on, not which one.
final class FocusMonitor: ObservableObject {
    @Published private(set) var isOn = false
    /// False when the user has not allowed Focus sharing, so the UI can explain itself.
    @Published private(set) var readable = false

    private var timer: Timer?
    private var asked = false

    var authorizationStatus: INFocusStatusAuthorizationStatus {
        INFocusStatusCenter.default.authorizationStatus
    }

    func start() {
        refreshAuthorization()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Only prompts once, and only when the feature is actually switched on.
    func requestAccessIfNeeded() {
        guard !asked, INFocusStatusCenter.default.authorizationStatus == .notDetermined else { return }
        asked = true
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshAuthorization()
                self?.poll()
            }
        }
    }

    private func refreshAuthorization() {
        let allowed = INFocusStatusCenter.default.authorizationStatus == .authorized
        if readable != allowed { readable = allowed }
        if allowed {
            poll()
        } else if isOn {
            isOn = false
        }
    }

    private func poll() {
        guard INFocusStatusCenter.default.authorizationStatus == .authorized else {
            if isOn { isOn = false }
            if readable { readable = false }
            return
        }
        if !readable { readable = true }
        let focused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        if focused != isOn { isOn = focused }
    }
}
