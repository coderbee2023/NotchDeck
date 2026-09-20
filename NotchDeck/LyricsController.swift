import Foundation
import Combine

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}

final class LyricsController: ObservableObject {
    enum Status: Equatable {
        case idle, loading, synced, plain, missing, failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainText: String?
    @Published private(set) var index: Int = -1
    @Published private(set) var source: String?
    /// Fraction (0…1) through the current line, from its timestamp to the next line's — drives
    /// the word-by-word colouring under the notch. LRC only carries per-line times, so this is
    /// a smooth interpolation across the line, not true per-syllable timing.
    @Published private(set) var lineProgress: Double = 0

    private var trackKey: String?
    private var task: URLSessionDataTask?
    private var ticker: Timer?
    private weak var music: MusicController?
    private var cancellables = Set<AnyCancellable>()
    private var cache: [String: [LyricLine]] = [:]
    private var misses = Set<String>()

    var currentLine: String? {
        guard status == .synced, index >= 0, index < lines.count else { return nil }
        let t = lines[index].text
        return t.isEmpty ? nil : t
    }

    var nextLine: String? {
        guard status == .synced, index + 1 < lines.count else { return nil }
        let t = lines[index + 1].text
        return t.isEmpty ? nil : t
    }

    func start(music: MusicController, settings: DeckSettings) {
        self.music = music
        music.$nowPlaying
            .map { $0?.trackKey }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, settings.showLyrics || settings.lyricsUnderNotch else { return }
                self.refresh()
            }
            .store(in: &cancellables)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    func refresh(force: Bool = false) {
        guard let np = music?.nowPlaying, !np.title.isEmpty else {
            reset()
            return
        }
        if force { misses.remove(np.trackKey); cache[np.trackKey] = nil }
        guard np.trackKey != trackKey || force else { return }
        trackKey = np.trackKey
        index = -1
        plainText = nil
        source = nil

        if let cached = cache[np.trackKey] {
            lines = cached
            status = .synced
            source = "LRCLIB"
            return
        }
        if misses.contains(np.trackKey) {
            lines = []
            status = .missing
            return
        }

        lines = []
        status = .loading
        fetch(np)
    }

    private func reset() {
        task?.cancel()
        trackKey = nil
        lines = []
        plainText = nil
        index = -1
        source = nil
        status = .idle
    }

    private func fetch(_ np: NowPlaying) {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "artist_name", value: np.artist),
            URLQueryItem(name: "track_name", value: np.title),
            URLQueryItem(name: "album_name", value: np.album),
            URLQueryItem(name: "duration", value: String(Int(np.duration.rounded())))
        ]
        guard let url = c.url else { status = .failed; return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("NotchDeck (https://github.com/coderbee2023/NotchDeck)", forHTTPHeaderField: "User-Agent")
        let key = np.trackKey

        task?.cancel()
        task = URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                DispatchQueue.main.async {
                    self.misses.insert(key)
                    guard self.trackKey == key else { return }
                    self.searchFallback(np)
                }
                return
            }
            guard let data, code == 200 else {
                DispatchQueue.main.async {
                    guard self.trackKey == key else { return }
                    self.status = .failed
                }
                return
            }
            self.handle(data: data, key: key, np: np)
        }
        task?.resume()
    }

    private func searchFallback(_ np: NowPlaying) {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [
            URLQueryItem(name: "artist_name", value: np.artist),
            URLQueryItem(name: "track_name", value: np.title)
        ]
        guard let url = c.url else { status = .missing; return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("NotchDeck (https://github.com/coderbee2023/NotchDeck)", forHTTPHeaderField: "User-Agent")
        let key = np.trackKey
        task?.cancel()
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { if self.trackKey == key { self.status = .missing } }
                return
            }
            let best = arr.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? arr.first
            guard let best, let obj = try? JSONSerialization.data(withJSONObject: best) else {
                DispatchQueue.main.async { if self.trackKey == key { self.status = .missing } }
                return
            }
            self.handle(data: obj, key: key, np: np)
        }
        task?.resume()
    }

    private func handle(data: Data, key: String, np: NowPlaying) {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let synced = (obj?["syncedLyrics"] as? String) ?? ""
        let plain = (obj?["plainLyrics"] as? String) ?? ""
        let parsed = LyricsController.parse(lrc: synced)
        DispatchQueue.main.async {
            guard self.trackKey == key else { return }
            if !parsed.isEmpty {
                self.lines = parsed
                self.cache[key] = parsed
                self.status = .synced
                self.source = "LRCLIB"
            } else if !plain.isEmpty {
                self.plainText = plain
                self.status = .plain
                self.source = "LRCLIB"
            } else {
                self.misses.insert(key)
                self.status = .missing
            }
        }
    }

    static func parse(lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            var stamps: [Double] = []
            var rest = line
            while rest.hasPrefix("[") {
                guard let close = rest.firstIndex(of: "]") else { break }
                let tag = String(rest[rest.index(after: rest.startIndex)..<close])
                let bits = tag.split(separator: ":")
                if bits.count == 2, let m = Double(bits[0]), let s = Double(bits[1].replacingOccurrences(of: ",", with: ".")) {
                    stamps.append(m * 60 + s)
                }
                rest = String(rest[rest.index(after: close)...])
            }
            guard !stamps.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in stamps { out.append(LyricLine(time: t, text: text)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    private func tick() {
        guard status == .synced, !lines.isEmpty, let music, let np = music.nowPlaying, np.isPlaying else { return }
        let pos = music.livePosition + 0.2
        var i = index
        if i < 0 || lines[i].time > pos { i = -1 }
        while i + 1 < lines.count, lines[i + 1].time <= pos { i += 1 }
        if i != index { index = i }

        if i >= 0, i < lines.count {
            let start = lines[i].time
            let end = i + 1 < lines.count ? lines[i + 1].time : start + 4
            let span = max(0.4, end - start)
            let p = min(1, max(0, (pos - start) / span))
            if abs(p - lineProgress) > 0.02 { lineProgress = p }
        } else if lineProgress != 0 {
            lineProgress = 0
        }
    }
}
