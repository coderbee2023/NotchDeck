import AppKit
import Combine
import SwiftUI

enum GlowMode: String, CaseIterable, Identifiable {
    case accent, custom, album, wallpaper, mood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent: return "Accent"
        case .custom: return "Custom"
        case .album: return "Album"
        case .wallpaper: return "Wallpaper"
        case .mood: return "Mood"
        }
    }

    var symbol: String {
        switch self {
        case .accent: return "paintbrush.pointed.fill"
        case .custom: return "circle.hexagongrid.fill"
        case .album: return "music.note"
        case .wallpaper: return "photo.fill"
        case .mood: return "sparkles"
        }
    }
}

/// How the glow border is animated. `breathe`/`pulse`/`solid` use the single chosen colour;
/// `flow` sweeps that colour and its neighbours around the border; `rainbow` is a full RGB
/// spectrum flowing; `comet` runs a bright highlight around a dim base.
enum GlowDynamic: String, CaseIterable, Identifiable {
    case breathe, pulse, flow, rainbow, comet, solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathe: return "Breathe"
        case .pulse: return "Pulse"
        case .flow: return "Flow"
        case .rainbow: return "Rainbow"
        case .comet: return "Comet"
        case .solid: return "Solid"
        }
    }

    var symbol: String {
        switch self {
        case .breathe: return "wind"
        case .pulse: return "waveform.path.ecg"
        case .flow: return "water.waves"
        case .rainbow: return "rainbow"
        case .comet: return "sparkles"
        case .solid: return "circle.fill"
        }
    }

    /// Whether the border colour comes from the animation itself (rainbow) rather than the
    /// chosen glow colour — used to gate the colour picker in settings.
    var usesOwnColor: Bool { self == .rainbow }
}

/// Picks a glow color out of the current album art or desktop picture.
final class GlowSource: ObservableObject {
    @Published private(set) var albumColor: Color?
    @Published private(set) var wallpaperColor: Color?
    /// Colour of the current song's mood, set by SongVibeController from on-device Apple
    /// Intelligence. Drives the `.mood` glow mode.
    @Published var moodColor: Color?

    private var cancellables = Set<AnyCancellable>()
    private var wallpaperTimer: Timer?
    private var lastWallpaperPath: String?

    func start(music: MusicController) {
        music.$artwork
            .receive(on: RunLoop.main)
            .sink { [weak self] image in
                self?.albumColor = image.flatMap { GlowSource.dominantColor(of: $0) }
            }
            .store(in: &cancellables)

        refreshWallpaper()
        wallpaperTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refreshWallpaper()
        }
        RunLoop.main.add(wallpaperTimer!, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWallpaper(force: true)
        }
    }

    func color(for mode: GlowMode) -> Color? {
        switch mode {
        case .album: return albumColor
        case .wallpaper: return wallpaperColor
        case .mood: return moodColor
        default: return nil
        }
    }

    private func refreshWallpaper(force: Bool = false) {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        if !force, url.path == lastWallpaperPath { return }
        lastWallpaperPath = url.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let image = NSImage(contentsOf: url),
                  let color = GlowSource.dominantColor(of: image) else { return }
            DispatchQueue.main.async { self?.wallpaperColor = color }
        }
    }

    /// Average the image down to a handful of pixels, then pick the most colorful one and
    /// push it toward something that actually reads as a glow.
    static func dominantColor(of image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff)?.cgImage else { return nil }

        let side = 8
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels,
                                      width: side,
                                      height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

        var best: (score: CGFloat, color: NSColor)?
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255
            let g = CGFloat(pixels[i + 1]) / 255
            let b = CGFloat(pixels[i + 2]) / 255
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            guard let hsb = color.usingColorSpace(.deviceRGB) else { continue }
            let saturation = hsb.saturationComponent
            let brightness = hsb.brightnessComponent
            // Favour colorful mid-tones; near-black and washed-out pixels make poor glows.
            let score = saturation * (1 - abs(brightness - 0.62))
            if best == nil || score > best!.score { best = (score, hsb) }
        }

        guard let picked = best?.color else { return nil }
        let boosted = NSColor(hue: picked.hueComponent,
                              saturation: min(1, max(0.55, picked.saturationComponent * 1.3)),
                              brightness: min(1, max(0.72, picked.brightnessComponent * 1.2)),
                              alpha: 1)
        return Color(nsColor: boosted)
    }
}
