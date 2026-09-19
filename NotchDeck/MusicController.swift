import AppKit
import Combine
import CoreImage

enum MusicPlayer: String {
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"

    var appName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Music"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }
}

enum RepeatMode: String {
    case off, all, one
}

struct NowPlaying: Equatable {
    var player: MusicPlayer
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var artworkURL: String
    var position: Double
    var duration: Double
    var repeatMode: RepeatMode
    var shuffle: Bool
    var volume: Int

    var trackKey: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }
}

final class MusicController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage? {
        didSet { updateGlow() }
    }
    @Published private(set) var artworkGlow: NSImage?
    @Published private(set) var activePlayer: MusicPlayer?
    @Published private(set) var lastError: String?

    var isForeground = false {
        didSet { if isForeground != oldValue { restartTimer() } }
    }

    private var timer: Timer?
    private var artworkKey: String?
    private var artworkTask: URLSessionDataTask?
    private var localPosition: Double = 0
    private var lastPoll = Date()
    private var volumeHold = Date.distantPast

    func start() {
        poll()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval: TimeInterval = isForeground ? 1.0 : 5.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func poll() {
        let player = detectPlayer()
        activePlayer = player
        guard let player else {
            nowPlaying = nil
            artwork = nil
            artworkKey = nil
            return
        }
        guard let raw = runScript(statusScript(for: player)) else { return }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 10 else {
            lastError = "Unexpected reply from \(player.appName): \(raw.prefix(80))"
            return
        }
        lastError = nil

        let state = parts[0].lowercased()
        let durationRaw = Double(parts[6].replacingOccurrences(of: ",", with: ".")) ?? 0
        let duration = player == .spotify ? durationRaw / 1000.0 : durationRaw
        let repeatMode: RepeatMode
        switch parts[7].lowercased() {
        case "true", "all": repeatMode = .all
        case "one": repeatMode = .one
        default: repeatMode = .off
        }

        let np = NowPlaying(player: player,
                            isPlaying: state == "playing",
                            title: parts[1],
                            artist: parts[2],
                            album: parts[3],
                            artworkURL: parts[4],
                            position: Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0,
                            duration: duration,
                            repeatMode: repeatMode,
                            shuffle: parts[8].lowercased() == "true",
                            volume: Int(parts[9].replacingOccurrences(of: ",", with: ".").split(separator: ".").first ?? "0") ?? 0)
        var np2 = np
        if Date() < volumeHold, let cur = nowPlaying { np2.volume = cur.volume }
        if np2 != nowPlaying { nowPlaying = np2 }
        if np.trackKey != artworkKey {
            artworkKey = np.trackKey
            loadArtwork(for: np)
        }
    }

    private func detectPlayer() -> MusicPlayer? {
        let candidates: [MusicPlayer] = [.spotify, .appleMusic].filter { $0.isRunning }
        if candidates.isEmpty { return nil }
        for p in candidates {
            if let s = runScript("tell application \"\(p.appName)\" to return (player state as string)"), s.lowercased() == "playing" {
                return p
            }
        }
        return candidates.first
    }

    private func statusScript(for player: MusicPlayer) -> String {
        switch player {
        case .spotify:
            return """
            tell application "Spotify"
                set pState to (player state as string)
                try
                    set theTrack to current track
                    set tName to (name of theTrack)
                    set tArtist to (artist of theTrack)
                    set tAlbum to (album of theTrack)
                    set tArt to (artwork url of theTrack)
                    set tDur to ((duration of theTrack) as string)
                on error
                    set tName to ""
                    set tArtist to ""
                    set tAlbum to ""
                    set tArt to ""
                    set tDur to "0"
                end try
                set tPos to (player position as string)
                set tRep to (repeating as string)
                set tShuf to (shuffling as string)
                set tVol to (sound volume as string)
                return pState & linefeed & tName & linefeed & tArtist & linefeed & tAlbum & linefeed & tArt & linefeed & tPos & linefeed & tDur & linefeed & tRep & linefeed & tShuf & linefeed & tVol
            end tell
            """
        case .appleMusic:
            return """
            tell application "Music"
                set pState to (player state as string)
                try
                    set theTrack to current track
                    set tName to (name of theTrack)
                    set tArtist to (artist of theTrack)
                    set tAlbum to (album of theTrack)
                    set tDur to ((duration of theTrack) as string)
                on error
                    set tName to ""
                    set tArtist to ""
                    set tAlbum to ""
                    set tDur to "0"
                end try
                set tPos to (player position as string)
                set tRep to (song repeat as string)
                set tShuf to (shuffle enabled as string)
                set tVol to (sound volume as string)
                return pState & linefeed & tName & linefeed & tArtist & linefeed & tAlbum & linefeed & "" & linefeed & tPos & linefeed & tDur & linefeed & tRep & linefeed & tShuf & linefeed & tVol
            end tell
            """
        }
    }

    private func loadArtwork(for np: NowPlaying) {
        artworkTask?.cancel()
        switch np.player {
        case .spotify:
            guard let url = URL(string: np.artworkURL) else { artwork = nil; return }
            let key = np.trackKey
            artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self?.artworkKey == key { self?.artwork = img }
                }
            }
            artworkTask?.resume()
        case .appleMusic:
            let script = NSAppleScript(source: "tell application \"Music\" to return (data of artwork 1 of current track)")
            var err: NSDictionary?
            if let desc = script?.executeAndReturnError(&err), let img = NSImage(data: desc.data) {
                artwork = img
            } else {
                artwork = nil
            }
        }
    }

    private func updateGlow() {
        guard let img = artwork, let tiff = img.tiffRepresentation else { artworkGlow = nil; return }
        let key = artworkKey
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let ci = CIImage(data: tiff) else { return }
            let side: CGFloat = 200
            let scale = side / max(ci.extent.width, ci.extent.height)
            let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let blurred = scaled.applyingGaussianBlur(sigma: 34)
            let rect = scaled.extent.insetBy(dx: -100, dy: -100)
            let ctx = CIContext(options: nil)
            guard let cg = ctx.createCGImage(blurred, from: rect) else { return }
            let out = NSImage(cgImage: cg, size: NSSize(width: rect.width, height: rect.height))
            DispatchQueue.main.async {
                if self?.artworkKey == key { self?.artworkGlow = out }
            }
        }
    }

    @discardableResult
    private func runScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
            DispatchQueue.main.async { self.lastError = "\(msg) (\(code))" }
            return nil
        }
        return result.stringValue
    }

    private func tell(_ command: String) {
        guard let p = activePlayer else { return }
        runScript("tell application \"\(p.appName)\" to \(command)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poll() }
    }

    func playPause() { tell("playpause") }
    func next() { tell("next track") }
    func previous() { tell("previous track") }

    func seek(to seconds: Double) {
        tell("set player position to \(Int(seconds))")
    }

    func setVolume(_ percent: Int) {
        guard let p = activePlayer else { return }
        let v = min(max(percent, 0), 100)
        if var np = nowPlaying { np.volume = v; nowPlaying = np }
        volumeHold = Date().addingTimeInterval(1.5)
        runScript("tell application \"\(p.appName)\" to set sound volume to \(v)")
    }

    func toggleShuffle() {
        guard let np = nowPlaying else { return }
        let value = np.shuffle ? "false" : "true"
        switch np.player {
        case .spotify: tell("set shuffling to \(value)")
        case .appleMusic: tell("set shuffle enabled to \(value)")
        }
    }

    func cycleRepeat() {
        guard let np = nowPlaying else { return }
        switch np.player {
        case .spotify:
            tell("set repeating to \(np.repeatMode == .off ? "true" : "false")")
        case .appleMusic:
            let next: String
            switch np.repeatMode {
            case .off: next = "all"
            case .all: next = "one"
            case .one: next = "off"
            }
            tell("set song repeat to \(next)")
        }
    }

    func openPlayer() {
        guard let p = activePlayer,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: p.rawValue).first else { return }
        app.activate()
    }
}
