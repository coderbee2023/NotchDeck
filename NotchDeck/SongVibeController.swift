import Foundation
import Combine
import SwiftUI
import FoundationModels

/// Reads the emotional vibe of the currently-playing song with on-device Apple Intelligence and
/// exposes it as plain values the notch UI can drive: a glow colour, an emoji, an energy level, a
/// mood word and a short caption. Everything runs in the background, one read per track (cached by
/// `trackKey`), and falls back gracefully when Apple Intelligence isn't available.
final class SongVibeController: ObservableObject {
    /// The vibe fields, resolved to plain types so the rest of the app never touches
    /// FoundationModels (and so nothing else needs an availability guard).
    @Published private(set) var mood: String?
    @Published private(set) var emoji: String?
    @Published private(set) var energy: Int?          // 0…100
    @Published private(set) var caption: String?
    @Published private(set) var color: Color?
    /// Our own catalogue face chosen to match the read mood (by name, then keyword).
    @Published private(set) var face: SongFace?
    /// Whether the on-device model is usable at all — false on < macOS 26 or when Apple
    /// Intelligence is turned off / still downloading.
    @Published private(set) var modelReady = false

    struct Vibe: Equatable {
        let mood: String
        let color: Color
        let emoji: String
        let energy: Int
        let caption: String
    }

    private weak var music: MusicController?
    private weak var glow: GlowSource?
    private weak var lyrics: LyricsController?
    private var cancellables = Set<AnyCancellable>()
    private var cache: [String: Vibe] = [:]
    private var currentKey: String?
    private var debounce: DispatchWorkItem?
    private var task: Task<Void, Never>?

    /// A glow dynamic that fits the song's energy — calm breathes, mid flows, high runs a comet.
    var suggestedDynamic: GlowDynamic? {
        guard let e = energy else { return nil }
        switch e {
        case ..<34: return .breathe
        case 34..<70: return .flow
        default: return .comet
        }
    }

    func start(music: MusicController, glow: GlowSource, lyrics: LyricsController? = nil) {
        self.music = music
        self.glow = glow
        self.lyrics = lyrics
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: modelReady = true
            default: modelReady = false
            }
        }
        music.$nowPlaying
            .map { $0?.trackKey }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleRead() }
            .store(in: &cancellables)
    }

    private func scheduleRead() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.read() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func read() {
        guard let np = music?.nowPlaying, !np.title.isEmpty else { apply(nil); return }
        let key = np.trackKey
        currentKey = key
        if let cached = cache[key] { apply(cached); return }

        // No on-device model → deterministic fallback so the UI still has a colour/emoji.
        guard #available(macOS 26.0, *), modelReady else { apply(fallback(np)); return }

        task?.cancel()
        let lyric = lyrics?.currentLine
        task = Task { [weak self] in
            let vibe = await SongVibeController.fetch(np, lyric: lyric)
            await MainActor.run {
                guard let self, self.currentKey == key else { return }
                let resolved = vibe ?? self.fallback(np)
                self.cache[key] = resolved
                self.apply(resolved)
            }
        }
    }

    private func apply(_ vibe: Vibe?) {
        if mood != vibe?.mood { mood = vibe?.mood }
        if emoji != vibe?.emoji { emoji = vibe?.emoji }
        if energy != vibe?.energy { energy = vibe?.energy }
        if caption != vibe?.caption { caption = vibe?.caption }
        color = vibe?.color
        face = vibe.flatMap { SongFace.match($0.mood) }
        glow?.moodColor = vibe?.color
    }

    /// Used when Apple Intelligence is unavailable or the read fails: a stable colour derived from
    /// the track so the glow still has something on-brand-ish, with a neutral emoji and mid energy.
    private func fallback(_ np: NowPlaying) -> Vibe {
        let hue = Double(abs(np.trackKey.hashValue) % 360) / 360.0
        return Vibe(mood: "unknown",
                    color: Color(hue: hue, saturation: 0.72, brightness: 1),
                    emoji: "🎵",
                    energy: 50,
                    caption: np.title)
    }

    // MARK: - Apple Intelligence

    @available(macOS 26.0, *)
    private static func fetch(_ np: NowPlaying, lyric: String?) async -> Vibe? {
        let instructions = """
        You read the emotional vibe of a song from its title, artist and album. Reply with: a one/two-word mood; a colour a designer would pick to represent that mood as a glowing light on a dark screen; a single emoji that fits; energy 0 (calm/ambient/slow) to 100 (intense/high-tempo/loud); and a poetic caption of at most six words. Use whatever you know about the song; if you don't recognise it, infer from the words in the title and the artist's usual style. Colours must be vivid enough to glow on black — avoid near-black, near-white and muddy greys.
        """
        var prompt = "Song: \"\(np.title)\" by \(np.artist), from the album \"\(np.album)\". Give its mood, colour, emoji, energy and caption."
        if let lyric, !lyric.isEmpty { prompt += " A lyric currently playing: \"\(lyric)\"." }
        // The on-device model can occasionally fail a structured generation; one retry with a
        // fresh session clears most transient misses before we fall back.
        for attempt in 0..<2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, generating: SongVibe.self)
                let v = response.content
                let color = NSColor(hex: v.colorHex).map(Color.init(nsColor:))
                    ?? Color(hue: 0.6, saturation: 0.85, brightness: 1)
                return Vibe(mood: v.mood.trimmingCharacters(in: .whitespacesAndNewlines),
                            color: color,
                            emoji: v.emoji.trimmingCharacters(in: .whitespacesAndNewlines),
                            energy: max(0, min(100, v.energy)),
                            caption: v.caption.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                if attempt == 1 { return nil }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        return nil
    }
}

/// The on-device model's structured answer. The model has a small context window and limited
/// knowledge of obscure tracks, so the guides steer it to infer from the title words when unsure.
@available(macOS 26.0, *)
@Generable
struct SongVibe {
    @Guide(description: "one or two word mood, e.g. melancholy, euphoric, chill, menacing")
    var mood: String
    @Guide(description: "a vivid hex colour #RRGGBB representing the mood as a glow on a dark screen")
    var colorHex: String
    @Guide(description: "a single emoji matching the vibe")
    var emoji: String
    @Guide(description: "energy from 0 (calm) to 100 (intense)")
    var energy: Int
    @Guide(description: "poetic vibe caption, at most six words")
    var caption: String
}
