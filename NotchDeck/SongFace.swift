import SwiftUI

// A song's face is composed from a small kit of eye / mouth / brow / extra parts, so we can offer
// a large catalogue of distinct, named expressions the mood reader picks from — all drawn natively
// in the same flat style as the system face, never real emoji.

enum FEyes: String { case open, happy, closed, sleepy, flat, wide, squint, x, spiral, teary, star, heart, side, cute }
enum FMouth: String { case smile, grin, bigSmile, o, frown, flat, wobble, smirk, tongue, gasp, cat, pout, grit }
enum FBrow: String { case none, angry, worried, raised }
enum FExtra: String { case none, blush, sweat, tear, sparkle, note, anger, heart, zzz }

struct FaceLook {
    var eyes: FEyes
    var mouth: FMouth
    var brow: FBrow = .none
    var extra: FExtra = .none
}

/// A large catalogue of named expressions. `rawValue` is the lowercase name the model chooses from;
/// `look` is how it's drawn. Grouped by feel: joyful, calm, sad, tense/dark, love, hype, quirky.
enum SongFace: String, CaseIterable, Identifiable {
    // joyful / bright
    case euphoric, ecstatic, happy, joyful, cheerful, playful, cheeky, bright, hopeful, proud, confident, blissful
    // calm / soft
    case calm, chill, serene, content, mellow, dreamy, peaceful, cozy, sleepy, tired, bored
    // sad / down
    case lonely, sad, melancholy, heartbroken, crying, somber, gloomy, wistful, nostalgic, moody
    // tense / dark
    case tense, anxious, nervous, scared, menacing, angry, furious, fierce, dark, intense, serious, determined
    // love / warm
    case romantic, love, sultry, warm
    // hype / motion
    case energetic, hyper, groovy, funky, triumphant, epic
    // quirky / odd
    case surprised, shocked, mysterious, eerie, dizzy, whimsical, cool, silly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var look: FaceLook {
        switch self {
        case .euphoric:    return FaceLook(eyes: .happy, mouth: .bigSmile, brow: .raised, extra: .sparkle)
        case .ecstatic:    return FaceLook(eyes: .star, mouth: .grin, extra: .sparkle)
        case .happy:       return FaceLook(eyes: .happy, mouth: .smile)
        case .joyful:      return FaceLook(eyes: .happy, mouth: .grin, extra: .blush)
        case .cheerful:    return FaceLook(eyes: .cute, mouth: .smile, extra: .blush)
        case .playful:     return FaceLook(eyes: .side, mouth: .tongue)
        case .cheeky:      return FaceLook(eyes: .squint, mouth: .smirk, extra: .blush)
        case .bright:      return FaceLook(eyes: .open, mouth: .grin, brow: .raised)
        case .hopeful:     return FaceLook(eyes: .open, mouth: .smile, brow: .raised)
        case .proud:       return FaceLook(eyes: .squint, mouth: .smile, brow: .raised)
        case .confident:   return FaceLook(eyes: .side, mouth: .smirk, brow: .raised)
        case .blissful:    return FaceLook(eyes: .closed, mouth: .bigSmile, extra: .sparkle)

        case .calm:        return FaceLook(eyes: .closed, mouth: .flat)
        case .chill:       return FaceLook(eyes: .closed, mouth: .smile)
        case .serene:      return FaceLook(eyes: .sleepy, mouth: .smile)
        case .content:     return FaceLook(eyes: .open, mouth: .smile)
        case .mellow:      return FaceLook(eyes: .sleepy, mouth: .flat)
        case .dreamy:      return FaceLook(eyes: .sleepy, mouth: .smile, extra: .sparkle)
        case .peaceful:    return FaceLook(eyes: .closed, mouth: .smile, extra: .blush)
        case .cozy:        return FaceLook(eyes: .happy, mouth: .smile, extra: .blush)
        case .sleepy:      return FaceLook(eyes: .sleepy, mouth: .o, extra: .zzz)
        case .tired:       return FaceLook(eyes: .sleepy, mouth: .flat, extra: .zzz)
        case .bored:       return FaceLook(eyes: .squint, mouth: .flat)

        case .lonely:      return FaceLook(eyes: .sleepy, mouth: .frown)
        case .sad:         return FaceLook(eyes: .teary, mouth: .frown, brow: .worried)
        case .melancholy:  return FaceLook(eyes: .sleepy, mouth: .frown, brow: .worried)
        case .heartbroken: return FaceLook(eyes: .teary, mouth: .frown, brow: .worried, extra: .tear)
        case .crying:      return FaceLook(eyes: .teary, mouth: .gasp, brow: .worried, extra: .tear)
        case .somber:      return FaceLook(eyes: .closed, mouth: .frown)
        case .gloomy:      return FaceLook(eyes: .sleepy, mouth: .frown, brow: .worried)
        case .wistful:     return FaceLook(eyes: .side, mouth: .frown, brow: .worried)
        case .nostalgic:   return FaceLook(eyes: .sleepy, mouth: .smile, brow: .worried)
        case .moody:       return FaceLook(eyes: .side, mouth: .pout, brow: .angry)

        case .tense:       return FaceLook(eyes: .squint, mouth: .grit, brow: .angry)
        case .anxious:     return FaceLook(eyes: .wide, mouth: .wobble, brow: .worried, extra: .sweat)
        case .nervous:     return FaceLook(eyes: .side, mouth: .wobble, brow: .worried, extra: .sweat)
        case .scared:      return FaceLook(eyes: .wide, mouth: .gasp, brow: .worried, extra: .sweat)
        case .menacing:    return FaceLook(eyes: .squint, mouth: .smirk, brow: .angry)
        case .angry:       return FaceLook(eyes: .squint, mouth: .grit, brow: .angry, extra: .anger)
        case .furious:     return FaceLook(eyes: .x, mouth: .grit, brow: .angry, extra: .anger)
        case .fierce:      return FaceLook(eyes: .wide, mouth: .grit, brow: .angry)
        case .dark:        return FaceLook(eyes: .sleepy, mouth: .flat, brow: .angry)
        case .intense:     return FaceLook(eyes: .wide, mouth: .flat, brow: .angry)
        case .serious:     return FaceLook(eyes: .flat, mouth: .flat, brow: .angry)
        case .determined:  return FaceLook(eyes: .squint, mouth: .grit, brow: .angry)

        case .romantic:    return FaceLook(eyes: .heart, mouth: .smile, extra: .heart)
        case .love:        return FaceLook(eyes: .heart, mouth: .grin, extra: .heart)
        case .sultry:      return FaceLook(eyes: .sleepy, mouth: .smirk, extra: .blush)
        case .warm:        return FaceLook(eyes: .happy, mouth: .smile, extra: .blush)

        case .energetic:   return FaceLook(eyes: .wide, mouth: .bigSmile, brow: .raised)
        case .hyper:       return FaceLook(eyes: .star, mouth: .gasp, brow: .raised, extra: .sparkle)
        case .groovy:      return FaceLook(eyes: .happy, mouth: .o, extra: .note)
        case .funky:       return FaceLook(eyes: .side, mouth: .o, extra: .note)
        case .triumphant:  return FaceLook(eyes: .happy, mouth: .grin, brow: .raised, extra: .sparkle)
        case .epic:        return FaceLook(eyes: .wide, mouth: .grin, brow: .raised, extra: .sparkle)

        case .surprised:   return FaceLook(eyes: .wide, mouth: .o, brow: .raised)
        case .shocked:     return FaceLook(eyes: .wide, mouth: .gasp, brow: .raised)
        case .mysterious:  return FaceLook(eyes: .sleepy, mouth: .smirk)
        case .eerie:       return FaceLook(eyes: .spiral, mouth: .wobble, brow: .worried)
        case .dizzy:       return FaceLook(eyes: .spiral, mouth: .wobble)
        case .whimsical:   return FaceLook(eyes: .cute, mouth: .cat, extra: .sparkle)
        case .cool:        return FaceLook(eyes: .side, mouth: .smirk)
        case .silly:       return FaceLook(eyes: .x, mouth: .tongue)
        }
    }

    /// Best-effort match of the model's free-text face name onto a catalogue case: exact name,
    /// then a keyword fallback so a near-miss still lands somewhere sensible.
    static func match(_ raw: String?) -> SongFace? {
        guard let s = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s != "unknown" else { return nil }
        if let exact = SongFace(rawValue: s) { return exact }
        if let hit = SongFace.allCases.first(where: { s.contains($0.rawValue) || $0.rawValue.contains(s) }) { return hit }
        func any(_ words: [String]) -> Bool { words.contains { s.contains($0) } }
        if any(["eupho", "ecsta", "elat", "thrill"]) { return .euphoric }
        if any(["happy", "joy", "glee", "upbeat", "sunny"]) { return .happy }
        if any(["calm", "chill", "rela", "sooth"]) { return .chill }
        if any(["dream", "ether", "float"]) { return .dreamy }
        if any(["sad", "down", "blue", "cry", "tear", "hurt", "heartb"]) { return .sad }
        if any(["lonel", "alone", "empty"]) { return .lonely }
        if any(["melan", "somber", "grief", "mourn"]) { return .melancholy }
        if any(["nerv", "anxi", "worri", "uneas"]) { return .nervous }
        if any(["scare", "fear", "afraid", "terr"]) { return .scared }
        if any(["ang", "rage", "fury", "furi", "mad"]) { return .angry }
        if any(["men", "sinist", "dark", "omin", "evil"]) { return .menacing }
        if any(["inten", "power", "epic", "driv"]) { return .intense }
        if any(["love", "roman", "cute", "adore"]) { return .romantic }
        if any(["sultr", "sens", "seduc", "warm"]) { return .sultry }
        if any(["hype", "energ", "pump", "wild"]) { return .energetic }
        if any(["groov", "funk", "danc", "bop"]) { return .groovy }
        if any(["sleep", "tired", "drow", "lull"]) { return .sleepy }
        if any(["myst", "eerie", "haunt", "creep"]) { return .mysterious }
        if any(["cool", "confid", "swag", "smooth"]) { return .cool }
        return .content
    }
}

/// Draws a `FaceLook` in the same flat vector style as the system `FaceGlyph`.
struct LookGlyph: View {
    var look: FaceLook
    var blink: CGFloat = 1
    var mouthOpen: CGFloat = 1
    var t: Double = 0
    var color: Color
    var size: CGFloat

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().fill(color.opacity(0.16))
            Circle().strokeBorder(color, lineWidth: max(1.2, size * 0.07))
            brow(x: -r * 0.36, r: r)
            brow(x: r * 0.36, r: r)
            eye(x: -r * 0.36, r: r, left: true)
            eye(x: r * 0.36, r: r, left: false)
            mouth(r: r)
            extra(r: r)
        }
        .frame(width: size, height: size)
    }

    private var lw2: CGFloat { max(1.2, size * 0.065) }

    @ViewBuilder
    private func eye(x: CGFloat, r: CGFloat, left: Bool) -> some View {
        let y = -r * 0.16
        switch look.eyes {
        case .open:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.3, height: r * 0.4 * blink)
                Circle().fill(.white.opacity(0.9)).frame(width: r * 0.1, height: r * 0.1).offset(x: r * 0.06, y: -r * 0.1).opacity(blink > 0.5 ? 1 : 0)
            }.offset(x: x, y: y)
        case .cute:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.34, height: r * 0.44 * blink)
                Circle().fill(.white.opacity(0.95)).frame(width: r * 0.16, height: r * 0.16).offset(x: r * 0.05, y: -r * 0.11)
                Circle().fill(.white.opacity(0.7)).frame(width: r * 0.07, height: r * 0.07).offset(x: -r * 0.06, y: r * 0.05)
            }.offset(x: x, y: y)
        case .happy:
            ArcUp().stroke(color, style: StrokeStyle(lineWidth: lw2, lineCap: .round))
                .frame(width: r * 0.42, height: r * 0.22).offset(x: x, y: y)
        case .closed:
            Capsule().fill(color).frame(width: r * 0.36, height: max(1, r * 0.09)).offset(x: x, y: y)
        case .sleepy:
            ArcDown().stroke(color, style: StrokeStyle(lineWidth: lw2, lineCap: .round))
                .frame(width: r * 0.4, height: r * 0.16).offset(x: x, y: y + r * 0.05)
        case .flat:
            Capsule().fill(color).frame(width: r * 0.4, height: max(1, r * 0.1)).offset(x: x, y: y)
        case .wide:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.4, height: r * 0.5)
                Circle().fill(.white.opacity(0.9)).frame(width: r * 0.13, height: r * 0.13).offset(x: r * 0.09, y: -r * 0.14)
            }.offset(x: x, y: y - r * 0.04)
        case .squint:
            Capsule().fill(color).frame(width: r * 0.34, height: max(1.5, r * 0.14)).offset(x: x, y: y)
        case .x:
            ZStack {
                Capsule().fill(color).frame(width: r * 0.36, height: max(1.5, r * 0.1)).rotationEffect(.degrees(45))
                Capsule().fill(color).frame(width: r * 0.36, height: max(1.5, r * 0.1)).rotationEffect(.degrees(-45))
            }.offset(x: x, y: y)
        case .spiral:
            SpiralShape().stroke(color, style: StrokeStyle(lineWidth: max(1.2, r * 0.08), lineCap: .round))
                .frame(width: r * 0.4, height: r * 0.4).rotationEffect(.degrees(t * 120)).offset(x: x, y: y)
        case .teary:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.34, height: r * 0.44 * blink)
                Circle().fill(.white.opacity(0.9)).frame(width: r * 0.1, height: r * 0.1).offset(x: r * 0.06, y: -r * 0.1)
                Circle().fill(Color(red: 0.5, green: 0.8, blue: 1)).frame(width: r * 0.16, height: r * 0.2).offset(y: r * 0.2)
            }.offset(x: x, y: y)
        case .star:
            StarShape().fill(color).frame(width: r * 0.44, height: r * 0.44).offset(x: x, y: y)
        case .heart:
            HeartShape().fill(color).frame(width: r * 0.4, height: r * 0.4).offset(x: x, y: y)
        case .side:
            ZStack {
                Ellipse().fill(color).frame(width: r * 0.3, height: r * 0.4 * blink)
                Circle().fill(.white.opacity(0.9)).frame(width: r * 0.1, height: r * 0.1).offset(x: (left ? r * 0.09 : r * 0.09), y: 0)
            }.offset(x: x, y: y)
        }
    }

    @ViewBuilder
    private func mouth(r: CGFloat) -> some View {
        let y = r * 0.42
        let lw = max(1.2, r * 0.13)
        switch look.mouth {
        case .smile:    ArcDown().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.52, height: r * 0.2).offset(y: y)
        case .grin:     SmileOpen().fill(color).frame(width: r * 0.62, height: r * 0.34).offset(y: y)
        case .bigSmile: SmileOpen().fill(color).frame(width: r * 0.74, height: r * 0.42).offset(y: y - r * 0.02)
        case .o:        Ellipse().fill(color).frame(width: r * 0.3, height: r * 0.16 + r * 0.24 * mouthOpen).offset(y: y + r * 0.02)
        case .frown:    ArcUp().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.5, height: r * 0.18).offset(y: y + r * 0.06)
        case .flat:     Capsule().fill(color).frame(width: r * 0.4, height: max(1, r * 0.1)).offset(y: y + r * 0.02)
        case .wobble:   Wobble().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.5, height: r * 0.14).offset(y: y + r * 0.04)
        case .smirk:    ArcDown().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.46, height: r * 0.18).rotationEffect(.degrees(-12)).offset(x: r * 0.06, y: y)
        case .tongue:
            ZStack {
                ArcDown().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).frame(width: r * 0.52, height: r * 0.2)
                RoundedRectangle(cornerRadius: r * 0.1).fill(Color(red: 1, green: 0.45, blue: 0.55)).frame(width: r * 0.22, height: r * 0.2).offset(x: r * 0.1, y: r * 0.12)
            }.offset(y: y)
        case .gasp:     Ellipse().fill(color).frame(width: r * 0.34, height: r * 0.4).offset(y: y + r * 0.02)
        case .cat:      CatMouth().stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)).frame(width: r * 0.5, height: r * 0.2).offset(y: y)
        case .pout:     Ellipse().fill(color).frame(width: r * 0.24, height: r * 0.18).offset(y: y + r * 0.02)
        case .grit:
            ZStack {
                RoundedRectangle(cornerRadius: r * 0.04).stroke(color, lineWidth: max(1, r * 0.08)).frame(width: r * 0.5, height: r * 0.2)
                Capsule().fill(color).frame(width: max(1, r * 0.06), height: r * 0.2)
                Capsule().fill(color).frame(width: r * 0.5, height: max(1, r * 0.06))
            }.offset(y: y)
        }
    }

    @ViewBuilder
    private func brow(x: CGFloat, r: CGFloat) -> some View {
        let y = -r * 0.16 - r * 0.34
        switch look.brow {
        case .none: EmptyView()
        case .angry:
            Capsule().fill(color).frame(width: r * 0.4, height: max(1.5, r * 0.1))
                .rotationEffect(.degrees(x < 0 ? 18 : -18)).offset(x: x, y: y + r * 0.06)
        case .worried:
            Capsule().fill(color).frame(width: r * 0.38, height: max(1.5, r * 0.09))
                .rotationEffect(.degrees(x < 0 ? -20 : 20)).offset(x: x, y: y)
        case .raised:
            Capsule().fill(color).frame(width: r * 0.36, height: max(1.5, r * 0.09)).offset(x: x, y: y - r * 0.02)
        }
    }

    @ViewBuilder
    private func extra(r: CGFloat) -> some View {
        switch look.extra {
        case .none: EmptyView()
        case .blush:
            Group {
                Capsule().fill(Color(red: 1, green: 0.45, blue: 0.5).opacity(0.55)).frame(width: r * 0.3, height: r * 0.16).offset(x: -r * 0.62, y: r * 0.24)
                Capsule().fill(Color(red: 1, green: 0.45, blue: 0.5).opacity(0.55)).frame(width: r * 0.3, height: r * 0.16).offset(x: r * 0.62, y: r * 0.24)
            }
        case .sweat:
            DropShape().fill(Color(red: 0.5, green: 0.8, blue: 1)).frame(width: r * 0.18, height: r * 0.26)
                .offset(x: r * 0.6, y: -r * 0.28 + CGFloat(t.truncatingRemainder(dividingBy: 1.4)) * 3)
        case .tear:
            DropShape().fill(Color(red: 0.5, green: 0.8, blue: 1)).frame(width: r * 0.16, height: r * 0.24)
                .offset(x: -r * 0.36, y: r * 0.12 + CGFloat(t.truncatingRemainder(dividingBy: 1.6)) * 4)
        case .sparkle:
            ForEach(0..<3, id: \.self) { i in
                let a = t * 2 + Double(i) * 2.1
                StarShape().fill(.white.opacity(0.9)).frame(width: r * 0.16, height: r * 0.16)
                    .offset(x: CGFloat(cos(a)) * r * 0.7, y: -r * 0.5 + CGFloat(sin(a)) * r * 0.2)
                    .opacity(0.5 + 0.5 * sin(a * 1.7))
            }
        case .note:
            Image(systemName: "music.note").font(.system(size: r * 0.34, weight: .bold)).foregroundStyle(color)
                .offset(x: r * 0.62, y: -r * 0.42 + CGFloat(sin(t * 3.2)) * 1.5)
        case .anger:
            Image(systemName: "number").font(.system(size: r * 0.36, weight: .black)).foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                .offset(x: r * 0.55, y: -r * 0.5)
        case .heart:
            ForEach(0..<2, id: \.self) { i in
                let ph = (t * 0.8 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                HeartShape().fill(Color(red: 1, green: 0.4, blue: 0.55).opacity(1 - ph))
                    .frame(width: r * 0.2, height: r * 0.2)
                    .offset(x: r * 0.55 + CGFloat(i) * 4, y: -r * 0.4 - CGFloat(ph) * 10)
            }
        case .zzz:
            ForEach(0..<2, id: \.self) { i in
                let ph = (t * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                Text("z").font(.system(size: r * (0.28 + 0.1 * CGFloat(i)), weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(1 - ph))
                    .offset(x: r * 0.55 + CGFloat(ph) * 6 + CGFloat(i) * 4, y: -r * 0.35 - CGFloat(ph) * 10 - CGFloat(i) * 3)
            }
        }
    }
}

// MARK: - Extra shapes

struct SpiralShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let turns = 2.4, steps = 40
        let maxR = min(rect.width, rect.height) / 2
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let ang = f * turns * 2 * .pi
            let rad = maxR * f
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * rad, y: c.y + CGFloat(sin(ang)) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * 0.44
        for i in 0..<10 {
            let ang = Double(i) * .pi / 5 - .pi / 2
            let rad = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * rad, y: c.y + CGFloat(sin(ang)) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.95))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.28), control1: CGPoint(x: w * 0.15, y: h * 0.7), control2: CGPoint(x: 0, y: h * 0.5))
        p.addArc(center: CGPoint(x: w * 0.25, y: h * 0.28), radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: w * 0.75, y: h * 0.28), radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.95), control1: CGPoint(x: w, y: h * 0.5), control2: CGPoint(x: w * 0.85, y: h * 0.7))
        p.closeSubpath()
        return p
    }
}

struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.68), control: CGPoint(x: rect.maxX, y: rect.midY))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY * 0.68), radius: rect.width / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

struct CatMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: midY), control: CGPoint(x: rect.width * 0.25, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: midY), control: CGPoint(x: rect.width * 0.75, y: rect.maxY))
        return p
    }
}
