import SwiftUI
import AppKit
import ServiceManagement

enum SystemWidget: String, CaseIterable, Identifiable {
    case clock, battery, cpu, memory, disk, network, thermal, topProcess, uptime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
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
    static let defaultWidgets: [SystemWidget] = [.clock, .battery, .cpu, .memory, .disk, .network, .thermal, .topProcess]

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
        hoverDelay = d.object(forKey: "hoverDelay") as? Double ?? 0.0
        pillNowPlaying = d.object(forKey: "pillNowPlaying") as? Bool ?? true
        if let raw = d.stringArray(forKey: "widgets") {
            widgets = raw.compactMap(SystemWidget.init(rawValue:))
        } else {
            widgets = DeckSettings.defaultWidgets
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
