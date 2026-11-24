import SwiftUI

struct PostBgColorOptionIOS: Identifiable, Hashable {
    let hex: String
    let color: Color
    let isDarkText: Bool
    var id: String { hex }
}

struct PostImageThemeOptionIOS: Identifiable, Hashable {
    let id: String
    let name: String
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let isDarkText: Bool
}

enum PostFontStyleIOS: String, CaseIterable, Identifiable {
    case classic, serif, hand, typewriter, bold, mono, display, rounded, italic, script, slab, condensed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Classic"
        case .serif: return "Serif"
        case .hand: return "Hand"
        case .typewriter: return "Typewriter"
        case .bold: return "Bold"
        case .mono: return "Mono"
        case .display: return "Display"
        case .rounded: return "Rounded"
        case .italic: return "Italic"
        case .script: return "Script"
        case .slab: return "Slab"
        case .condensed: return "Condensed"
        }
    }

    var badge: String { self == .bold ? "AA" : "Aa" }

    func swiftUIFont(size: CGFloat) -> Font {
        switch self {
        case .classic: return .system(size: size, weight: .semibold, design: .default)
        case .serif: return .system(size: size, weight: .regular, design: .serif)
        case .hand: return .custom("MarkerFelt-Thin", size: size)
        case .typewriter: return .system(size: size, weight: .regular, design: .monospaced)
        case .bold: return .system(size: size, weight: .heavy, design: .default)
        case .mono: return .system(size: size, weight: .regular, design: .monospaced)
        case .display: return .system(size: size, weight: .bold, design: .rounded)
        case .rounded: return .system(size: size, weight: .medium, design: .rounded)
        case .italic: return .system(size: size, weight: .regular, design: .serif).italic()
        case .script: return .custom("SnellRoundhand-Bold", size: size)
        case .slab: return .system(size: size, weight: .bold, design: .serif)
        case .condensed: return .system(size: size, weight: .bold, design: .default)
        }
    }
}

let POST_BG_COLORS_IOS: [PostBgColorOptionIOS] = [
    PostBgColorOptionIOS(hex: "#C81010", color: Color(red: 200/255, green: 16/255, blue: 16/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#FF9E5E", color: Color(red: 255/255, green: 158/255, blue: 94/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#169AE6", color: Color(red: 22/255, green: 154/255, blue: 230/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#149A5A", color: Color(red: 20/255, green: 154/255, blue: 90/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#8B5CF6", color: Color(red: 139/255, green: 92/255, blue: 246/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#232B38", color: Color(red: 35/255, green: 43/255, blue: 56/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#F5EEDC", color: Color(red: 245/255, green: 238/255, blue: 220/255), isDarkText: true),
    PostBgColorOptionIOS(hex: "#E11D48", color: Color(red: 225/255, green: 29/255, blue: 72/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#0D9488", color: Color(red: 13/255, green: 148/255, blue: 136/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#4338CA", color: Color(red: 67/255, green: 56/255, blue: 202/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#D97706", color: Color(red: 217/255, green: 119/255, blue: 6/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#BE185D", color: Color(red: 190/255, green: 24/255, blue: 93/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#0F172A", color: Color(red: 15/255, green: 23/255, blue: 42/255), isDarkText: false),
    PostBgColorOptionIOS(hex: "#10B981", color: Color(red: 16/255, green: 185/255, blue: 129/255), isDarkText: false)
]

let POST_IMAGE_THEMES_IOS: [PostImageThemeOptionIOS] = [
    PostImageThemeOptionIOS(id: "aurora", name: "Aurora", primaryColor: Color(red: 8/255, green: 28/255, blue: 36/255), secondaryColor: Color(red: 16/255, green: 185/255, blue: 129/255), accentColor: Color(red: 56/255, green: 189/255, blue: 248/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "sunset_peaks", name: "Sunset Peaks", primaryColor: Color(red: 124/255, green: 45/255, blue: 18/255), secondaryColor: Color(red: 251/255, green: 113/255, blue: 133/255), accentColor: Color(red: 251/255, green: 191/255, blue: 36/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "starry_night", name: "Starry Night", primaryColor: Color(red: 11/255, green: 16/255, blue: 38/255), secondaryColor: Color(red: 30/255, green: 58/255, blue: 138/255), accentColor: Color(red: 253/255, green: 224/255, blue: 71/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "ocean_waves", name: "Ocean Waves", primaryColor: Color(red: 4/255, green: 47/255, blue: 75/255), secondaryColor: Color(red: 2/255, green: 132/255, blue: 199/255), accentColor: Color(red: 125/255, green: 211/255, blue: 252/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "desert_dunes", name: "Desert Dunes", primaryColor: Color(red: 154/255, green: 52/255, blue: 18/255), secondaryColor: Color(red: 245/255, green: 158/255, blue: 11/255), accentColor: Color(red: 254/255, green: 215/255, blue: 170/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "sakura_blossom", name: "Sakura", primaryColor: Color(red: 131/255, green: 24/255, blue: 67/255), secondaryColor: Color(red: 244/255, green: 114/255, blue: 182/255), accentColor: Color(red: 252/255, green: 231/255, blue: 243/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "cyber_grid", name: "Cyber Grid", primaryColor: Color(red: 9/255, green: 13/255, blue: 22/255), secondaryColor: Color(red: 147/255, green: 51/255, blue: 234/255), accentColor: Color(red: 34/255, green: 211/255, blue: 238/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "forest_mist", name: "Forest Mist", primaryColor: Color(red: 6/255, green: 78/255, blue: 59/255), secondaryColor: Color(red: 5/255, green: 150/255, blue: 105/255), accentColor: Color(red: 167/255, green: 243/255, blue: 208/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "marble_gold", name: "Marble Gold", primaryColor: Color(red: 28/255, green: 25/255, blue: 23/255), secondaryColor: Color(red: 68/255, green: 64/255, blue: 60/255), accentColor: Color(red: 251/255, green: 191/255, blue: 36/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "neon_horizon", name: "Neon Horizon", primaryColor: Color(red: 49/255, green: 16/255, blue: 66/255), secondaryColor: Color(red: 236/255, green: 72/255, blue: 153/255), accentColor: Color(red: 250/255, green: 204/255, blue: 21/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "abstract_prism", name: "Prism", primaryColor: Color(red: 30/255, green: 27/255, blue: 75/255), secondaryColor: Color(red: 99/255, green: 102/255, blue: 241/255), accentColor: Color(red: 244/255, green: 63/255, blue: 94/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "rainy_glass", name: "Rainy Glass", primaryColor: Color(red: 30/255, green: 41/255, blue: 59/255), secondaryColor: Color(red: 71/255, green: 85/255, blue: 105/255), accentColor: Color(red: 147/255, green: 197/255, blue: 253/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "warm_bokeh", name: "Warm Bokeh", primaryColor: Color(red: 69/255, green: 10/255, blue: 10/255), secondaryColor: Color(red: 220/255, green: 38/255, blue: 38/255), accentColor: Color(red: 253/255, green: 186/255, blue: 116/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "midnight_clouds", name: "Midnight Clouds", primaryColor: Color(red: 15/255, green: 23/255, blue: 42/255), secondaryColor: Color(red: 51/255, green: 65/255, blue: 85/255), accentColor: Color(red: 192/255, green: 132/255, blue: 252/255), isDarkText: false),
    PostImageThemeOptionIOS(id: "coral_reef", name: "Coral Reef", primaryColor: Color(red: 19/255, green: 78/255, blue: 74/255), secondaryColor: Color(red: 251/255, green: 113/255, blue: 133/255), accentColor: Color(red: 45/255, green: 212/255, blue: 191/255), isDarkText: false)
]

struct PostThemeArtworkIOS: View {
    let theme: PostImageThemeOptionIOS

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [theme.primaryColor, theme.secondaryColor]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
            let minDim = min(size.width, size.height)
            switch theme.id {
            case "aurora":
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height * 0.45))
                p.addCurve(to: CGPoint(x: size.width, y: size.height * 0.22), control1: CGPoint(x: size.width * 0.28, y: size.height * 0.15), control2: CGPoint(x: size.width * 0.65, y: size.height * 0.65))
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.55))
                p.addCurve(to: CGPoint(x: 0, y: size.height * 0.7), control1: CGPoint(x: size.width * 0.62, y: size.height * 0.85), control2: CGPoint(x: size.width * 0.3, y: size.height * 0.36))
                p.closeSubpath()
                ctx.fill(p, with: .color(theme.accentColor.opacity(0.45)))
            case "sunset_peaks":
                let sunRect = CGRect(x: size.width * 0.5 - minDim * 0.18, y: size.height * 0.34 - minDim * 0.18, width: minDim * 0.36, height: minDim * 0.36)
                ctx.fill(Path(ellipseIn: sunRect), with: .color(theme.accentColor.opacity(0.85)))
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height))
                p.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.52))
                p.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.76))
                p.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.48))
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.72))
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color.black.opacity(0.36)))
            case "starry_night":
                for i in 0..<22 {
                    let x = CGFloat((i * 73 + 19) % 100) / 100.0 * size.width
                    let y = CGFloat((i * 41 + 11) % 85) / 100.0 * size.height
                    let r = i % 4 == 0 ? minDim * 0.015 : minDim * 0.008
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(0.7)))
                }
            case "ocean_waves", "desert_dunes":
                for row in 0...2 {
                    let base = size.height * (0.5 + CGFloat(row) * 0.14)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: base))
                    p.addCurve(to: CGPoint(x: size.width, y: base - size.height * 0.03), control1: CGPoint(x: size.width * 0.3, y: base - size.height * 0.09), control2: CGPoint(x: size.width * 0.65, y: base + size.height * 0.09))
                    p.addLine(to: CGPoint(x: size.width, y: size.height))
                    p.addLine(to: CGPoint(x: 0, y: size.height))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(theme.accentColor.opacity(0.18 + Double(row) * 0.08)))
                }
            case "cyber_grid":
                let h = size.height * 0.54
                var line = Path()
                line.move(to: CGPoint(x: 0, y: h))
                line.addLine(to: CGPoint(x: size.width, y: h))
                ctx.stroke(line, with: .color(theme.accentColor.opacity(0.75)), lineWidth: 2)
                for i in -3...3 {
                    var r = Path()
                    r.move(to: CGPoint(x: size.width * 0.5 + CGFloat(i) * size.width * 0.06, y: h))
                    r.addLine(to: CGPoint(x: size.width * 0.5 + CGFloat(i) * size.width * 0.24, y: size.height))
                    ctx.stroke(r, with: .color(theme.secondaryColor.opacity(0.45)), lineWidth: 1.5)
                }
            case "neon_horizon":
                let s = CGRect(x: size.width * 0.5 - minDim * 0.22, y: size.height * 0.46 - minDim * 0.22, width: minDim * 0.44, height: minDim * 0.44)
                ctx.fill(Path(ellipseIn: s), with: .color(theme.accentColor.opacity(0.85)))
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.56, width: size.width, height: size.height * 0.44)), with: .color(theme.primaryColor.opacity(0.78)))
            default:
                for i in 0..<10 {
                    let x = CGFloat((i * 83 + 15) % 90 + 5) / 100.0 * size.width
                    let y = CGFloat((i * 47 + 21) % 86 + 6) / 100.0 * size.height
                    let r = minDim * CGFloat(0.06 + Double(i % 4) * 0.03)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(theme.accentColor.opacity(0.24)))
                }
            }
        }
    }
}

// MARK: - Post SVG Vector Icons

struct CloseVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 6 * sx, y: 6 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 18 * sy))
        p.move(to: CGPoint(x: 18 * sx, y: 6 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 18 * sy))
        return p
    }
}

struct PhotosTabVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 15 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 4 * sy))
        p.addCurve(to: CGPoint(x: 4 * sx, y: 6 * sy), control1: CGPoint(x: 4.9 * sx, y: 4 * sy), control2: CGPoint(x: 4 * sx, y: 4.9 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 18 * sy))
        p.addCurve(to: CGPoint(x: 6 * sx, y: 20 * sy), control1: CGPoint(x: 4 * sx, y: 19.1 * sy), control2: CGPoint(x: 4.9 * sx, y: 20 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 20 * sy))
        p.addCurve(to: CGPoint(x: 20 * sx, y: 18 * sy), control1: CGPoint(x: 19.1 * sx, y: 20 * sy), control2: CGPoint(x: 20 * sx, y: 19.1 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 9 * sy))
        p.move(to: CGPoint(x: 19 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 17 * sx, y: 5 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 5 * sy))
        p.move(to: CGPoint(x: 5 * sx, y: 16 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 12.2 * sx, y: 15.2 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 12.5 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 16.5 * sy))
        return p
    }
}

struct VideoTabVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 5 * sx, y: 4 * sy, width: 16 * sx, height: 14 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.move(to: CGPoint(x: 3 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 18 * sy))
        p.addCurve(to: CGPoint(x: 5 * sx, y: 20 * sy), control1: CGPoint(x: 3 * sx, y: 19.1 * sy), control2: CGPoint(x: 3.9 * sx, y: 20 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 20 * sy))
        p.move(to: CGPoint(x: 11.5 * sx, y: 8.6 * sy))
        p.addLine(to: CGPoint(x: 15.6 * sx, y: 11 * sy))
        p.addLine(to: CGPoint(x: 11.5 * sx, y: 13.4 * sy))
        p.closeSubpath()
        return p
    }
}

struct MusicNoteVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 6 * sx, y: 14 * sy, width: 6 * sx, height: 6 * sy))
        p.move(to: CGPoint(x: 12 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 8 * sy))
        return p
    }
}

struct HashtagVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 10 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 8 * sx, y: 20 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 14 * sx, y: 20 * sy))
        p.move(to: CGPoint(x: 4 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 9 * sy))
        p.move(to: CGPoint(x: 3 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 15 * sy))
        return p
    }
}

struct ChevronRightVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 9 * sx, y: 6 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 18 * sy))
        return p
    }
}

struct PlayTriangleVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 8 * sx, y: 5 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 8 * sx, y: 19 * sy))
        p.closeSubpath()
        return p
    }
}

struct PauseBarsVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRect(CGRect(x: 6 * sx, y: 5 * sy, width: 4 * sx, height: 14 * sy))
        p.addRect(CGRect(x: 14 * sx, y: 5 * sy, width: 4 * sx, height: 14 * sy))
        return p
    }
}

struct CheckMarkVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 5 * sx, y: 12.5 * sy))
        p.addLine(to: CGPoint(x: 9.5 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 7 * sy))
        return p
    }
}

struct ClapperboardVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2 * sx, y: 8 * sy, width: 20 * sx, height: 12 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.move(to: CGPoint(x: 2 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 22 * sx, y: 4 * sy))
        p.move(to: CGPoint(x: 6 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 8 * sy))
        p.move(to: CGPoint(x: 12 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 8 * sy))
        p.move(to: CGPoint(x: 18 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 8 * sy))
        return p
    }
}

struct VolumeOffVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 11 * sx, y: 5 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 11 * sx, y: 19 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 22 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 15 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 22 * sx, y: 15 * sy))
        return p
    }
}

struct VolumeOnVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 11 * sx, y: 5 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 11 * sx, y: 19 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 15.5 * sx, y: 8.5 * sy))
        p.addCurve(to: CGPoint(x: 15.5 * sx, y: 15.5 * sy), control1: CGPoint(x: 17.5 * sx, y: 10.5 * sy), control2: CGPoint(x: 17.5 * sx, y: 13.5 * sy))
        p.move(to: CGPoint(x: 18.8 * sx, y: 5.8 * sy))
        p.addCurve(to: CGPoint(x: 18.8 * sx, y: 18.2 * sy), control1: CGPoint(x: 22 * sx, y: 9.2 * sy), control2: CGPoint(x: 22 * sx, y: 14.8 * sy))
        return p
    }
}

struct AutoSparkleVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12 * sx, y: 2 * sy))
        p.addLine(to: CGPoint(x: 14.4 * sx, y: 9.6 * sy))
        p.addLine(to: CGPoint(x: 22 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 14.4 * sx, y: 14.4 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 22 * sy))
        p.addLine(to: CGPoint(x: 9.6 * sx, y: 14.4 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 9.6 * sx, y: 9.6 * sy))
        p.closeSubpath()
        return p
    }
}

struct PaletteVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 3 * sx, y: 3 * sy, width: 18 * sx, height: 18 * sy))
        p.addEllipse(in: CGRect(x: 7 * sx, y: 8 * sy, width: 2.5 * sx, height: 2.5 * sy))
        p.addEllipse(in: CGRect(x: 12 * sx, y: 6.5 * sy, width: 2.5 * sx, height: 2.5 * sy))
        p.addEllipse(in: CGRect(x: 15.5 * sx, y: 10.5 * sy, width: 2.5 * sx, height: 2.5 * sy))
        p.addEllipse(in: CGRect(x: 8.5 * sx, y: 14 * sy, width: 2.5 * sx, height: 2.5 * sy))
        return p
    }
}

struct ImageThemeVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3 * sx, y: 4 * sy, width: 18 * sx, height: 16 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.addEllipse(in: CGRect(x: 7 * sx, y: 7.5 * sy, width: 3 * sx, height: 3 * sy))
        p.move(to: CGPoint(x: 4 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 12.5 * sy))
        p.addLine(to: CGPoint(x: 12.5 * sx, y: 15.5 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 11.5 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 17 * sy))
        return p
    }
}
