import AppKit

/// Very small, very quiet feedback sounds. Off unless the user turns them on.
enum DeckSound: String {
    case open, close, drop, pin, paste, timerDone

    fileprivate var systemName: String {
        switch self {
        case .open: return "Tink"
        case .close: return "Tink"
        case .drop: return "Pop"
        case .pin: return "Morse"
        case .paste: return "Tink"
        case .timerDone: return "Glass"
        }
    }

    fileprivate var volume: Float {
        switch self {
        case .open: return 0.18
        case .close: return 0.12
        case .drop: return 0.35
        case .pin: return 0.2
        case .paste: return 0.22
        case .timerDone: return 0.7
        }
    }
}

enum SoundKit {
    /// Set once at startup so callers don't each need the settings object.
    static var enabled: () -> Bool = { false }

    private static var cache: [String: NSSound] = [:]
    private static var lastPlayed = Date.distantPast

    static func play(_ sound: DeckSound, force: Bool = false) {
        guard force || enabled() else { return }
        // Never machine-gun: one sound per 120ms is plenty.
        guard Date().timeIntervalSince(lastPlayed) > 0.12 else { return }
        lastPlayed = Date()

        let cached: NSSound?
        if let existing = cache[sound.systemName] {
            cached = existing.copy() as? NSSound
        } else if let created = NSSound(named: sound.systemName) {
            cache[sound.systemName] = created
            cached = created.copy() as? NSSound
        } else {
            cached = nil
        }
        guard let player = cached else { return }
        player.volume = sound.volume
        player.play()
    }
}
