import SwiftUI
import Combine

enum FaceMood: String, CaseIterable {
    case content, happy, vibing, sleepy, hot, low, charging, surprised, dizzy, wink, watching, focused, dnd

    static let pickable: [FaceMood] = [.content, .happy, .vibing, .sleepy, .hot, .low, .charging]

    var title: String {
        switch self {
        case .content: return "Calm"
        case .happy: return "Happy"
        case .vibing: return "Vibing"
        case .sleepy: return "Sleepy"
        case .hot: return "Hot"
        case .low: return "Low battery"
        case .charging: return "Charging"
        case .surprised: return "Surprised"
        case .dizzy: return "Dizzy"
        case .wink: return "Wink"
        case .watching: return "Camera or mic in use"
        case .focused: return "Focused"
        case .dnd: return "Focus on"
        }
    }

    static func auto(stats: SystemStats, playing: Bool, now: Date, focus: Bool = false) -> FaceMood {
        if stats.thermalState == .serious || stats.thermalState == .critical { return .hot }
        if stats.hasBattery && !stats.isCharging && stats.batteryLevel < 0.15 { return .low }
        if playing { return .vibing }
        if focus { return .dnd }
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 23 || hour < 6 { return .sleepy }
        if stats.hasBattery && stats.isCharging { return .charging }
        return .content
    }
}

struct FaceView: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var music: MusicController
    @ObservedObject var audio: AudioLevelMonitor
    @ObservedObject var events: FaceEvents
    @ObservedObject var timer: TimerManager
    @ObservedObject var weather: WeatherController
    @ObservedObject var focus: FocusMonitor
    @EnvironmentObject var settings: DeckSettings
    var size: CGFloat = 24

    var body: some View {
        let playing = music.nowPlaying?.isPlaying ?? false
        let sky: WeatherCondition? = (settings.weatherOn && settings.weatherFace) ? weather.condition : nil
        let base: FaceMood = settings.faceMode == "auto" ? FaceMood.auto(stats: stats, playing: playing, now: stats.now, focus: settings.focusIndicator && focus.isOn) : (FaceMood(rawValue: settings.faceMode) ?? .content)
        let timed: FaceMood = (timer.phase == .running && !playing) ? .focused : base
        let mood: FaceMood = (settings.eventFaces ? events.override : nil) ?? timed
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.2)
            let blink: CGFloat = (blinkPhase > 3.95 && blinkPhase < 4.13) ? 0.1 : 1
            let bob: CGFloat = mood == .vibing ? CGFloat(sin(t * 2 * .pi * 2.1)) * (1 + 2.5 * CGFloat(audio.level)) : (mood == .sleepy ? CGFloat(sin(t * 1.4)) * 0.8 : 0)
            let tilt: Double = mood == .vibing ? sin(t * 2 * .pi * 1.05) * (3 + 6 * audio.level) : (mood == .sleepy ? 8 : 0)
            let mouthOpen = CGFloat(0.5 + 0.5 * (sin(t * 2 * .pi * 2.1) * 0.5 + 0.5))
            ZStack {
                FaceGlyph(mood: mood, blink: blink, mouthOpen: mouthOpen, color: settings.accent, size: size)
                    .shadow(color: settings.accent.opacity(0.5), radius: 3)
                if let sky {
                    WeatherBadge(condition: sky, isDay: weather.isDay, t: t, size: size)
                        .offset(x: -size * 0.5, y: -size * 0.28)
                }
                if mood == .sleepy {
                    ForEach(0..<2, id: \.self) { i in
                        let ph = (t * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                        Text("z")
                            .font(.system(size: size * (0.28 + 0.1 * CGFloat(i)), weight: .bold, design: .rounded))
                            .foregroundStyle(settings.accent.opacity(1 - ph))
                            .offset(x: size * 0.55 + CGFloat(ph) * 6 + CGFloat(i) * 4, y: -size * 0.35 - CGFloat(ph) * 10 - CGFloat(i) * 3)
                    }
                }
                if mood == .hot {
                    Capsule()
                        .fill(Color(red: 0.45, green: 0.75, blue: 1))
                        .frame(width: size * 0.14, height: size * 0.24)
                        .offset(x: size * 0.48, y: -size * 0.22 + CGFloat(t.truncatingRemainder(dividingBy: 1.6)) * 4)
                }
                if mood == .charging {
                    let pulse = sin(t * 5) * 0.5 + 0.5
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(.yellow)
                        .scaleEffect(0.9 + 0.22 * CGFloat(pulse))
                        .opacity(0.65 + 0.35 * pulse)
                        .shadow(color: .yellow.opacity(0.5 + 0.5 * pulse), radius: 2 + 4 * CGFloat(pulse))
                        .offset(x: size * 0.55, y: -size * 0.42)
                }
                if mood == .vibing {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(settings.accent)
                        .offset(x: size * 0.62, y: -size * 0.42 + CGFloat(sin(t * 3.2)) * 1.5)
                }
                if mood == .low {
                    Circle()
                        .fill(Color(red: 0.45, green: 0.75, blue: 1))
                        .frame(width: size * 0.12, height: size * 0.12)
                        .offset(x: size * 0.22, y: size * 0.02 + CGFloat(t.truncatingRemainder(dividingBy: 2.2)) * 3)
                }
                if mood == .watching {
                    Circle().fill(Color.red).frame(width: size * 0.2, height: size * 0.2)
                        .opacity(0.5 + 0.5 * (sin(t * 4) * 0.5 + 0.5))
                        .offset(x: size * 0.55, y: -size * 0.42)
                }
                if mood == .dnd {
                    Image(systemName: "moon.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(settings.accent)
                        .offset(x: size * 0.58, y: -size * 0.4)
                }
                if mood == .dizzy {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(Color.yellow).frame(width: size * 0.1, height: size * 0.1)
                            .offset(x: CGFloat(cos(t * 4 + Double(i) * 2.1)) * size * 0.5, y: -size * 0.45 + CGFloat(sin(t * 4 + Double(i) * 2.1)) * size * 0.16)
                    }
                }
                if mood == .focused, timer.phase == .running {
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(settings.accent.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size + 6, height: size + 6)
                }
            }
            .frame(width: size, height: size)
            .offset(y: bob)
            .rotationEffect(.degrees(tilt))
        }
        .frame(width: size + 10, height: size)
        .help(mood.title)
    }
}

/// Ambient weather shown alongside the face — a sun, cloud, rain cloud, snow or thunderstorm
/// tucked into the top-left corner. Hand-drawn in the same flat vector style as the face, each in
/// its own single colour with no background. It never changes the face's own expression.
struct WeatherBadge: View {
    let condition: WeatherCondition
    let isDay: Bool
    let t: Double
    let size: CGFloat

    private var cloudColor: Color { Color(white: 0.9) }
    private var rainColor: Color { Color(red: 0.5, green: 0.72, blue: 1) }
    private var sunColor: Color { Color(red: 1, green: 0.82, blue: 0.25) }

    var body: some View {
        let s = size * 0.6
        ZStack {
            switch condition {
            case .clear:
                if isDay { sun.frame(width: s, height: s) }
                else { Crescent().fill(Color(red: 0.9, green: 0.92, blue: 1), style: FillStyle(eoFill: true)).frame(width: s * 0.8, height: s * 0.8) }
            case .partlyCloudy:
                sun.frame(width: s * 0.72, height: s * 0.72).offset(x: s * 0.16, y: -s * 0.18)
                cloud(color: cloudColor, box: s).offset(x: -s * 0.06, y: s * 0.12)
            case .cloudy:
                cloud(color: cloudColor, box: s).offset(x: CGFloat(sin(t * 0.8)) * 1.5)
            case .fog:
                cloud(color: cloudColor, box: s * 0.94).offset(y: -s * 0.08)
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(cloudColor.opacity(0.8))
                        .frame(width: s * (0.5 - CGFloat(i) * 0.1), height: max(1, s * 0.06))
                        .offset(x: CGFloat(sin(t + Double(i))) * 2, y: s * (0.34 + CGFloat(i) * 0.16))
                }
            case .drizzle, .rain:
                cloud(color: cloudColor, box: s).offset(y: -s * 0.1)
                drops(color: rainColor, box: s, count: condition == .rain ? 3 : 2)
            case .snow:
                cloud(color: cloudColor, box: s).offset(y: -s * 0.1)
                flakes(color: .white, box: s)
            case .thunder:
                cloud(color: cloudColor, box: s).offset(y: -s * 0.12)
                Bolt().fill(sunColor.opacity(sin(t * 6) > 0.55 ? 1 : 0.5))
                    .frame(width: s * 0.24, height: s * 0.34)
                    .offset(y: s * 0.28)
            }
        }
        .frame(width: s, height: s)
    }

    private var sun: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule().fill(sunColor)
                    .frame(width: size * 0.06, height: size * 0.18)
                    .offset(y: -size * 0.42)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle().fill(sunColor).frame(width: size * 0.44, height: size * 0.44)
        }
        .rotationEffect(.degrees(t * 12))
        .shadow(color: sunColor.opacity(0.6), radius: 2)
    }

    private func cloud(color: Color, box s: CGFloat) -> some View {
        CloudShape().fill(color)
            .frame(width: s, height: s * 0.66)
    }

    private func drops(color: Color, box s: CGFloat, count: Int) -> some View {
        ForEach(0..<count, id: \.self) { i in
            let ph = (t * 1.6 + Double(i) * 0.4).truncatingRemainder(dividingBy: 1)
            Capsule().fill(color.opacity(1 - ph * 0.7))
                .frame(width: max(1, s * 0.06), height: s * 0.16)
                .rotationEffect(.degrees(12))
                .offset(x: s * (CGFloat(i) - CGFloat(count - 1) / 2) * 0.24,
                        y: s * 0.24 + CGFloat(ph) * s * 0.24)
        }
    }

    private func flakes(color: Color, box s: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { i in
            let ph = (t * 0.9 + Double(i) * 0.34).truncatingRemainder(dividingBy: 1)
            Circle().fill(color.opacity(1 - ph * 0.6))
                .frame(width: s * 0.1, height: s * 0.1)
                .offset(x: s * (CGFloat(i) - 1) * 0.24 + CGFloat(sin(ph * 6)) * 1.5,
                        y: s * 0.22 + CGFloat(ph) * s * 0.26)
        }
    }
}

/// A soft cloud silhouette — overlapping lobes on a flat base, filled as one shape (one colour, no seams).
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.02, y: rect.minY + h * 0.34, width: w * 0.44, height: h * 0.5))
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.28, y: rect.minY + h * 0.06, width: w * 0.46, height: h * 0.56))
        p.addEllipse(in: CGRect(x: rect.minX + w * 0.54, y: rect.minY + h * 0.3, width: w * 0.44, height: h * 0.52))
        p.addRoundedRect(in: CGRect(x: rect.minX + w * 0.06, y: rect.minY + h * 0.5, width: w * 0.88, height: h * 0.4),
                         cornerSize: CGSize(width: h * 0.2, height: h * 0.2))
        return p
    }
}

/// Two circles with an even-odd fill carve a crescent moon.
struct Crescent: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        p.addEllipse(in: CGRect(x: c.x - r * 0.35, y: c.y - r * 0.98, width: r * 1.9, height: r * 1.9))
        return p
    }
}

/// A lightning bolt zig-zag.
struct Bolt: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.55, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.1, y: rect.minY + h * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.45, y: rect.minY + h * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.3, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.9, y: rect.minY + h * 0.4))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.4))
        p.closeSubpath()
        return p
    }
}

struct FaceGlyph: View {
    var mood: FaceMood
    var blink: CGFloat = 1
    var mouthOpen: CGFloat = 1
    var color: Color
    var size: CGFloat

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().fill(color.opacity(0.16))
            Circle().strokeBorder(color, lineWidth: max(1.2, size * 0.07))
            eye(x: -r * 0.36, r: r)
            eye(x: r * 0.36, r: r)
            if mood != .low && mood != .hot && mood != .dizzy && mood != .watching && mood != .focused {
                Circle().fill(color.opacity(0.45)).frame(width: r * 0.26, height: r * 0.18).offset(x: -r * 0.6, y: r * 0.2)
                Circle().fill(color.opacity(0.45)).frame(width: r * 0.26, height: r * 0.18).offset(x: r * 0.6, y: r * 0.2)
            }
            if mood == .hot {
                Circle().fill(Color(red: 1, green: 0.4, blue: 0.4).opacity(0.7)).frame(width: r * 0.3, height: r * 0.2).offset(x: -r * 0.6, y: r * 0.2)
                Circle().fill(Color(red: 1, green: 0.4, blue: 0.4).opacity(0.7)).frame(width: r * 0.3, height: r * 0.2).offset(x: r * 0.6, y: r * 0.2)
            }
            mouth(r: r)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func eye(x: CGFloat, r: CGFloat) -> some View {
        let y = -r * 0.16
        switch mood {
        case .happy, .vibing, .charging:
            ArcUp().stroke(color, style: StrokeStyle(lineWidth: max(1.2, r * 0.13), lineCap: .round))
                .frame(width: r * 0.42, height: r * 0.22).offset(x: x, y: y)
        case .sleepy, .dnd:
            ArcDown().stroke(color, style: StrokeStyle(lineWidth: max(1.2, r * 0.13), lineCap: .round))
                .frame(width: r * 0.4, height: r * 0.16).offset(x: x, y: y + r * 0.06)
        case .low:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.3, height: r * 0.38 * blink)
                Circle().fill(Color.white.opacity(0.9)).frame(width: r * 0.1, height: r * 0.1).offset(x: r * 0.06, y: -r * 0.1)
            }
            .offset(x: x, y: y + r * 0.04)
            Capsule().fill(color).frame(width: r * 0.4, height: max(1, r * 0.09))
                .rotationEffect(.degrees(x < 0 ? -22 : 22)).offset(x: x, y: y - r * 0.3)
        case .hot:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.26, height: r * 0.26 * blink)
            }
            .offset(x: x, y: y)
        case .surprised:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.4, height: r * 0.5)
                Circle().fill(Color.white.opacity(0.9)).frame(width: r * 0.13, height: r * 0.13).offset(x: r * 0.09, y: -r * 0.14)
            }
            .offset(x: x, y: y - r * 0.04)
        case .dizzy:
            ZStack {
                Capsule().fill(color).frame(width: r * 0.36, height: max(1, r * 0.1)).rotationEffect(.degrees(45))
                Capsule().fill(color).frame(width: r * 0.36, height: max(1, r * 0.1)).rotationEffect(.degrees(-45))
            }
            .offset(x: x, y: y)
        case .wink:
            if x > 0 {
                ArcUp().stroke(color, style: StrokeStyle(lineWidth: max(1.2, r * 0.13), lineCap: .round))
                    .frame(width: r * 0.42, height: r * 0.22).offset(x: x, y: y)
            } else {
                ZStack {
                    Ellipse().fill(color).frame(width: r * 0.32, height: r * 0.42)
                    Circle().fill(Color.white.opacity(0.9)).frame(width: r * 0.11, height: r * 0.11).offset(x: r * 0.07, y: -r * 0.11)
                }
                .offset(x: x, y: y)
            }
        case .watching:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.36, height: r * 0.44 * blink)
                Circle().fill(Color.white.opacity(0.9)).frame(width: r * 0.12, height: r * 0.12).offset(x: r * 0.1, y: -r * 0.1)
            }
            .offset(x: x + r * 0.08, y: y)
        case .focused:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.32, height: r * 0.3 * blink)
            }
            .offset(x: x, y: y + r * 0.02)
            Capsule().fill(color).frame(width: r * 0.36, height: max(1, r * 0.09))
                .rotationEffect(.degrees(x < 0 ? 14 : -14)).offset(x: x, y: y - r * 0.26)
        default:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.32, height: r * 0.42 * blink)
                Circle().fill(Color.white.opacity(0.9)).frame(width: r * 0.11, height: r * 0.11).offset(x: r * 0.07, y: -r * 0.11)
                    .opacity(blink > 0.5 ? 1 : 0)
            }
            .offset(x: x, y: y)
        }
    }

    @ViewBuilder
    private func mouth(r: CGFloat) -> some View {
        let y = r * 0.42
        let lw = max(1.2, r * 0.13)
        switch mood {
        case .happy, .charging:
            SmileOpen().fill(color).frame(width: r * 0.62, height: r * 0.34).offset(y: y)
        case .vibing:
            Ellipse().fill(color).frame(width: r * 0.3, height: r * 0.16 + r * 0.24 * mouthOpen).offset(y: y + r * 0.02)
        case .sleepy:
            Ellipse().stroke(color, lineWidth: lw).frame(width: r * 0.2, height: r * 0.24).offset(y: y + r * 0.02)
        case .hot:
            Wobble().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.6, height: r * 0.16).offset(y: y)
        case .low:
            ArcUp().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.5, height: r * 0.18).offset(y: y + r * 0.06)
        case .surprised:
            Ellipse().fill(color).frame(width: r * 0.3, height: r * 0.34).offset(y: y + r * 0.04)
        case .dizzy:
            Wobble().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.5, height: r * 0.14).offset(y: y + r * 0.04)
        case .wink:
            ArcDown().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.56, height: r * 0.22).offset(x: r * 0.06, y: y)
        case .watching:
            Capsule().fill(color).frame(width: r * 0.32, height: max(1, r * 0.1)).offset(y: y + r * 0.02)
        case .focused:
            Capsule().fill(color).frame(width: r * 0.4, height: max(1, r * 0.1)).offset(y: y + r * 0.02)
        case .content, .dnd:
            ArcDown().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.52, height: r * 0.2).offset(y: y)
        }
    }
}

struct ArcUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return p
    }
}

struct ArcDown: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6))
        return p
    }
}

struct SmileOpen: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.9))
        p.closeSubpath()
        return p
    }
}

struct Wobble: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width / 3
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w, y: rect.midY), control: CGPoint(x: rect.minX + w / 2, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + 2 * w, y: rect.midY), control: CGPoint(x: rect.minX + 1.5 * w, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.minX + 2.5 * w, y: rect.minY))
        return p
    }
}


import CoreMediaIO
import CoreAudio

final class FaceEvents: ObservableObject {
    @Published private(set) var override: FaceMood?
    private var cancellables = Set<AnyCancellable>()
    private var poll: Timer?
    private var desktopSource: DispatchSourceFileSystemObject?
    private var desktopFD: Int32 = -1
    private var lastCharging: Bool?
    private var wasLow = false
    private var flashUntil = Date.distantPast
    private var mediaActive = false

    func start(stats: SystemStats) {
        stats.$isCharging.receive(on: RunLoop.main).sink { [weak self] c in
            guard let self else { return }
            if let last = self.lastCharging, last != c { self.flash(c ? .surprised : .content, c ? 2.2 : 1.4) }
            self.lastCharging = c
        }.store(in: &cancellables)
        stats.$batteryLevel.receive(on: RunLoop.main).sink { [weak self] lvl in
            guard let self else { return }
            let low = lvl < 0.10 && stats.hasBattery && !stats.isCharging
            if low && !self.wasLow { self.flash(.dizzy, 3.5) }
            self.wasLow = low
        }.store(in: &cancellables)
        watchDesktop()
        poll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.pollMedia() }
        RunLoop.main.add(poll!, forMode: .common)
    }

    func flash(_ mood: FaceMood, _ seconds: TimeInterval) {
        override = mood
        flashUntil = Date().addingTimeInterval(seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in
            guard let self, Date() >= self.flashUntil else { return }
            self.override = self.mediaActive ? .watching : nil
        }
    }

    private func pollMedia() {
        let active = FaceEvents.cameraInUse() || FaceEvents.micInUse()
        if active != mediaActive {
            mediaActive = active
            if Date() >= flashUntil { override = active ? .watching : nil }
        }
    }

    private func watchDesktop() {
        let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        desktopFD = open(dir.path, O_EVTONLY)
        guard desktopFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: desktopFD, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
            let recent = items.contains { u in
                guard u.lastPathComponent.hasPrefix("Screenshot"), let d = try? u.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false }
                return Date().timeIntervalSince(d) < 4
            }
            if recent { self?.flash(.wink, 2.0) }
        }
        src.resume()
        desktopSource = src
    }

    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var v: UInt32 = 0
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, 4, &u, &v) == 0, v != 0 { return true }
        }
        return false
    }

    static func micInUse() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == 0 else { return false }
        for id in ids {
            var inAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var sz: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &inAddr, 0, nil, &sz)
            if sz == 0 { continue }
            var runAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var v: UInt32 = 0
            var vs: UInt32 = 4
            if AudioObjectGetPropertyData(id, &runAddr, 0, nil, &vs, &v) == 0, v != 0 { return true }
        }
        return false
    }
}
