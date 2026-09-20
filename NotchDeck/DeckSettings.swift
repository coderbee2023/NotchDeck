import SwiftUI
import AppKit
import ServiceManagement

enum SystemWidget: String, CaseIterable, Identifiable {
    case clock, weather, battery, cpu, memory, disk, network, thermal, topProcess, uptime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .weather: return "Weather"
        case .battery: return "Battery"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .thermal: return "Thermals"
        case .topProcess: return "Top App"
        case .uptime: return "Uptime"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .weather: return "cloud.sun.fill"
        case .battery: return "battery.75percent"
        case .cpu: return "cpu.fill"
        case .memory: return "memorychip.fill"
        case .disk: return "internaldrive.fill"
        case .network: return "network"
        case .thermal: return "thermometer.medium"
        case .topProcess: return "flame.fill"
        case .uptime: return "hourglass"
        }
    }
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case mono, ocean, mint, ember, violet, rose

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var hex: String {
        switch self {
        case .mono: return "#FFFFFF"
        case .ocean: return "#4DA3FF"
        case .mint: return "#3DDC84"
        case .ember: return "#FF8A3D"
        case .violet: return "#9B6CFF"
        case .rose: return "#FF5C8A"
        }
    }
}

final class DeckSettings: ObservableObject {
    static let defaultWidgets: [SystemWidget] = [.clock, .weather, .battery, .cpu, .memory, .disk, .network, .thermal]

    @Published var accentHex: String { didSet { d.set(accentHex, forKey: "accentHex") } }
    @Published var glass: Double { didSet { d.set(glass, forKey: "glass") } }
    @Published var tint: Double { didSet { d.set(tint, forKey: "tint") } }
    @Published var showVisualizer: Bool { didSet { d.set(showVisualizer, forKey: "showVisualizer") } }
    @Published var showVolume: Bool { didSet { d.set(showVolume, forKey: "showVolume") } }
    @Published var animateArtwork: Bool { didSet { d.set(animateArtwork, forKey: "animateArtwork") } }
    @Published var showQuickActions: Bool { didSet { d.set(showQuickActions, forKey: "showQuickActions") } }
    @Published var showSystemVolume: Bool { didSet { d.set(showSystemVolume, forKey: "showSystemVolume") } }
    @Published var widgets: [SystemWidget] { didSet { d.set(widgets.map(\.rawValue), forKey: "widgets") } }
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: "openOnHover") } }
    @Published var hoverDelay: Double { didSet { d.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var pillNowPlaying: Bool { didSet { d.set(pillNowPlaying, forKey: "pillNowPlaying") } }
    @Published var glowBorder: Bool { didSet { d.set(glowBorder, forKey: "glowBorder") } }
    @Published var glowHex: String { didSet { d.set(glowHex, forKey: "glowHex") } }
    @Published var waveWithMusic: Bool { didSet { d.set(waveWithMusic, forKey: "waveWithMusic") } }
    @Published var waveIntensity: Double { didSet { d.set(waveIntensity, forKey: "waveIntensity") } }
    @Published var showFace: Bool { didSet { d.set(showFace, forKey: "showFace") } }
    @Published var faceMode: String { didSet { d.set(faceMode, forKey: "faceMode") } }
    @Published var eventFaces: Bool { didSet { d.set(eventFaces, forKey: "eventFaces") } }
    @Published var clickActions: Bool { didSet { d.set(clickActions, forKey: "clickActions") } }
    @Published var scrollVolume: Bool { didSet { d.set(scrollVolume, forKey: "scrollVolume") } }
    @Published var showLyrics: Bool { didSet { d.set(showLyrics, forKey: "showLyrics") } }
    @Published var lyricsUnderNotch: Bool { didSet { d.set(lyricsUnderNotch, forKey: "lyricsUnderNotch") } }
    @Published var weatherOn: Bool { didSet { d.set(weatherOn, forKey: "weatherOn") } }
    @Published var weatherCity: String { didSet { d.set(weatherCity, forKey: "weatherCity") } }
    @Published var weatherUseLocation: Bool { didSet { d.set(weatherUseLocation, forKey: "weatherUseLocation") } }
    @Published var fahrenheit: Bool { didSet { d.set(fahrenheit, forKey: "fahrenheit") } }
    @Published var weatherFace: Bool { didSet { d.set(weatherFace, forKey: "weatherFace") } }
    @Published var glowMode: String { didSet { d.set(glowMode, forKey: "glowMode") } }
    @Published var focusIndicator: Bool { didSet { d.set(focusIndicator, forKey: "focusIndicator") } }
    @Published var chargeAnimation: Bool { didSet { d.set(chargeAnimation, forKey: "chargeAnimation") } }
    @Published var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    @Published var launchAtLogin: Bool = false

    private let d = UserDefaults.standard

    init() {
        accentHex = d.string(forKey: "accentHex") ?? ThemePreset.mono.hex
        glass = d.object(forKey: "glass") as? Double ?? 0.11
        tint = d.object(forKey: "tint") as? Double ?? 0
        showVisualizer = d.object(forKey: "showVisualizer") as? Bool ?? true
        showVolume = d.object(forKey: "showVolume") as? Bool ?? true
        animateArtwork = d.object(forKey: "animateArtwork") as? Bool ?? true
        showQuickActions = d.object(forKey: "showQuickActions") as? Bool ?? true
        showSystemVolume = d.object(forKey: "showSystemVolume") as? Bool ?? true
        openOnHover = d.object(forKey: "openOnHover") as? Bool ?? true
        hoverDelay = d.object(forKey: "hoverDelay") as? Double ?? 0.35
        pillNowPlaying = d.object(forKey: "pillNowPlaying") as? Bool ?? true
        glowBorder = d.object(forKey: "glowBorder") as? Bool ?? true
        glowHex = d.string(forKey: "glowHex") ?? ""
        waveWithMusic = d.object(forKey: "waveWithMusic") as? Bool ?? true
        waveIntensity = d.object(forKey: "waveIntensity") as? Double ?? 0.6
        showFace = d.object(forKey: "showFace") as? Bool ?? true
        faceMode = d.string(forKey: "faceMode") ?? "auto"
        eventFaces = d.object(forKey: "eventFaces") as? Bool ?? true
        clickActions = d.object(forKey: "clickActions") as? Bool ?? true
        scrollVolume = d.object(forKey: "scrollVolume") as? Bool ?? true
        showLyrics = d.object(forKey: "showLyrics") as? Bool ?? true
        lyricsUnderNotch = d.object(forKey: "lyricsUnderNotch") as? Bool ?? false
        weatherOn = d.object(forKey: "weatherOn") as? Bool ?? true
        weatherCity = d.string(forKey: "weatherCity") ?? ""
        weatherUseLocation = d.object(forKey: "weatherUseLocation") as? Bool ?? true
        fahrenheit = d.object(forKey: "fahrenheit") as? Bool ?? (Locale.current.measurementSystem == .us)
        weatherFace = d.object(forKey: "weatherFace") as? Bool ?? true
        glowMode = d.string(forKey: "glowMode") ?? (d.string(forKey: "glowHex").map { $0.isEmpty ? "accent" : "custom" } ?? "accent")
        focusIndicator = d.object(forKey: "focusIndicator") as? Bool ?? true
        chargeAnimation = d.object(forKey: "chargeAnimation") as? Bool ?? true
        sounds = d.object(forKey: "sounds") as? Bool ?? false
        if let raw = d.stringArray(forKey: "widgets") {
            widgets = raw.compactMap(SystemWidget.init(rawValue:))
        } else {
            widgets = DeckSettings.defaultWidgets
        }
        if !d.bool(forKey: "weatherWidgetMigrated") {
            if !widgets.contains(.weather) {
                var next = widgets
                next.insert(.weather, at: min(1, next.count))
                widgets = next
                d.set(next.map(\.rawValue), forKey: "widgets")
            }
            d.set(true, forKey: "weatherWidgetMigrated")
        }
        if !d.bool(forKey: "hoverDelayMigrated") {
            hoverDelay = max(hoverDelay, 0.35)
            d.set(hoverDelay, forKey: "hoverDelay")
            d.set(true, forKey: "hoverDelayMigrated")
        }
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
        refreshLaunchAtLogin()
    }

    var mode: GlowMode { GlowMode(rawValue: glowMode) ?? .accent }

    /// The static part of the glow: dynamic modes are resolved against live art in DeckState.
    var glowColor: Color {
        if mode == .custom, !glowHex.isEmpty { return Color(nsColor: NSColor(hex: glowHex) ?? accentNSColor) }
        return accent
    }

    var accentNSColor: NSColor { NSColor(hex: accentHex) ?? .white }
    var accent: Color { Color(nsColor: accentNSColor) }
    var onAccent: Color { accentNSColor.luminance > 0.6 ? .black : .white }

    var accentHue: Double? {
        guard let c = accentNSColor.usingColorSpace(.deviceRGB), c.saturationComponent > 0.1 else { return nil }
        return Double(c.hueComponent)
    }

    func isOn(_ w: SystemWidget) -> Bool { widgets.contains(w) }

    func toggle(_ w: SystemWidget) {
        if let i = widgets.firstIndex(of: w) {
            widgets.remove(at: i)
        } else {
            var next = widgets
            next.append(w)
            let order = SystemWidget.allCases
            next.sort { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
            widgets = next
        }
    }

    func setAccent(hue: Double) {
        accentHex = NSColor(hue: CGFloat(hue), saturation: 0.72, brightness: 1, alpha: 1).hexString
    }

    func reset() {
        accentHex = ThemePreset.mono.hex
        glass = 0.11
        tint = 0
        showVisualizer = true
        showVolume = true
        animateArtwork = true
        showQuickActions = true
        showSystemVolume = true
        widgets = DeckSettings.defaultWidgets
        openOnHover = true
        hoverDelay = 0
        pillNowPlaying = true
        glowBorder = true
        glowHex = ""
        waveWithMusic = true
        waveIntensity = 0.6
        showFace = true
        faceMode = "auto"
        eventFaces = true
        clickActions = true
        scrollVolume = true
        showLyrics = true
        weatherOn = true
        weatherUseLocation = true
        weatherFace = true
        glowMode = "accent"
        focusIndicator = true
        chargeAnimation = true
        sounds = false
        hoverDelay = 0.35
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    var luminance: Double {
        let c = usingColorSpace(.sRGB) ?? self
        return 0.2126 * Double(c.redComponent) + 0.7152 * Double(c.greenComponent) + 0.0722 * Double(c.blueComponent)
    }
}
