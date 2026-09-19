import SwiftUI
import AppKit

struct DeckView: View {
    @EnvironmentObject var state: DeckState
    @EnvironmentObject var settings: DeckSettings
    @EnvironmentObject var ui: PanelState
    @ObservedObject var music: MusicController
    let metrics: NotchMetrics

    private let expandedSize = NotchMetrics.expandedSize

    var body: some View {
        let expanded = ui.isExpanded
        let pill = !expanded && settings.pillNowPlaying && (music.nowPlaying?.isPlaying ?? false)
        let ext: CGFloat = pill ? 62 : 0
        let flare: CGFloat = expanded ? 20 : (pill ? 10 : 6)
        let margin: CGFloat = 30
        let width = expanded ? expandedSize.width - margin * 2 : metrics.notchWidth + ext * 2
        let height = expanded ? expandedSize.height - 14 : metrics.notchHeight
        let shape = NotchShape(bottomRadius: expanded ? 30 : (pill ? 14 : 10), topFlare: flare)

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

            if pill {
                HStack(spacing: 0) {
                    pillArtwork
                        .frame(width: metrics.notchHeight - 10, height: metrics.notchHeight - 10)
                        .padding(.leading, 12)
                    Spacer(minLength: 0)
                    Visualizer(active: true, color: settings.accent, barCount: 5, maxHeight: metrics.notchHeight - 16)
                        .padding(.trailing, 14)
                }
                .frame(width: width, height: height)
                .transition(.opacity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: pill)
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
                PageTab(systemImage: "gearshape.fill", index: 3)
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
                MusicPage(music: state.music)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                SystemPage(stats: state.stats)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                SettingsPage()
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
    @State private var hovering = false

    var body: some View {
        let selected = ui.page == index
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { ui.page = index }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
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

                        Spacer(minLength: 2)

                        ProgressScrubber(position: np.position, duration: np.duration, accent: settings.accent) { music.seek(to: $0) }
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
    @State private var phase = 0.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(active ? 0.9 : 0.3))
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .onAppear { animate() }
        .onChange(of: active) { _, _ in animate() }
    }

    private func height(for i: Int) -> CGFloat {
        guard active else { return 3 }
        let v = sin(phase + Double(i) * 1.3) * 0.5 + 0.5
        return 3 + CGFloat(v) * (maxHeight - 3)
    }

    private func animate() {
        guard active else { return }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
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
            }
        }
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

// MARK: - Settings

struct SettingsPage: View {
    @EnvironmentObject var settings: DeckSettings

    private let chipColumns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        HStack(spacing: 10) {
            Tile(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
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
            }
            Tile(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "General", symbol: "slider.horizontal.3")
                    Chip(title: "Launch at login", symbol: "power", on: settings.launchAtLogin) { settings.setLaunchAtLogin(!settings.launchAtLogin) }
                    Chip(title: "Open on hover", symbol: "cursorarrow.motionlines", on: settings.openOnHover) { settings.openOnHover.toggle() }
                    LabeledSlider(title: "Delay", icon: "timer", value: settings.hoverDelay / 0.8) { settings.hoverDelay = ($0 * 0.8 * 20).rounded() / 20 }
                    SectionHeader(title: "Music", symbol: "music.note")
                        .padding(.top, 2)
                    HStack(spacing: 6) {
                        Chip(title: "Visualizer", symbol: "waveform", on: settings.showVisualizer) { settings.showVisualizer.toggle() }
                        Chip(title: "Volume", symbol: "speaker.wave.2.fill", on: settings.showVolume) { settings.showVolume.toggle() }
                    }
                    HStack(spacing: 6) {
                        Chip(title: "Glow", symbol: "sparkles", on: settings.animateArtwork) { settings.animateArtwork.toggle() }
                        Chip(title: "In notch", symbol: "rectangle.topthird.inset.filled", on: settings.pillNowPlaying) { settings.pillNowPlaying.toggle() }
                    }
                    Spacer(minLength: 0)
                    Text("⌃⌥Space toggles the deck · Esc closes it")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(2)
                }
                .onAppear { settings.refreshLaunchAtLogin() }
            }
            Tile(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeader(title: "System widgets", symbol: "square.grid.2x2.fill")
                    LazyVGrid(columns: chipColumns, spacing: 6) {
                        ForEach(SystemWidget.allCases) { w in
                            Chip(title: w.title, symbol: w.symbol, on: settings.isOn(w)) { settings.toggle(w) }
                        }
                        Chip(title: "Actions", symbol: "bolt.fill", on: settings.showQuickActions) { settings.showQuickActions.toggle() }
                        Chip(title: "Volume", symbol: "speaker.wave.2.fill", on: settings.showSystemVolume) { settings.showSystemVolume.toggle() }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 4)
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
