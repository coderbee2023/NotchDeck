import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DeckView: View {
    @EnvironmentObject var state: DeckState
    @EnvironmentObject var settings: DeckSettings
    @EnvironmentObject var ui: PanelState
    @ObservedObject var music: MusicController
    @EnvironmentObject var audio: AudioLevelMonitor
    @ObservedObject var timer: TimerManager
    @ObservedObject var shelf: ShelfManager
    @ObservedObject var glow: GlowSource
    @ObservedObject var focus: FocusMonitor
    @ObservedObject var vibe: SongVibeController
    let metrics: NotchMetrics

    @State private var chargeBannerUntil: Date?
    @State private var chargeRing: Double = 0

    /// Glow color after the album / wallpaper modes are resolved.
    private var liveGlow: Color {
        glow.color(for: settings.mode) ?? settings.glowColor
    }

    private var focusOn: Bool { settings.focusIndicator && focus.isOn }

    private let expandedSize = NotchMetrics.expandedSize

    /// "2h 10m to full" while the charge banner is up, or just the percentage if macOS
    /// has not worked out an estimate yet.
    private var chargeLine: String? {
        let stats = state.stats
        guard stats.hasBattery else { return nil }
        if let mins = stats.batteryMinutes, mins > 0 {
            let h = mins / 60
            let m = mins % 60
            return h > 0 ? "\(h)h \(m)m to full" : "\(m)m to full"
        }
        return "\(Int(stats.batteryLevel * 100))% · charging"
    }

    private func publishHitRect(expanded: Bool, width: CGFloat, height: CGFloat, shift: CGFloat) {
        guard !expanded else { ui.hitRect = nil; return }
        let panel = metrics.collapsedSize
        ui.hitRect = CGRect(x: (panel.width - width) / 2 + shift,
                            y: panel.height - height,
                            width: width,
                            height: height)
    }

    /// The glow border, coloured by POSITION around the outline so the whole palette shows at
    /// once (like an RGB keyboard's rainbow across the keys) instead of one hue by centre-angle.
    /// Multi-colour dynamics are drawn as many short trimmed segments, each its own colour;
    /// single-colour dynamics stay one cheap stroke.
    @ViewBuilder
    private func borderOutline(_ dyn: GlowDynamic, base: Color, t: Double, flare: CGFloat, radius: CGFloat, amp: CGFloat, lineW: CGFloat) -> some View {
        if dyn == .rainbow || dyn == .flow || dyn == .comet {
            let n = 30
            ZStack {
                ForEach(0..<n, id: \.self) { i in
                    let a = CGFloat(i) / CGFloat(n)
                    let b = CGFloat(i + 1) / CGFloat(n)
                    NotchWaveOutline(bottomRadius: radius, topFlare: flare, time: t, amplitude: amp)
                        .trim(from: a, to: min(1, b + 0.03))
                        .stroke(borderColor(dyn, base: base, pos: (Double(i) + 0.5) / Double(n), t: t),
                                style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
                }
            }
        } else {
            NotchWaveOutline(bottomRadius: radius, topFlare: flare, time: t, amplitude: amp)
                .stroke(base, style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
        }
    }

    /// Colour at a point `pos` (0…1) around the border for a given dynamic. `rainbow` maps the
    /// full spectrum around the loop and drifts it; `flow` waves the chosen colour's hue around;
    /// `comet` keeps the chosen colour with a bright head that travels the loop.
    private func borderColor(_ dyn: GlowDynamic, base: Color, pos: Double, t: Double) -> Color {
        switch dyn {
        case .rainbow:
            let h = (pos + t * 0.14).truncatingRemainder(dividingBy: 1)
            return Color(hue: h, saturation: 0.95, brightness: 1)
        case .flow:
            let ns = NSColor(base).usingColorSpace(.deviceRGB) ?? .white
            let s = Double(max(0.6, ns.saturationComponent))
            let b = Double(max(0.9, ns.brightnessComponent))
            var h = Double(ns.hueComponent) + 0.18 * sin((pos + t * 0.12) * 2 * .pi)
            h = h.truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
            return Color(hue: h, saturation: s, brightness: b)
        case .comet:
            let head = (t * 0.22).truncatingRemainder(dividingBy: 1)
            var d = abs(pos - head); if d > 0.5 { d = 1 - d }
            return DeckView.mix(base, .white, max(0, 1 - d / 0.13))
        default:
            return base
        }
    }

    /// Linear RGB blend of two colours, `f` = 0 → a, 1 → b.
    static func mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
        let na = NSColor(a).usingColorSpace(.deviceRGB) ?? .white
        let nb = NSColor(b).usingColorSpace(.deviceRGB) ?? .white
        let g = CGFloat(max(0, min(1, f)))
        return Color(nsColor: NSColor(red: na.redComponent + (nb.redComponent - na.redComponent) * g,
                                      green: na.greenComponent + (nb.greenComponent - na.greenComponent) * g,
                                      blue: na.blueComponent + (nb.blueComponent - na.blueComponent) * g,
                                      alpha: 1))
    }

    /// Words already sung are tinted the accent colour, the rest dimmed — a smooth per-line
    /// interpolation (LRC has no per-word timing), giving the karaoke feel under the notch.
    static func coloredLyric(_ text: String, progress: Double, accent: Color) -> AttributedString {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return AttributedString(text) }
        // Run the colour ahead of the raw line fraction so words light up closer to when they're
        // actually sung (LRC only gives per-line times, so a lead feels more in sync).
        let p = min(1, progress * 1.6 + 0.08)
        let reached = max(0, min(words.count, Int((Double(words.count) * p).rounded())))
        var out = AttributedString()
        for (i, w) in words.enumerated() {
            var piece = AttributedString(w)
            piece.foregroundColor = i < reached ? accent : Color.white.opacity(0.5)
            out += piece
            if i < words.count - 1 { out += AttributedString(" ") }
        }
        return out
    }

    var body: some View {
        let expanded = ui.isExpanded
        let pill = !expanded && settings.pillNowPlaying && (music.nowPlaying?.isPlaying ?? false)
        let face = !expanded && settings.showFace
        let timerRunning = !expanded && state.timer.phase == .running
        let chargeBannerActive = !expanded && settings.chargeAnimation && (chargeBannerUntil.map { $0 > Date() } ?? false)
        let chargingNow = chargeBannerActive
        let timerLeft = timerRunning && pill
        let timerRight = timerRunning && !pill
        let extras: CGFloat = (focusOn ? 20 : 0)
            + (chargeBannerActive ? 92 : 0)
            + (timerLeft ? 44 : 0)
        let leftExt: CGFloat = (face ? 48 : (pill ? 62 : 0)) + extras
        let rightExt: CGFloat = pill ? (face ? 104 : 62) : (timerRight ? 60 : 0)
        let wide = pill || face || timerRunning
        // Current lyric line, shown INSIDE the notch (which grows taller) while collapsed and
        // playing. It ducks the instant the pointer nears the notch (notchHovered) or the deck
        // opens, so the notch snaps back to its normal waves-only size and hides nothing.
        let lyricLine: String? = (!expanded && !ui.notchHovered && settings.lyricsUnderNotch && (music.nowPlaying?.isPlaying ?? false))
            ? state.lyrics.currentLine : nil
        let lyricOn = lyricLine != nil
        let lyricH: CGFloat = lyricOn ? 24 : 0
        let flare: CGFloat = expanded ? 20 : (wide ? 10 : 6)
        let margin: CGFloat = 30
        // Keep the notch at its normal (no-lyric) width; the lyric just truncates to fit and
        // only the height grows.
        let collapsedW = metrics.notchWidth + leftExt + rightExt
        let width = expanded ? expandedSize.width - margin * 2 : collapsedW
        let height = expanded ? expandedSize.height - 14 : metrics.notchHeight + (pill ? 12 : 2) + lyricH
        let shift: CGFloat = expanded ? 0 : (rightExt - leftExt) / 2
        // The interactive/hover zone is only the physical notch, never the lyric's extra height,
        // so the lyric never blocks clicks behind it.
        let hitW = width
        let hitH = height - lyricH
        let shape = NotchShape(bottomRadius: expanded ? 30 : (wide ? 14 : 10), topFlare: flare)

        ZStack(alignment: .top) {
            shape
                .fill(
                    LinearGradient(stops: [
                        .init(color: Color.black, location: 0),
                        .init(color: Color.black, location: 0.25),
                        .init(color: Color(white: settings.glass), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    shape.fill(
                        LinearGradient(colors: [.clear, settings.accent.opacity(expanded ? settings.tint * 0.35 : 0)],
                                       startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [.clear, .clear, Color.white.opacity(expanded ? 0.16 : 0)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                )
                .frame(width: width, height: height)
                .opacity(pill && settings.waveWithMusic && settings.glowBorder ? 0 : 1)

            if settings.glowBorder {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let p = 0.5 + 0.5 * (sin(t * 2.4) * 0.5 + 0.5)
                    let c = liveGlow
                    let waving = pill && settings.waveWithMusic
                    let amp: CGFloat = waving ? CGFloat(settings.waveIntensity) * (1.2 + 4.5 * CGFloat(audio.level)) : 0
                    let radius: CGFloat = expanded ? 30 : (pill ? 14 : 10)
                    // In Mood mode the song's energy picks the dynamic (calm→breathe, mid→flow,
                    // high→comet); otherwise the user's chosen dynamic is used.
                    let effDynamic: GlowDynamic = (settings.mode == .mood ? (vibe.suggestedDynamic ?? settings.dynamic) : settings.dynamic)
                    let lineW: CGFloat = effDynamic == .pulse ? 1.2 + 0.9 * p : 1.2
                    let glowAmt = settings.glowIntensity
                    let bOpacity: Double = {
                        switch effDynamic {
                        case .breathe: return 0.55 + 0.45 * p
                        case .pulse:   return 0.3 + 0.7 * p
                        case .solid:   return 0.9
                        default:       return 0.95
                        }
                    }()
                    ZStack {
                        if waving {
                            NotchWaveOutline(bottomRadius: radius, topFlare: flare, time: t, amplitude: amp, closed: true)
                                .fill(LinearGradient(stops: [
                                    .init(color: Color.black, location: 0),
                                    .init(color: Color.black, location: 0.25),
                                    .init(color: Color(white: settings.glass), location: 1)
                                ], startPoint: .top, endPoint: .bottom))
                        }
                        // Glow = the SAME multi-colour border, just blurred, so the bloom always
                        // matches the border exactly. Glow intensity only scales how far it spreads.
                        if glowAmt > 0.01 {
                            borderOutline(effDynamic, base: c, t: t, flare: flare, radius: radius, amp: amp, lineW: lineW + 1)
                                .opacity(bOpacity * (0.5 + 0.3 * p) * min(1, 0.5 + glowAmt))
                                .blur(radius: 4 + 11 * glowAmt)
                        }
                        borderOutline(effDynamic, base: c, t: t, flare: flare, radius: radius, amp: amp, lineW: lineW)
                            .opacity(bOpacity)
                        if chargingNow {
                            NotchWaveOutline(bottomRadius: radius, topFlare: flare, time: t, amplitude: 0)
                                .trim(from: 0, to: chargeRing)
                                .stroke(Color.green.opacity(0.95), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                .shadow(color: Color.green.opacity(0.7), radius: 6)

                            // Charge "beat": a bright surge born at the bottom-centre (path ≈ 0.5) that
                            // shoots out to both sides — "tuuun" — then releases — "puff" — every cycle.
                            let beat = (t / 1.25).truncatingRemainder(dividingBy: 1)
                            let grow = min(1, beat / 0.5)
                            let g = 0.5 * (1 - pow(1 - grow, 3))
                            let fade = beat < 0.5 ? 1.0 : max(0, 1 - (beat - 0.5) / 0.5)
                            NotchWaveOutline(bottomRadius: radius, topFlare: flare, time: t, amplitude: 0)
                                .trim(from: 0.5 - g, to: 0.5 + g)
                                .stroke(Color.green.opacity(0.95 * fade), style: StrokeStyle(lineWidth: 2 + 2.6 * fade, lineCap: .round, lineJoin: .round))
                                .shadow(color: Color.green.opacity(0.9 * fade), radius: 8)
                                .shadow(color: Color.green.opacity(0.6 * fade), radius: 16)
                        }
                    }
                    .frame(width: width, height: height)
                }
                .allowsHitTesting(false)
            }

            if pill || face {
                HStack(spacing: 0) {
                    if face {
                        FaceView(stats: state.stats, music: music, audio: audio, events: state.faceEvents, timer: state.timer, weather: state.weather, focus: focus, vibe: vibe, size: metrics.notchHeight - 8)
                            .padding(.leading, 12)
                            .help(state.weather.summary ?? "")
                    } else if pill {
                        pillArtwork
                            .frame(width: metrics.notchHeight - 10, height: metrics.notchHeight - 10)
                            .padding(.leading, 12)
                    }
                    if focusOn {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(settings.accent.opacity(0.9))
                            .padding(.leading, 6)
                            .help("A Focus is on")
                    }
                    if chargingNow, let line = chargeLine {
                        Text(line)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.leading, 6)
                            .fixedSize()
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                    if timerLeft {
                        Text(state.timer.display)
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(settings.accent.opacity(0.9))
                            .padding(.leading, 6)
                    }
                    Spacer(minLength: 0)
                    if pill {
                        HStack(spacing: 8) {
                            if face {
                                pillArtwork.frame(width: metrics.notchHeight - 10, height: metrics.notchHeight - 10)
                            }
                            Visualizer(active: true, color: settings.accent, barCount: 5, maxHeight: metrics.notchHeight - 16, energy: Double(vibe.energy ?? 50) / 100)
                        }
                        .padding(.trailing, 14)
                    } else if timerRight {
                        Text(state.timer.display)
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(settings.accent)
                            .padding(.trailing, 14)
                    }
                }
                .frame(width: width, height: metrics.notchHeight + 4)
                .overlay(alignment: .bottom) {
                    if let v = ui.volumeFlash {
                        GeometryReader { g in
                            Capsule().fill(Color.white.opacity(0.18))
                                .overlay(alignment: .leading) { Capsule().fill(settings.accent).frame(width: g.size.width * v) }
                        }
                        .frame(width: 90, height: 3)
                        .padding(.bottom, 3)
                        .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }

            if let lyricLine {
                // Sits INSIDE the black notch, just below the physical notch, so the notch reads
                // as one longer shape. Words already sung are tinted the accent colour.
                Text(DeckView.coloredLyric(lyricLine, progress: state.lyrics.lineProgress, accent: settings.accent))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: width - 28)
                    .padding(.top, metrics.notchHeight + (pill ? 12 : 2) - 2)
                    .id(state.lyrics.index)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if !expanded {
                Color.black.opacity(0.001)
                    .frame(width: width, height: height)
                    .onTapGesture(count: 2) { if settings.openOnHover && settings.clickActions { ui.suppressHover = true; music.next() } }
                    .onTapGesture(count: 1) {
                        if !settings.openOnHover {
                            ui.expandHandler?()
                        } else if settings.clickActions {
                            ui.suppressHover = true
                            music.playPause()
                        }
                    }
            }

            if expanded {
                VStack(spacing: 6) {
                    header
                    pages
                }
                .padding(.horizontal, 18)
                .padding(.top, metrics.notchHeight + 4)
                .padding(.bottom, 12)
                .frame(width: width, height: height)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .offset(x: shift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onAppear { publishHitRect(expanded: expanded, width: hitW, height: hitH, shift: shift) }
        .onChange(of: state.chargePing) { _, _ in
            guard settings.chargeAnimation else { return }
            chargeBannerUntil = Date().addingTimeInterval(6)
            chargeRing = 0
            withAnimation(.easeOut(duration: 1.6)) { chargeRing = max(0.04, state.stats.batteryLevel) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
                if let until = chargeBannerUntil, until <= Date() {
                    withAnimation(.easeOut(duration: 0.5)) { chargeRing = 0 }
                    chargeBannerUntil = nil
                }
            }
        }
        .onChange(of: state.stats.isCharging) { _, charging in
            guard settings.chargeAnimation, charging else {
                chargeBannerUntil = nil
                chargeRing = 0
                return
            }
            chargeBannerUntil = Date().addingTimeInterval(6)
            chargeRing = 0
            withAnimation(.easeOut(duration: 1.6)) { chargeRing = max(0.04, state.stats.batteryLevel) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
                if let until = chargeBannerUntil, until <= Date() {
                    withAnimation(.easeOut(duration: 0.5)) { chargeRing = 0 }
                    chargeBannerUntil = nil
                }
            }
        }
        .onChange(of: "\(expanded)|\(hitW)|\(hitH)|\(shift)") { _, _ in
            publishHitRect(expanded: expanded, width: hitW, height: hitH, shift: shift)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: pill)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: lyricLine != nil)
        .animation(.easeOut(duration: 0.24), value: state.lyrics.index)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: face)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: timerRunning)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: focusOn)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: chargeBannerActive)
        .animation(.easeOut(duration: 0.2), value: ui.volumeFlash == nil)
    }

    private var pillArtwork: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack {
            shape.fill(Color.white.opacity(0.12))
            if let art = music.artwork {
                Image(nsImage: art).resizable().scaledToFill()
                    .clipShape(shape)
            } else {
                Image(systemName: "music.note").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .clipShape(shape)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(clockText)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            Text("·")
                .foregroundStyle(.white.opacity(0.3))
            Text(currentSpaceTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            HStack(spacing: 4) {
                PageTab(title: "Spaces", systemImage: "rectangle.3.group.fill", index: 0)
                PageTab(title: "Music", systemImage: "music.note", index: 1)
                PageTab(title: "System", systemImage: "gauge.with.dots.needle.33percent", index: 2)
                PageTab(title: ui.page == 3 ? "Shelf" : nil, systemImage: "tray.full.fill", index: 3, badge: state.shelf.items.count)
                PageTab(title: ui.page == 4 ? "Clipboard" : nil, systemImage: "doc.on.clipboard.fill", index: 4)
                PageTab(title: ui.page == 5 ? "Timer" : nil, systemImage: "timer", index: 5, active: state.timer.phase == .running)
                PageTab(systemImage: "gearshape.fill", index: 6)
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .frame(height: 30)
    }

    private var clockText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: state.stats.now)
    }

    private var currentSpaceTitle: String {
        state.spaces.spaces(for: metrics.screen).first(where: { $0.id == state.spaces.activeSpaceID(for: metrics.screen) })?.title ?? "Desktop"
    }

    private var pages: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SpacesPage(spaces: state.spaces, screen: metrics.screen)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                MusicPage(music: state.music, lyrics: state.lyrics, vibe: state.songVibe)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                SystemPage(stats: state.stats)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                ShelfPage(shelf: state.shelf)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                ClipboardPage(clipboard: state.clipboard)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                TimerPage(timer: state.timer)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                SettingsPage(focus: focus)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .offset(x: -CGFloat(ui.page) * geo.size.width)
        }
        .clipped()
    }
}

struct PageTab: View {
    @EnvironmentObject var ui: PanelState
    @EnvironmentObject var settings: DeckSettings
    var title: String? = nil
    let systemImage: String
    let index: Int
    var badge: Int = 0
    var active: Bool = false
    @State private var hovering = false

    var body: some View {
        let selected = ui.page == index
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { ui.page = index }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 && !selected {
                            Text("\(badge)").font(.system(size: 7, weight: .bold)).foregroundStyle(settings.onAccent)
                                .padding(.horizontal, 3).frame(height: 10).background(Capsule().fill(settings.accent)).offset(x: 7, y: -6)
                        } else if active && !selected {
                            Circle().fill(settings.accent).frame(width: 5, height: 5).offset(x: 4, y: -4)
                        }
                    }
                if let title {
                    Text(title).font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(selected ? settings.onAccent : Color.white.opacity(hovering ? 0.95 : 0.65))
            .padding(.horizontal, title == nil ? 8 : 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? settings.accent : Color.white.opacity(hovering ? 0.10 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var topFlare: CGFloat
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topFlare) }
        set { bottomRadius = newValue.first; topFlare = newValue.second }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var c = self
        c.inset += amount
        return c
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        let r = min(bottomRadius, rect.height / 2)
        let f = topFlare
        p.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchOutline: Shape {
    var bottomRadius: CGFloat
    var topFlare: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topFlare) }
        set { bottomRadius = newValue.first; topFlare = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height / 2)
        let f = topFlare
        p.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

struct NotchWaveOutline: Shape {
    var bottomRadius: CGFloat
    var topFlare: CGFloat
    var time: Double
    var amplitude: CGFloat
    var closed: Bool = false

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2)
        let f = topFlare
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f), control: CGPoint(x: rect.minX, y: rect.minY))
        if amplitude <= 0.01 {
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        } else {
            let side = max(0, rect.height - f - r)
            let arc = CGFloat.pi / 2 * r
            let bottom = max(0, rect.width - 2 * r)
            let total = side * 2 + arc * 2 + bottom
            let step: CGFloat = 3
            var s: CGFloat = 0
            while s <= total {
                var pt: CGPoint
                var n: CGPoint
                if s < side {
                    pt = CGPoint(x: rect.minX, y: rect.minY + f + s); n = CGPoint(x: -1, y: 0)
                } else if s < side + arc {
                    let a = (s - side) / r
                    let cx = rect.minX + r, cy = rect.maxY - r
                    pt = CGPoint(x: cx - r * cos(a), y: cy + r * sin(a)); n = CGPoint(x: -cos(a), y: sin(a))
                } else if s < side + arc + bottom {
                    pt = CGPoint(x: rect.minX + r + (s - side - arc), y: rect.maxY); n = CGPoint(x: 0, y: 1)
                } else if s < side + arc * 2 + bottom {
                    let a = (s - side - arc - bottom) / r
                    let cx = rect.maxX - r, cy = rect.maxY - r
                    pt = CGPoint(x: cx + r * sin(a), y: cy + r * cos(a)); n = CGPoint(x: sin(a), y: cos(a))
                } else {
                    pt = CGPoint(x: rect.maxX, y: rect.maxY - r - (s - side - arc * 2 - bottom)); n = CGPoint(x: 1, y: 0)
                }
                let edge = min(1, min(s, total - s) / 14)
                let w = sin(Double(s) / 38 * 2 * .pi - time * 5.5) * 0.6 + sin(Double(s) / 17 * 2 * .pi + time * 8.1) * 0.4
                let d = amplitude * CGFloat(w) * edge
                p.addLine(to: CGPoint(x: pt.x + n.x * d, y: pt.y + n.y * d))
                s += step
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        }
        p.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        if closed { p.closeSubpath() }
        return p
    }
}

// MARK: - Shared controls

struct DeckSlider: View {
    let value: Double
    var icon: String? = nil
    var accent: Color = .white
    var onChange: (Double) -> Void
    var onIconTap: (() -> Void)? = nil
    @State private var dragValue: Double?
    @State private var hovering = false
    @State private var lastSent = Date.distantPast
    @State private var releaseItem: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Button { onIconTap?() } label: {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                let shown = min(max(dragValue ?? value, 0), 1)
                let live = hovering || dragValue != nil
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(accent).frame(width: geo.size.width * shown)
                    Circle().fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: geo.size.width * shown - 5)
                        .opacity(live ? 1 : 0)
                }
                .frame(height: live ? 5 : 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let f = min(max(g.location.x / geo.size.width, 0), 1)
                            dragValue = f
                            releaseItem?.cancel()
                            if Date().timeIntervalSince(lastSent) > 0.1 {
                                lastSent = Date()
                                onChange(f)
                            }
                        }
                        .onEnded { g in
                            let f = min(max(g.location.x / geo.size.width, 0), 1)
                            dragValue = f
                            onChange(f)
                            let item = DispatchWorkItem { dragValue = nil }
                            releaseItem = item
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
                        }
                )
            }
            .onHover { hovering = $0 }
        }
    }
}

struct RingGauge: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
        }
    }
}

struct Tile<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Spaces

struct SpacesPage: View {
    @ObservedObject var spaces: SpacesManager
    let screen: NSScreen

    var body: some View {
        GeometryReader { geo in
            let items = spaces.spaces(for: screen)
            let activeID = spaces.activeSpaceID(for: screen)
            let count = max(items.count, 1)
            let columns = min(count, 4)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let gap: CGFloat = 10
            let showBanner = !spaces.hasScreenCapture || !spaces.hasAccessibility || !spaces.directHotkeysEnabled
            let bannerH: CGFloat = showBanner ? 30 : 0
            let cardW = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cardH = min(cardW * 0.625, (geo.size.height - bannerH - gap * CGFloat(rows)) / CGFloat(rows))

            VStack(spacing: gap) {
                if showBanner {
                    PermissionBanner(needsScreen: !spaces.hasScreenCapture,
                                     needsAX: !spaces.hasAccessibility,
                                     needsHotkeys: !spaces.directHotkeysEnabled,
                                     enableHotkeys: { spaces.enableDirectHotkeys() })
                }
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { col in
                            let idx = row * columns + col
                            if idx < items.count {
                                SpaceCard(space: items[idx],
                                          thumbnail: spaces.thumbnails[items[idx].id],
                                          isActive: items[idx].id == activeID)
                                    .frame(width: cardW, height: cardH)
                                    .onTapGesture { spaces.switchTo(items[idx]) }
                            } else {
                                Color.clear.frame(width: cardW, height: cardH)
                            }
                        }
                    }
                }
                if items.isEmpty {
                    Text("No Spaces found")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 13))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

struct PermissionBanner: View {
    let needsScreen: Bool
    let needsAX: Bool
    var needsHotkeys: Bool = false
    var enableHotkeys: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.yellow).font(.system(size: 11))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
            if needsScreen {
                SmallLinkButton(title: "Screen Recording", url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            }
            if needsAX {
                SmallLinkButton(title: "Accessibility", url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
            if needsHotkeys && !needsAX {
                Button(action: enableHotkeys) {
                    Text("Enable Ctrl+1–9")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private var message: String {
        switch (needsScreen, needsAX) {
        case (true, true): return "Previews and switching need permissions"
        case (true, false): return "Space previews need Screen Recording"
        case (false, true): return "Switching needs Accessibility"
        default: return "Jump straight to a desktop"
        }
    }
}

struct SmallLinkButton: View {
    let title: String
    let url: String

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.9)))
        }
        .buttonStyle(.plain)
    }
}

struct SpaceCard: View {
    @EnvironmentObject var settings: DeckSettings
    let space: SpaceInfo
    let thumbnail: NSImage?
    let isActive: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            shape.fill(Color.white.opacity(0.06))

            if let thumbnail {
                Color.clear
                    .overlay(Image(nsImage: thumbnail).resizable().scaledToFill())
                    .clipShape(shape)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: space.isFullscreen ? "arrow.up.left.and.arrow.down.right" : "macwindow")
                        .font(.system(size: 20, weight: .light))
                    Text("Loading preview…")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                .clipShape(shape)

            HStack(spacing: 6) {
                if isActive {
                    Circle().fill(settings.accent).frame(width: 6, height: 6)
                        .shadow(color: settings.accent.opacity(0.8), radius: 4)
                }
                Text(space.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: -5) {
                    ForEach(Array(space.appPIDs.prefix(4)), id: \.self) { pid in
                        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                        }
                    }
                }
            }
            .padding(8)

            shape.strokeBorder(
                isActive ? settings.accent.opacity(0.95) : Color.white.opacity(hovering ? 0.45 : 0.12),
                lineWidth: isActive ? 1.5 : 1
            )
        }
        .shadow(color: isActive ? settings.accent.opacity(0.22) : .clear, radius: 10)
        .scaleEffect(hovering ? 1.035 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(shape)
    }
}

// MARK: - Music

struct MusicPage: View {
    @ObservedObject var music: MusicController
    @ObservedObject var lyrics: LyricsController
    @ObservedObject var vibe: SongVibeController
    @EnvironmentObject var settings: DeckSettings
    @State private var pulse = false

    var body: some View {
        Group {
            if let np = music.nowPlaying {
                HStack(alignment: .center, spacing: 22) {
                    artworkView(np)
                        .frame(width: 168, height: 168)
                        .onTapGesture { music.openPlayer() }
                        .id(np.trackKey)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(np.title.isEmpty ? "Nothing playing" : np.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            if settings.showVisualizer {
                                Visualizer(active: np.isPlaying, color: settings.accent)
                            }
                        }
                        Text(np.artist)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        Text(np.album)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)

                        if let caption = vibe.caption, !caption.isEmpty {
                            HStack(spacing: 6) {
                                Text(caption)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .italic()
                                    .foregroundStyle((vibe.color ?? settings.accent).opacity(0.95))
                                    .lineLimit(1)
                                if let m = vibe.mood, !m.isEmpty, m != "unknown" {
                                    Text("· \(m)")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.top, 3)
                            .transition(.opacity)
                        }

                        if settings.showLyrics {
                            LyricsStrip(lyrics: lyrics, accent: settings.accent)
                                .frame(height: 42)
                                .padding(.top, 4)
                        }

                        Spacer(minLength: 2)

                        ProgressScrubber(position: music.livePosition, duration: np.duration, accent: settings.accent) { music.seek(to: $0) }
                            .padding(.top, 2)

                        HStack(spacing: 18) {
                            ControlButton(system: "shuffle", active: np.shuffle, activeColor: activeColor(np)) { music.toggleShuffle() }
                            Spacer()
                            ControlButton(system: "backward.fill", size: 17) { music.previous() }
                            ControlButton(system: np.isPlaying ? "pause.fill" : "play.fill", size: 18, prominent: true) { music.playPause() }
                            ControlButton(system: "forward.fill", size: 17) { music.next() }
                            Spacer()
                            ControlButton(system: np.repeatMode == .one ? "repeat.1" : "repeat", active: np.repeatMode != .off, activeColor: activeColor(np)) { music.cycleRepeat() }
                        }

                        if settings.showVolume {
                            DeckSlider(value: Double(np.volume) / 100,
                                       icon: volumeIcon(np.volume),
                                       accent: settings.accent,
                                       onChange: { music.setVolume(Int(($0 * 100).rounded())) })
                                .frame(height: 18)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 176)
                }
                .padding(.top, 2)
                .padding(.leading, 26)
                .padding(.bottom, 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: np.trackKey)
                .onAppear { updatePulse(np.isPlaying) }
                .onChange(of: np.isPlaying) { _, playing in updatePulse(playing) }
                .onChange(of: settings.animateArtwork) { _, _ in updatePulse(np.isPlaying) }
            } else if let player = music.activePlayer {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.yellow)
                    Text("\(player.appName) is running but NotchDeck can't talk to it")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(music.lastError ?? "Allow NotchDeck to control \(player.appName) under Automation.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        SmallLinkButton(title: "Open Automation settings", url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                        Button("Retry") { music.poll() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 30, weight: .light))
                    Text("Open Spotify or Apple Music to control playback here")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func activeColor(_ np: NowPlaying) -> Color {
        if settings.accentHue != nil { return settings.accent }
        return np.player == .spotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : Color(red: 0.98, green: 0.24, blue: 0.36)
    }

    private func volumeIcon(_ v: Int) -> String {
        switch v {
        case 0: return "speaker.slash.fill"
        case 1..<34: return "speaker.wave.1.fill"
        case 34..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func updatePulse(_ playing: Bool) {
        if playing && settings.animateArtwork {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.5)) { pulse = false }
        }
    }

    private func artworkView(_ np: NowPlaying) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack {
            if settings.animateArtwork, let glow = music.artworkGlow {
                Image(nsImage: glow)
                    .resizable()
                    .frame(width: 336, height: 336)
                    .mask(
                        RadialGradient(colors: [.white, .white, .white.opacity(0)],
                                       center: .center, startRadius: 60, endRadius: 104)
                            .frame(width: 336, height: 336)
                    )
                    .opacity(pulse ? 1.0 : 0.55)
                    .scaleEffect(pulse ? 1.06 : 1.0)
                    .allowsHitTesting(false)
            }

            ZStack(alignment: .bottomLeading) {
                shape.fill(Color.white.opacity(0.08))
                if let art = music.artwork {
                    Color.clear
                        .overlay(Image(nsImage: art).resizable().scaledToFill())
                        .clipShape(shape)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.white.opacity(0.35))
                }
                ZStack {
                    Circle().fill(np.player == .spotify ? Color(red: 0.11, green: 0.73, blue: 0.33) : Color(red: 0.98, green: 0.24, blue: 0.36))
                    Image(systemName: np.player == .spotify ? "waveform" : "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .offset(x: 8, y: -8)
            }
            .frame(width: 168, height: 168)
            .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
            .scaleEffect(pulse ? 1.025 : 1.0)
        }
    }
}

struct Visualizer: View {
    let active: Bool
    var color: Color = .white
    var barCount: Int = 6
    var maxHeight: CGFloat = 16
    /// Song energy 0…1 (from the mood read): faster and taller bars at higher energy.
    var energy: Double = 0.5

    var body: some View {
        // Period shrinks with energy (0.5→1.35s calm, 1→0.55s intense) so the bars beat faster.
        let period = 1.35 - 0.8 * max(0, min(1, energy))
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { tl in
            let phase = tl.date.timeIntervalSinceReferenceDate * (2 * .pi / period)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(active ? 0.9 : 0.3))
                        .frame(width: 3, height: height(for: i, phase: phase))
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
    }

    private func height(for i: Int, phase: Double) -> CGFloat {
        guard active else { return 3 }
        let v = sin(phase + Double(i) * 1.3) * 0.5 + 0.5
        let scale = 0.5 + 0.7 * max(0, min(1, energy))   // taller when energetic
        return 3 + CGFloat(v) * (maxHeight - 3) * CGFloat(scale)
    }
}

struct ControlButton: View {
    @EnvironmentObject var settings: DeckSettings
    let system: String
    var size: CGFloat = 14
    var active: Bool = false
    var activeColor: Color? = nil
    var prominent: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle().fill(settings.accent).frame(width: 36, height: 36)
                }
                Image(systemName: system)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(prominent ? settings.onAccent : (active ? (activeColor ?? settings.accent) : (hovering ? Color.white : Color.white.opacity(0.75))))
            }
            .frame(width: prominent ? 40 : max(size + 14, 30), height: prominent ? 40 : max(size + 14, 30))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct ProgressScrubber: View {
    let position: Double
    let duration: Double
    var accent: Color = .white
    let onSeek: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let frac = duration > 0 ? min(max(position / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(accent).frame(width: geo.size.width * frac)
                    if hovering {
                        Circle().fill(Color.white).frame(width: 9, height: 9)
                            .offset(x: geo.size.width * frac - 4.5)
                    }
                }
                .frame(height: hovering ? 5 : 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard duration > 0 else { return }
                    let f = min(max(value.location.x / geo.size.width, 0), 1)
                    onSeek(f * duration)
                })
            }
            .frame(height: 14)
            .onHover { hovering = $0 }
            HStack {
                Text(format(position))
                Spacer()
                Text("-" + format(max(0, duration - position)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func format(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - System

struct SystemPage: View {
    @ObservedObject var stats: SystemStats
    @EnvironmentObject var settings: DeckSettings
    @EnvironmentObject var ui: PanelState

    var body: some View {
        GeometryReader { geo in
            let widgets = settings.widgets
            let rows = stride(from: 0, to: widgets.count, by: 4).map { Array(widgets[$0..<min($0 + 4, widgets.count)]) }
            let showDock = settings.showQuickActions || settings.showSystemVolume
            let gap: CGFloat = 8
            let dockH: CGFloat = showDock ? 38 : 0
            let rowCount = max(rows.count, 1)
            let avail = geo.size.height - dockH - (showDock ? gap : 0) - gap * CGFloat(rowCount - 1)
            let tileH = min(avail / CGFloat(rowCount), 120)
            let slots = rows.count > 1 ? 4 : max(widgets.count, 1)

            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(0..<slots, id: \.self) { i in
                            if i < row.count {
                                WidgetTile(widget: row[i], stats: stats)
                                    .frame(height: tileH)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: tileH)
                            }
                        }
                    }
                }
                if widgets.isEmpty {
                    Text("No widgets enabled — turn some on in Settings")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showDock {
                    dock.frame(height: dockH)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(.top, 4)
    }

    private var dock: some View {
        HStack(spacing: 6) {
            if settings.showQuickActions {
                QuickButton(symbol: "lock.fill", help: "Lock screen") { QuickActions.lockScreen() }
                QuickButton(symbol: "moon.fill", help: "Sleep display") { QuickActions.sleepDisplay() }
                QuickButton(symbol: "rectangle.3.group", help: "Mission Control") {
                    ui.collapseHandler?()
                    QuickActions.missionControl()
                }
                QuickButton(symbol: "circle.lefthalf.filled", help: "Toggle dark mode") { QuickActions.toggleDarkMode() }
                QuickButton(symbol: "camera.viewfinder", help: "Screenshot") {
                    ui.collapseHandler?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { QuickActions.screenshot() }
                }
                QuickButton(symbol: "cup.and.saucer.fill", help: "Keep awake", active: stats.keepAwake) { stats.toggleKeepAwake() }
            }
            Spacer(minLength: 8)
            if settings.showSystemVolume {
                DeckSlider(value: stats.isMuted ? 0 : stats.outputVolume,
                           icon: systemVolumeIcon,
                           accent: settings.accent,
                           onChange: { stats.setOutputVolume($0) },
                           onIconTap: { stats.toggleMute() })
                    .frame(width: 190, height: 18)
            }
        }
        .padding(.horizontal, 10)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var systemVolumeIcon: String {
        if stats.isMuted || stats.outputVolume == 0 { return "speaker.slash.fill" }
        if stats.outputVolume < 0.34 { return "speaker.wave.1.fill" }
        if stats.outputVolume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct QuickButton: View {
    @EnvironmentObject var settings: DeckSettings
    let symbol: String
    let help: String
    var active: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? settings.onAccent : Color.white.opacity(hovering ? 1 : 0.75))
                .frame(width: 28, height: 28)
                .background(Circle().fill(active ? settings.accent : Color.white.opacity(hovering ? 0.14 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct WidgetTile: View {
    let widget: SystemWidget
    @ObservedObject var stats: SystemStats
    @EnvironmentObject var state: DeckState
    @EnvironmentObject var settings: DeckSettings

    var body: some View {
        Tile(padding: 12) {
            switch widget {
            case .clock: clock
            case .battery: battery
            case .cpu:
                gauge(title: "CPU", value: stats.cpuUsage, color: settings.accent,
                      big: "\(Int(stats.cpuUsage * 100))%",
                      sub: "\(ProcessInfo.processInfo.activeProcessorCount) cores")
            case .memory:
                gauge(title: "Memory", value: stats.memoryTotal > 0 ? stats.memoryUsed / stats.memoryTotal : 0, color: settings.accent,
                      big: "\(Int((stats.memoryTotal > 0 ? stats.memoryUsed / stats.memoryTotal : 0) * 100))%",
                      sub: gb(stats.memoryUsed) + " of " + gb(stats.memoryTotal))
            case .disk:
                gauge(title: "Disk", value: stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal : 0, color: settings.accent,
                      big: "\(Int((stats.diskTotal > 0 ? stats.diskUsed / stats.diskTotal : 0) * 100))%",
                      sub: gb(max(0, stats.diskTotal - stats.diskUsed)) + " free")
            case .network: network
            case .thermal:
                info(title: "Thermals", symbol: "thermometer.medium", color: thermalColor, big: thermalLabel, sub: "Thermal pressure")
            case .topProcess: topProcess
            case .uptime:
                info(title: "Uptime", symbol: "hourglass", color: settings.accent, big: uptimeString, sub: "since " + bootString)
            case .weather: weather
            }
        }
    }

    private var weather: some View {
        let w = state.weather
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: w.condition?.symbol ?? "cloud.sun.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.accent)
                Text(w.place ?? w.condition?.label ?? "Weather")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            if let c = w.celsius {
                Text(w.display(c))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    ForEach(w.hours.filter { $0.date > Date() }.prefix(3)) { h in
                        HStack(spacing: 2) {
                            Text(hourLabel(h.date))
                                .foregroundStyle(.white.opacity(0.4))
                            Image(systemName: h.condition.symbol)
                                .foregroundStyle(.white.opacity(0.65))
                            Text(w.display(h.celsius))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(settings.weatherOn ? (w.problem ?? "Loading…") : "Weather off")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.weatherOn, w.problem != nil {
                    Button("Set city") { WeatherController.askForCity(current: settings.weatherCity) { settings.weatherCity = $0 } }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(settings.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .help(state.weather.summary ?? "")
    }

    private func hourLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH"
        return f.string(from: d) + "h"
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(f("HH:mm"))
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(f("EEEE"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.accent.opacity(0.95))
            Text(f("d MMMM"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var battery: some View {
        HStack(spacing: 10) {
            ZStack {
                RingGauge(value: stats.batteryLevel, color: batteryColor, lineWidth: 5)
                if stats.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.yellow)
                } else {
                    Text("\(Int(stats.batteryLevel * 100))")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.hasBattery ? "Battery" : "Power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(batteryDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "network").foregroundStyle(settings.accent).font(.system(size: 11))
                Text("Network").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(settings.accent)
                Text(rate(stats.downRate)).font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                Text(rate(stats.upRate)).font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var topProcess: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = topProcessIcon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "flame.fill").font(.system(size: 20)).foregroundStyle(settings.accent)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Top App").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text(stats.topProcessName.isEmpty ? "—" : stats.topProcessName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(String(format: "%.0f%% CPU", stats.topProcessCPU * 100))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }

    private var topProcessIcon: NSImage? {
        NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == stats.topProcessName })?.icon
    }

    private func gauge(title: String, value: Double, color: Color, big: String, sub: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RingGauge(value: value, color: color, lineWidth: 5)
                Text(big)
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text(sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func info(title: String, symbol: String, color: Color, big: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(color).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Text(big)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
    }

    private func f(_ format: String) -> String {
        let df = DateFormatter()
        df.dateFormat = format
        return df.string(from: stats.now)
    }

    private func gb(_ bytes: Double) -> String {
        bytes >= 1_000_000_000_000 ? String(format: "%.2f TB", bytes / 1_000_000_000_000) : String(format: "%.0f GB", bytes / 1_000_000_000)
    }

    private func rate(_ bps: Double) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f KB/s", bps / 1_000) }
        return "0 KB/s"
    }

    private var uptimeString: String {
        let t = Int(ProcessInfo.processInfo.systemUptime)
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60
        return d > 0 ? "\(d)d \(h)h" : "\(h)h \(m)m"
    }

    private var bootString: String {
        let boot = Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
        let df = DateFormatter()
        df.dateFormat = "EEE HH:mm"
        return df.string(from: boot)
    }

    private var batteryDetail: String {
        guard stats.hasBattery else { return "Plugged in" }
        if stats.isCharging {
            if let m = stats.batteryMinutes { return "\(m / 60)h \(m % 60)m to full" }
            return "Charging"
        }
        if let m = stats.batteryMinutes { return "\(m / 60)h \(m % 60)m left" }
        return "\(Int(stats.batteryLevel * 100))% remaining"
    }

    private var batteryColor: Color {
        if stats.isCharging { return .green }
        if stats.batteryLevel < 0.2 { return .red }
        if stats.batteryLevel < 0.4 { return .orange }
        return settings.accent
    }

    private var thermalLabel: String {
        switch stats.thermalState {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private var thermalColor: Color {
        switch stats.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        default: return .red
        }
    }
}


// MARK: - Shelf

struct ShelfPage: View {
    @ObservedObject var shelf: ShelfManager
    @EnvironmentObject var settings: DeckSettings

    var body: some View {
        VStack(spacing: 8) {
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(shelf.isDragTarget ? settings.accent : .white.opacity(0.45))
                    Text(shelf.isDragTarget ? "Drop to keep it here" : "Drag files onto the notch to park them here")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Then AirDrop, zip, copy or drag them out again.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5])).foregroundStyle(shelf.isDragTarget ? settings.accent : Color.white.opacity(0.15)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfCard(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(shelf.isDragTarget ? 0.08 : 0.03)))
                HStack(spacing: 6) {
                    ShelfAction(title: "AirDrop", symbol: "wifi") { shelf.airdrop() }
                    ShelfAction(title: "Zip", symbol: "doc.zipper") { shelf.compress() }
                    ShelfAction(title: "Copy", symbol: "doc.on.doc") { shelf.copyFiles() }
                    ShelfAction(title: "To Downloads", symbol: "arrow.down.to.line") { shelf.moveToDownloads() }
                    Spacer()
                    if let s = shelf.status {
                        Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(settings.accent).transition(.opacity)
                    }
                    ShelfAction(title: "Clear", symbol: "xmark") { shelf.clear() }
                }
                .frame(height: 30)
            }
        }
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.2), value: shelf.status)
    }
}

struct ShelfCard: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfManager
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
            Text(item.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
            Text(item.size).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 104, height: 118)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain).padding(4)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Reveal in Finder") { shelf.reveal(item) }
            Button("Copy path") { shelf.copyPath(item) }
            Divider()
            Button("Remove from shelf") { shelf.remove(item) }
        }
    }
}

struct ShelfAction: View {
    @EnvironmentObject var settings: DeckSettings
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Clipboard

struct ClipboardPage: View {
    @ObservedObject var clipboard: ClipboardManager
    @EnvironmentObject var settings: DeckSettings
    @EnvironmentObject var ui: PanelState

    var body: some View {
        VStack(spacing: 6) {
            if clipboard.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 30, weight: .light))
                    Text("Everything you copy shows up here").font(.system(size: 12, weight: .medium))
                    Text("Click to paste it again · pin what you reuse").font(.system(size: 10))
                }
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
                        ForEach(clipboard.items) { item in
                            ClipRow(item: item, clipboard: clipboard) {
                                ui.collapseHandler?()
                                clipboard.paste(item)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Text("\(clipboard.items.count) items · click to paste · ⇧click copies only")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    ShelfAction(title: "Clear", symbol: "xmark") { clipboard.clear() }
                }
                .frame(height: 24)
            }
        }
        .padding(.top, 4)
    }
}

struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardManager
    let paste: () -> Void
    @EnvironmentObject var settings: DeckSettings
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let img = item.image {
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let u = item.fileURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 26, height: 26)
                } else {
                    Image(systemName: item.kind).font(.system(size: 12, weight: .semibold)).foregroundStyle(settings.accent).frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(settings.accent.opacity(0.12)))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text(item.date, style: .time).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 4)
            Button { clipboard.togglePin(item) } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.pinned ? settings.accent : .white.opacity(hovering ? 0.6 : 0.2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0.05)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) { clipboard.copy(item) } else { paste() }
        }
    }
}

// MARK: - Timer

struct TimerPage: View {
    @ObservedObject var timer: TimerManager
    @EnvironmentObject var settings: DeckSettings

    private var phaseLabel: String {
        if timer.pomodoro { return timer.onBreak ? "Break · round \(timer.pomodoroRound)" : "Focus · round \(timer.pomodoroRound)" }
        switch timer.phase {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .done: return "Done"
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle().trim(from: 0, to: timer.progress)
                    .stroke(timer.phase == .done ? Color.green : settings.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.progress)
                VStack(spacing: 1) {
                    Text(timer.display)
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(phaseLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settings.accent.opacity(0.9))
                }
            }
            .frame(width: 190, height: 190)
            .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("Presets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach([5, 15, 25, 45, 60], id: \.self) { m in
                        Chip(title: "\(m)m", symbol: "timer", on: !timer.pomodoro && Int(timer.total / 60) == m && timer.phase != .running) {
                            timer.pomodoro = false
                            timer.set(minutes: Double(m))
                        }
                    }
                }
                HStack(spacing: 6) {
                    Chip(title: "Pomodoro 25 / 5", symbol: "leaf.fill", on: timer.pomodoro) {
                        timer.pomodoro.toggle()
                        if timer.pomodoro { timer.reset(); timer.set(minutes: 25) }
                    }
                    Chip(title: "+5 min", symbol: "plus", on: false) {
                        timer.pomodoro = false
                        timer.set(minutes: min(180, timer.total / 60 + 5))
                    }
                }
                .help("Pomodoro cycles 25 minutes of focus with 5-minute breaks, and a longer break every fourth round.")

                HStack(spacing: 10) {
                    Button { timer.toggle() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: timer.phase == .running ? "pause.fill" : "play.fill")
                            Text(timer.phase == .running ? "Pause" : (timer.phase == .paused ? "Resume" : "Start"))
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(settings.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(settings.accent))
                    }
                    .buttonStyle(.plain)
                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Reset")
                }
                .padding(.top, 2)

                Text(timer.isActive
                     ? "The face focuses and the notch shows the countdown while this runs."
                     : "Pick a length, hit start — the countdown rides in the notch.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}
struct SettingsPage: View {
    @EnvironmentObject var settings: DeckSettings
    @EnvironmentObject var state: DeckState
    @ObservedObject var focus: FocusMonitor

    private func glowModeHelp(_ m: GlowMode) -> String {
        switch m {
        case .accent: return "Glow follows the accent color above."
        case .custom: return "Pick a fixed color from the swatches."
        case .album: return "Glow takes its color from the album art that is playing."
        case .wallpaper: return "Glow takes its color from your desktop picture."
        case .mood: return "Glow takes on the song's mood color, read on-device by Apple Intelligence."
        }
    }

    private func glowDynamicHelp(_ d: GlowDynamic) -> String {
        switch d {
        case .breathe: return "The chosen color softly fades in and out."
        case .pulse: return "A stronger, sharper heartbeat pulse in the chosen color."
        case .flow: return "The chosen color and its neighbours flow around the border."
        case .rainbow: return "A full RGB spectrum flows around the border (ignores the color)."
        case .comet: return "A bright highlight races around a dim border in the chosen color."
        case .solid: return "A steady, non-animated border in the chosen color."
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    appearanceTile
                    glowTile
                    faceTile
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    generalTile
                    weatherTile
                    musicTile
                }
                .fixedSize(horizontal: false, vertical: true)
                widgetsTile
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private var appearanceTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Appearance", symbol: "paintpalette.fill")
                Text("Accent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(ThemePreset.allCases) { p in
                        Swatch(hex: p.hex, selected: settings.accentHex == p.hex) { settings.accentHex = p.hex }
                    }
                }
                HueBar(hue: settings.accentHue) { settings.setAccent(hue: $0) }
                    .frame(height: 14)
                LabeledSlider(title: "Glass", icon: "sun.max.fill", value: (settings.glass - 0.04) / 0.26) { settings.glass = 0.04 + $0 * 0.26 }
                LabeledSlider(title: "Tint", icon: "drop.fill", value: settings.tint) { settings.tint = $0 }
                Spacer(minLength: 0)
                Button { settings.reset() } label: {
                    Text("Reset to defaults")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var glowTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Glow", symbol: "sparkle")
                Chip(title: "Glowing border", symbol: "sparkle", on: settings.glowBorder) { settings.glowBorder.toggle() }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 2), spacing: 5) {
                    ForEach(GlowMode.allCases) { m in
                        Chip(title: m.title, symbol: m.symbol, on: settings.mode == m) { settings.glowMode = m.rawValue }
                            .help(glowModeHelp(m))
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                    ForEach(GlowDynamic.allCases) { dyn in
                        Chip(title: dyn.title, symbol: dyn.symbol, on: settings.dynamic == dyn) { settings.glowDynamic = dyn.rawValue }
                            .help(glowDynamicHelp(dyn))
                    }
                }
                HStack(spacing: 5) {
                    Button { settings.glowMode = "custom"; settings.glowHex = "" } label: {
                        ZStack {
                            Circle().fill(settings.accent)
                            Image(systemName: "paintbrush.pointed.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(settings.onAccent)
                        }
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(settings.glowHex.isEmpty ? 1 : 0.2), lineWidth: settings.glowHex.isEmpty ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help("Follow the accent color")
                    ForEach(ThemePreset.allCases.filter { $0 != .mono }) { p in
                        Button { settings.glowHex = p.hex } label: {
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: p.hex) ?? .white))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.white.opacity(settings.glowHex == p.hex ? 1 : 0.2), lineWidth: settings.glowHex == p.hex ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                LabeledSlider(title: "Glow", icon: "sparkles", value: settings.glowIntensity) { settings.glowIntensity = $0 }
                Chip(title: "Wave with music", symbol: "waveform.path", on: settings.waveWithMusic) { settings.waveWithMusic.toggle() }
                    .help("The border ripples with whatever is actually coming out of the speakers.")
                LabeledSlider(title: "Wave", icon: "water.waves", value: settings.waveIntensity) { settings.waveIntensity = $0 }
                HStack(spacing: 6) {
                    Chip(title: "Focus", symbol: "moon.fill", on: settings.focusIndicator) {
                        settings.focusIndicator.toggle()
                        if settings.focusIndicator { focus.requestAccessIfNeeded() }
                    }
                    .help(focus.readable
                          ? "Show a moon and close the face's eyes while a Focus is on."
                          : "Needs Focus sharing — turn this on and allow the prompt, or enable it under Privacy & Security ▸ Focus.")
                    Chip(title: "Charging", symbol: "bolt.fill", on: settings.chargeAnimation) { settings.chargeAnimation.toggle() }
                        .help("When you plug in, the notch fills like a battery ring and shows the time to full.")
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var faceTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Face", symbol: "face.smiling")
                HStack(spacing: 6) {
                    Chip(title: "Show face", symbol: "face.smiling", on: settings.showFace) { settings.showFace.toggle() }
                    Chip(title: "Auto", symbol: "sparkles", on: settings.faceMode == "auto") { settings.faceMode = "auto" }
                }
                Chip(title: "Reactions", symbol: "bolt.heart.fill", on: settings.eventFaces) { settings.eventFaces.toggle() }
                    .help("The face reacts for a couple of seconds to plugging in, low battery, screenshots and the camera or mic turning on, then goes back to what it was doing.")
                Chip(title: "Weather scene", symbol: "cloud.sun.fill", on: settings.weatherFace) { settings.weatherFace.toggle() }
                    .help("Show a little sun, cloud, rain or thunderstorm beside the face for the sky outside. The face keeps its own expression.")
                Text("Or pick one and keep it")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 5) {
                    ForEach(FaceMood.pickable, id: \.rawValue) { m in
                        Button { settings.faceMode = m.rawValue } label: {
                            FaceGlyph(mood: m, color: settings.faceMode == m.rawValue ? settings.accent : Color.white.opacity(0.6), size: 20)
                                .padding(3)
                                .background(Circle().fill(Color.white.opacity(settings.faceMode == m.rawValue ? 0.14 : 0.0)))
                        }
                        .buttonStyle(.plain)
                        .help(m.title)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var generalTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "General", symbol: "slider.horizontal.3")
                Chip(title: "Launch at login", symbol: "power", on: settings.launchAtLogin) { settings.setLaunchAtLogin(!settings.launchAtLogin) }
                Chip(title: "Open on hover", symbol: "cursorarrow.motionlines", on: settings.openOnHover) { settings.openOnHover.toggle() }
                LabeledSlider(title: "Delay", icon: "timer", value: settings.hoverDelay / 0.8) { settings.hoverDelay = ($0 * 0.8 * 20).rounded() / 20 }
                Chip(title: settings.openOnHover ? "Tap = play/pause" : "Tap = open deck", symbol: "cursorarrow.click.2", on: settings.clickActions) { settings.clickActions.toggle() }
                    .help("With Open on hover on: click the closed notch to play or pause, double-click to skip. With it off: a click opens the deck. Right-click always opens the menu.")
                Chip(title: "Scroll = volume", symbol: "speaker.wave.2", on: settings.scrollVolume) { settings.scrollVolume.toggle() }
                    .help("Scroll up or down over the notch to change system volume.")
                Chip(title: "Sounds", symbol: settings.sounds ? "speaker.wave.2.fill" : "speaker.slash.fill", on: settings.sounds) {
                    settings.sounds.toggle()
                    if settings.sounds { SoundKit.play(.open, force: true) }
                }
                .help("Quiet taps when the deck opens, files land on the shelf, or you paste from the clipboard.")
                Spacer(minLength: 0)
                Text("⌃⌥Space toggles · Esc closes")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .onAppear { settings.refreshLaunchAtLogin() }
        }
    }

    private var weatherTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Weather", symbol: "cloud.sun.fill")
                HStack(spacing: 6) {
                    Chip(title: "Weather", symbol: "cloud.sun.fill", on: settings.weatherOn) { settings.weatherOn.toggle() }
                        .help("Show weather in the System tab and let the face react to it.")
                    Chip(title: settings.fahrenheit ? "°F" : "°C", symbol: "thermometer.medium", on: true) { settings.fahrenheit.toggle() }
                        .help("Switch between Celsius and Fahrenheit.")
                }
                Chip(title: "Use my location", symbol: "location.fill", on: settings.weatherUseLocation) { settings.weatherUseLocation.toggle() }
                    .help("Use the Mac's location. macOS asks once. If you say no, the city below is used.")
                Chip(title: settings.weatherCity.isEmpty ? "Set a city…" : settings.weatherCity, symbol: "building.2.fill", on: !settings.weatherCity.isEmpty) {
                    WeatherController.askForCity(current: settings.weatherCity) { settings.weatherCity = $0 }
                }
                .help("Fallback city, used when location is off or denied.")
                Spacer(minLength: 0)
                Text("Forecast by Open-Meteo")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var musicTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Music", symbol: "music.note")
                HStack(spacing: 6) {
                    Chip(title: "Visualizer", symbol: "waveform", on: settings.showVisualizer) { settings.showVisualizer.toggle() }
                    Chip(title: "Volume", symbol: "speaker.wave.2.fill", on: settings.showVolume) { settings.showVolume.toggle() }
                }
                HStack(spacing: 6) {
                    Chip(title: "Art glow", symbol: "sparkles", on: settings.animateArtwork) { settings.animateArtwork.toggle() }
                    Chip(title: "In notch", symbol: "rectangle.topthird.inset.filled", on: settings.pillNowPlaying) { settings.pillNowPlaying.toggle() }
                }
                Chip(title: "Lyrics", symbol: "quote.bubble.fill", on: settings.showLyrics) { settings.showLyrics.toggle() }
                    .help("Show time-synced lyrics in the Music tab when they can be found for the track.")
                Chip(title: "Lyrics under notch", symbol: "text.bubble.fill", on: settings.lyricsUnderNotch) { settings.lyricsUnderNotch.toggle() }
                    .help("Show the current lyric line under the closed notch while music plays. It hides the moment you hover to open the deck.")
                Spacer(minLength: 0)
                Text("Works with Apple Music and Spotify")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var widgetsTile: some View {
        Tile(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "System widgets", symbol: "square.grid.2x2.fill")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(SystemWidget.allCases) { w in
                        Chip(title: w.title, symbol: w.symbol, on: settings.isOn(w)) { settings.toggle(w) }
                    }
                    Chip(title: "Actions", symbol: "bolt.fill", on: settings.showQuickActions) { settings.showQuickActions.toggle() }
                    Chip(title: "Volume", symbol: "speaker.wave.2.fill", on: settings.showSystemVolume) { settings.showSystemVolume.toggle() }
                }
            }
        }
    }
}

struct SectionHeader: View {
    @EnvironmentObject var settings: DeckSettings
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(settings.accent)
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
    }
}

struct Chip: View {
    @EnvironmentObject var settings: DeckSettings
    let title: String
    let symbol: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 12)
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? settings.onAccent : Color.white.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(on ? settings.accent : Color.white.opacity(hovering ? 0.12 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Swatch: View {
    let hex: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: hex) ?? .white))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 1 : 0.2), lineWidth: selected ? 2 : 1))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct HueBar: View {
    let hue: Double?
    let onPick: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(
                    LinearGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 0.72, brightness: 1) },
                                   startPoint: .leading, endPoint: .trailing)
                )
                if let hue {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .offset(x: geo.size.width * CGFloat(hue) - 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                onPick(Double(min(max(g.location.x / geo.size.width, 0), 0.999)))
            })
        }
    }
}

struct LabeledSlider: View {
    @EnvironmentObject var settings: DeckSettings
    let title: String
    let icon: String
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 34, alignment: .leading)
            DeckSlider(value: value, icon: icon, accent: settings.accent, onChange: onChange)
                .frame(height: 16)
        }
    }
}


struct LyricsStrip: View {
    @ObservedObject var lyrics: LyricsController
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch lyrics.status {
            case .synced:
                Text(lyrics.currentLine ?? "♪")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(lyrics.index)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Text(lyrics.nextLine ?? " ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            case .loading:
                Text("Looking for lyrics…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            case .plain:
                Text("Lyrics found, but not time-synced")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            case .missing:
                Text("No lyrics for this track")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.28))
            case .failed:
                HStack(spacing: 6) {
                    Text("Lyrics unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.28))
                    Button("Retry") { lyrics.refresh(force: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.8))
                }
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.22), value: lyrics.index)
        .animation(.easeOut(duration: 0.22), value: lyrics.status)
    }
}
