import SwiftUI

enum TelefamColors {
    static let crimson = Color(red: 200.0 / 255.0, green: 16.0 / 255.0, blue: 16.0 / 255.0)
    static let crimsonDark = Color(red: 166.0 / 255.0, green: 11.0 / 255.0, blue: 11.0 / 255.0)
    static let crimsonSoft = Color(red: 252.0 / 255.0, green: 232.0 / 255.0, blue: 232.0 / 255.0)

    static let darkBackground = Color(red: 18.0 / 255.0, green: 19.0 / 255.0, blue: 22.0 / 255.0)
    static let darkSurface = Color(red: 27.0 / 255.0, green: 29.0 / 255.0, blue: 34.0 / 255.0)
    static let darkBar = Color(red: 22.0 / 255.0, green: 24.0 / 255.0, blue: 28.0 / 255.0)
    static let darkBorder = Color(red: 43.0 / 255.0, green: 47.0 / 255.0, blue: 56.0 / 255.0)
    static let darkSecondaryText = Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0)

    static let lightBackground = Color.white
    static let lightSurface = Color.white
    static let lightSurfaceSubtle = Color(red: 246.0 / 255.0, green: 247.0 / 255.0, blue: 249.0 / 255.0)
    static let lightBorder = Color(red: 229.0 / 255.0, green: 231.0 / 255.0, blue: 235.0 / 255.0)
    static let lightInkPrimary = Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0)
    static let lightInkSecondary = Color(red: 107.0 / 255.0, green: 114.0 / 255.0, blue: 128.0 / 255.0)

    static let darkHomePill = Color(red: 30.0 / 255.0, green: 31.0 / 255.0, blue: 36.0 / 255.0)
    static let darkContactsSearch = Color(red: 26.0 / 255.0, green: 32.0 / 255.0, blue: 41.0 / 255.0)
    static let darkContactsPill = Color(red: 25.0 / 255.0, green: 28.0 / 255.0, blue: 34.0 / 255.0)

    static func background(isDark: Bool) -> Color { isDark ? darkBackground : lightBackground }
    static func surface(isDark: Bool) -> Color { isDark ? darkSurface : lightSurface }
    static func bar(isDark: Bool) -> Color { isDark ? darkBar : Color.white }
    static func rail(isDark: Bool) -> Color { isDark ? darkBar : lightSurfaceSubtle }
    static func border(isDark: Bool) -> Color { isDark ? darkBorder : lightBorder }
    static func inkPrimary(isDark: Bool) -> Color { isDark ? .white : lightInkPrimary }
    static func inkSecondary(isDark: Bool) -> Color { isDark ? darkSecondaryText : lightInkSecondary }
}

enum TelefamMetrics {
    static let searchBarHeight: CGFloat = 46
    static let searchBarRadius: CGFloat = 23
    static let themePillHeight: CGFloat = 38
    static let themePillRadius: CGFloat = 19
    static let topIconTouch: CGFloat = 48
    static let topIconSize: CGFloat = 22
    static let filterPillHeight: CGFloat = 36
    static let filterPillRadius: CGFloat = 18
    static let actionPillHeight: CGFloat = 38
    static let actionPillRadius: CGFloat = 19
    static let minTouchSize: CGFloat = 48
    static let bottomBarHeight: CGFloat = 66
    static let railWidth: CGFloat = 84
    static let railPostSize: CGFloat = 48
    static let bottomPostSize: CGFloat = 40
    static let authButtonHeight: CGFloat = 48
    static let authButtonRadius: CGFloat = 10
    static let continueButtonHeight: CGFloat = 50
    static let startChatHeight: CGFloat = 48
    static let startChatRadius: CGFloat = 24
}

// MARK: - Left-Edge Swipe Back Gesture

private struct SwipeBackEdgeModifier: ViewModifier {
    let enabled: Bool
    let edgeWidth: CGFloat
    let threshold: CGFloat
    let onBack: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if value.startLocation.x <= edgeWidth && dx >= threshold && abs(dx) > abs(dy) * 1.25 {
                            onBack()
                        }
                    }
            )
        } else {
            content
        }
    }
}

extension View {
    func telefamSwipeBack(
        enabled: Bool = true,
        edgeWidth: CGFloat = 36,
        threshold: CGFloat = 64,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(SwipeBackEdgeModifier(enabled: enabled, edgeWidth: edgeWidth, threshold: threshold, onBack: onBack))
    }
}

// MARK: - Shared SVG Vector Icons (Matching Android res/drawable/ic_*.xml)

struct SearchVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 3 * sx, y: 3 * sy, width: 16 * sx, height: 16 * sy))
        p.move(to: CGPoint(x: 21 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 16.65 * sx, y: 16.65 * sy))
        return p
    }
}

struct MoonVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 20.5 * sx, y: 13.8 * sy))
        p.addCurve(
            to: CGPoint(x: 10.8 * sx, y: 21 * sy),
            control1: CGPoint(x: 19.1 * sx, y: 18.1 * sy),
            control2: CGPoint(x: 15.2 * sx, y: 21 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 3 * sx, y: 12 * sy),
            control1: CGPoint(x: 6.4 * sx, y: 21 * sy),
            control2: CGPoint(x: 3 * sx, y: 17.0 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 11.4 * sx, y: 3.1 * sy),
            control1: CGPoint(x: 3 * sx, y: 7.4 * sy),
            control2: CGPoint(x: 6.6 * sx, y: 3.6 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 11.1 * sx, y: 12.9 * sy),
            control1: CGPoint(x: 9.8 * sx, y: 6.4 * sy),
            control2: CGPoint(x: 9.7 * sx, y: 10.2 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 20.5 * sx, y: 13.8 * sy),
            control1: CGPoint(x: 13.0 * sx, y: 15.3 * sy),
            control2: CGPoint(x: 16.9 * sx, y: 15.6 * sy)
        )
        p.closeSubpath()
        return p
    }
}

struct CameraVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 4 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 7.5 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 9.2 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 14.8 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 16.5 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 7 * sy))
        p.addCurve(to: CGPoint(x: 22 * sx, y: 9 * sy), control1: CGPoint(x: 21.1 * sx, y: 7 * sy), control2: CGPoint(x: 22 * sx, y: 7.9 * sy))
        p.addLine(to: CGPoint(x: 22 * sx, y: 18 * sy))
        p.addCurve(to: CGPoint(x: 20 * sx, y: 20 * sy), control1: CGPoint(x: 22 * sx, y: 19.1 * sy), control2: CGPoint(x: 21.1 * sx, y: 20 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 20 * sy))
        p.addCurve(to: CGPoint(x: 2 * sx, y: 18 * sy), control1: CGPoint(x: 2.9 * sx, y: 20 * sy), control2: CGPoint(x: 2 * sx, y: 19.1 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 9 * sy))
        p.addCurve(to: CGPoint(x: 4 * sx, y: 7 * sy), control1: CGPoint(x: 2 * sx, y: 7.9 * sy), control2: CGPoint(x: 2.9 * sx, y: 7 * sy))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: 8.5 * sx, y: 9.5 * sy, width: 7 * sx, height: 7 * sy))
        return p
    }
}

struct PaperPlaneSendVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 2.01 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 23 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 2.01 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 10 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 14 * sy))
        p.closeSubpath()
        return p
    }
}

struct CalendarVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3 * sx, y: 5 * sy, width: 18 * sx, height: 16 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 8 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 8 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 3 * sx, y: 10 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 10 * sy))
        return p
    }
}

struct LocationPinVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12 * sx, y: 22 * sy))
        p.addCurve(to: CGPoint(x: 5 * sx, y: 10 * sy), control1: CGPoint(x: 8 * sx, y: 17.5 * sy), control2: CGPoint(x: 5 * sx, y: 13.8 * sy))
        p.addCurve(to: CGPoint(x: 12 * sx, y: 3 * sy), control1: CGPoint(x: 5 * sx, y: 6.13 * sy), control2: CGPoint(x: 8.13 * sx, y: 3 * sy))
        p.addCurve(to: CGPoint(x: 19 * sx, y: 10 * sy), control1: CGPoint(x: 15.87 * sx, y: 3 * sy), control2: CGPoint(x: 19 * sx, y: 6.13 * sy))
        p.addCurve(to: CGPoint(x: 12 * sx, y: 22 * sy), control1: CGPoint(x: 19 * sx, y: 13.8 * sy), control2: CGPoint(x: 16 * sx, y: 17.5 * sy))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: 9.5 * sx, y: 7.5 * sy, width: 5 * sx, height: 5 * sy))
        return p
    }
}

struct AtVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 8 * sx, y: 8 * sy, width: 8 * sx, height: 8 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 13 * sy))
        p.addCurve(to: CGPoint(x: 21 * sx, y: 12 * sy), control1: CGPoint(x: 16 * sx, y: 16 * sy), control2: CGPoint(x: 21 * sx, y: 16 * sy))
        p.addCurve(to: CGPoint(x: 12 * sx, y: 3 * sy), control1: CGPoint(x: 21 * sx, y: 6.5 * sy), control2: CGPoint(x: 17 * sx, y: 3 * sy))
        p.addCurve(to: CGPoint(x: 3 * sx, y: 12 * sy), control1: CGPoint(x: 7 * sx, y: 3 * sy), control2: CGPoint(x: 3 * sx, y: 7 * sy))
        p.addCurve(to: CGPoint(x: 12 * sx, y: 21 * sy), control1: CGPoint(x: 3 * sx, y: 17 * sy), control2: CGPoint(x: 7 * sx, y: 21 * sy))
        p.addCurve(to: CGPoint(x: 17.5 * sx, y: 19.2 * sy), control1: CGPoint(x: 14.2 * sx, y: 21 * sy), control2: CGPoint(x: 16.0 * sx, y: 20.3 * sy))
        return p
    }
}

struct PhoneVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 6.62 * sx, y: 10.79 * sy))
        p.addCurve(to: CGPoint(x: 13.21 * sx, y: 17.38 * sy), control1: CGPoint(x: 8.06 * sx, y: 13.62 * sy), control2: CGPoint(x: 10.38 * sx, y: 15.94 * sy))
        p.addLine(to: CGPoint(x: 15.41 * sx, y: 15.18 * sy))
        p.addCurve(to: CGPoint(x: 16.43 * sx, y: 14.94 * sy), control1: CGPoint(x: 15.68 * sx, y: 14.91 * sy), control2: CGPoint(x: 16.08 * sx, y: 14.82 * sy))
        p.addCurve(to: CGPoint(x: 20 * sx, y: 15.51 * sy), control1: CGPoint(x: 17.55 * sx, y: 15.31 * sy), control2: CGPoint(x: 18.76 * sx, y: 15.51 * sy))
        p.addCurve(to: CGPoint(x: 21 * sx, y: 16.51 * sy), control1: CGPoint(x: 20.55 * sx, y: 15.51 * sy), control2: CGPoint(x: 21 * sx, y: 15.96 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 20 * sy))
        p.addCurve(to: CGPoint(x: 20 * sx, y: 21 * sy), control1: CGPoint(x: 21 * sx, y: 20.55 * sy), control2: CGPoint(x: 20.55 * sx, y: 21 * sy))
        p.addCurve(to: CGPoint(x: 3 * sx, y: 4 * sy), control1: CGPoint(x: 10.61 * sx, y: 21 * sy), control2: CGPoint(x: 3 * sx, y: 13.39 * sy))
        p.addCurve(to: CGPoint(x: 4 * sx, y: 3 * sy), control1: CGPoint(x: 3 * sx, y: 3.45 * sy), control2: CGPoint(x: 3.45 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 7.5 * sx, y: 3 * sy))
        p.addCurve(to: CGPoint(x: 8.5 * sx, y: 4 * sy), control1: CGPoint(x: 8.05 * sx, y: 3 * sy), control2: CGPoint(x: 8.5 * sx, y: 3.45 * sy))
        p.addCurve(to: CGPoint(x: 9.07 * sx, y: 7.57 * sy), control1: CGPoint(x: 8.5 * sx, y: 5.25 * sy), control2: CGPoint(x: 8.7 * sx, y: 6.45 * sy))
        p.addCurve(to: CGPoint(x: 8.82 * sx, y: 8.59 * sy), control1: CGPoint(x: 9.18 * sx, y: 7.92 * sy), control2: CGPoint(x: 9.1 * sx, y: 8.31 * sy))
        p.closeSubpath()
        return p
    }
}

struct SunVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 7 * sx, y: 7 * sy, width: 10 * sx, height: 10 * sy))
        let rays: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 12, y: 1), CGPoint(x: 12, y: 3)),
            (CGPoint(x: 12, y: 21), CGPoint(x: 12, y: 23)),
            (CGPoint(x: 4.22, y: 4.22), CGPoint(x: 5.64, y: 5.64)),
            (CGPoint(x: 18.36, y: 18.36), CGPoint(x: 19.78, y: 19.78)),
            (CGPoint(x: 1, y: 12), CGPoint(x: 3, y: 12)),
            (CGPoint(x: 21, y: 12), CGPoint(x: 23, y: 12)),
            (CGPoint(x: 4.22, y: 19.78), CGPoint(x: 5.64, y: 18.36)),
            (CGPoint(x: 18.36, y: 5.64), CGPoint(x: 19.78, y: 4.22))
        ]
        for (a, b) in rays {
            p.move(to: CGPoint(x: a.x * sx, y: a.y * sy))
            p.addLine(to: CGPoint(x: b.x * sx, y: b.y * sy))
        }
        return p
    }
}

struct BellVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12 * sx, y: 22 * sy))
        p.addCurve(
            to: CGPoint(x: 14 * sx, y: 20 * sy),
            control1: CGPoint(x: 13.1 * sx, y: 22 * sy),
            control2: CGPoint(x: 14 * sx, y: 21.1 * sy)
        )
        p.addLine(to: CGPoint(x: 10 * sx, y: 20 * sy))
        p.addCurve(
            to: CGPoint(x: 12 * sx, y: 22 * sy),
            control1: CGPoint(x: 10 * sx, y: 21.1 * sy),
            control2: CGPoint(x: 10.9 * sx, y: 22 * sy)
        )
        p.closeSubpath()

        p.move(to: CGPoint(x: 18 * sx, y: 16 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 11 * sy))
        p.addCurve(
            to: CGPoint(x: 13.5 * sx, y: 4.68 * sy),
            control1: CGPoint(x: 18 * sx, y: 7.93 * sy),
            control2: CGPoint(x: 16.36 * sx, y: 5.36 * sy)
        )
        p.addLine(to: CGPoint(x: 13.5 * sx, y: 4 * sy))
        p.addCurve(
            to: CGPoint(x: 12 * sx, y: 2.5 * sy),
            control1: CGPoint(x: 13.5 * sx, y: 3.17 * sy),
            control2: CGPoint(x: 12.83 * sx, y: 2.5 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 10.5 * sx, y: 4 * sy),
            control1: CGPoint(x: 11.17 * sx, y: 2.5 * sy),
            control2: CGPoint(x: 10.5 * sx, y: 3.17 * sy)
        )
        p.addLine(to: CGPoint(x: 10.5 * sx, y: 4.68 * sy))
        p.addCurve(
            to: CGPoint(x: 6 * sx, y: 11 * sy),
            control1: CGPoint(x: 7.63 * sx, y: 5.36 * sy),
            control2: CGPoint(x: 6 * sx, y: 7.92 * sy)
        )
        p.addLine(to: CGPoint(x: 6 * sx, y: 16 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 18 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 18 * sy))
        p.closeSubpath()
        return p
    }
}

struct MoreVertVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        for cy in [6.0, 12.0, 18.0] {
            p.addEllipse(in: CGRect(x: 10.2 * sx, y: (cy - 1.8) * sy, width: 3.6 * sx, height: 3.6 * sy))
        }
        return p
    }
}

struct MailOutlineVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 2 * sx, y: 6 * sy, width: 20 * sx, height: 12 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.move(to: CGPoint(x: 22 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 13.5 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 8 * sy))
        return p
    }
}

struct ArrowLeftVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 19 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 12 * sy))
        p.move(to: CGPoint(x: 12 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 5 * sy))
        return p
    }
}

struct ChevronDownVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 6 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 9 * sy))
        return p
    }
}

struct PlusVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12 * sx, y: 5 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 19 * sy))
        p.move(to: CGPoint(x: 5 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 12 * sy))
        return p
    }
}

struct ChatFilledVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 20 * sx, y: 2 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 2 * sy))
        p.addCurve(to: CGPoint(x: 2 * sx, y: 4 * sy), control1: CGPoint(x: 2.9 * sx, y: 2 * sy), control2: CGPoint(x: 2 * sx, y: 2.9 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 22 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 18 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 18 * sy))
        p.addCurve(to: CGPoint(x: 22 * sx, y: 16 * sy), control1: CGPoint(x: 21.1 * sx, y: 18 * sy), control2: CGPoint(x: 22 * sx, y: 17.1 * sy))
        p.addLine(to: CGPoint(x: 22 * sx, y: 4 * sy))
        p.addCurve(to: CGPoint(x: 20 * sx, y: 2 * sy), control1: CGPoint(x: 22 * sx, y: 2.9 * sy), control2: CGPoint(x: 21.1 * sx, y: 2 * sy))
        p.closeSubpath()
        return p
    }
}

struct ChatOutlineVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 21 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 19 * sx, y: 17 * sy), control1: CGPoint(x: 21 * sx, y: 16.1 * sy), control2: CGPoint(x: 20.1 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 7 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 5 * sy))
        p.addCurve(to: CGPoint(x: 5 * sx, y: 3 * sy), control1: CGPoint(x: 3 * sx, y: 3.9 * sy), control2: CGPoint(x: 3.9 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 3 * sy))
        p.addCurve(to: CGPoint(x: 21 * sx, y: 5 * sy), control1: CGPoint(x: 20.1 * sx, y: 3 * sy), control2: CGPoint(x: 21 * sx, y: 3.9 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 7 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 8 * sy))
        p.move(to: CGPoint(x: 7 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 13 * sx, y: 12 * sy))
        return p
    }
}

struct ChatPlusVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 21 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 19 * sx, y: 17 * sy), control1: CGPoint(x: 21 * sx, y: 16.1 * sy), control2: CGPoint(x: 20.1 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 7 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 5 * sy))
        p.addCurve(to: CGPoint(x: 5 * sx, y: 3 * sy), control1: CGPoint(x: 3 * sx, y: 3.9 * sy), control2: CGPoint(x: 3.9 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 3 * sy))
        p.addCurve(to: CGPoint(x: 21 * sx, y: 5 * sy), control1: CGPoint(x: 20.1 * sx, y: 3 * sy), control2: CGPoint(x: 21 * sx, y: 3.9 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 12 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 13 * sy))
        p.move(to: CGPoint(x: 9 * sx, y: 10 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 10 * sy))
        return p
    }
}

struct ContactsOutlineVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 17 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 19 * sy))
        p.addCurve(to: CGPoint(x: 13 * sx, y: 15 * sy), control1: CGPoint(x: 17 * sx, y: 16.79 * sy), control2: CGPoint(x: 15.21 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 1 * sx, y: 19 * sy), control1: CGPoint(x: 2.79 * sx, y: 15 * sy), control2: CGPoint(x: 1 * sx, y: 16.79 * sy))
        p.addLine(to: CGPoint(x: 1 * sx, y: 21 * sy))
        p.addEllipse(in: CGRect(x: 5 * sx, y: 3 * sy, width: 8 * sx, height: 8 * sy))
        p.move(to: CGPoint(x: 23 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 23 * sx, y: 19 * sy))
        p.addCurve(to: CGPoint(x: 20 * sx, y: 15.13 * sy), control1: CGPoint(x: 23 * sx, y: 17.13 * sy), control2: CGPoint(x: 21.73 * sx, y: 15.57 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 3.13 * sy))
        p.addCurve(to: CGPoint(x: 16 * sx, y: 10.87 * sy), control1: CGPoint(x: 18.2 * sx, y: 3.9 * sy), control2: CGPoint(x: 18.2 * sx, y: 10.1 * sy))
        return p
    }
}

struct ContactsFilledVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 5 * sx, y: 5 * sy, width: 6 * sx, height: 6 * sy))
        p.addEllipse(in: CGRect(x: 13 * sx, y: 5 * sy, width: 6 * sx, height: 6 * sy))
        p.move(to: CGPoint(x: 8 * sx, y: 13 * sy))
        p.addCurve(to: CGPoint(x: 1 * sx, y: 16.5 * sy), control1: CGPoint(x: 5.67 * sx, y: 13 * sy), control2: CGPoint(x: 1 * sx, y: 14.17 * sy))
        p.addLine(to: CGPoint(x: 1 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 16.5 * sy))
        p.addCurve(to: CGPoint(x: 8 * sx, y: 13 * sy), control1: CGPoint(x: 15 * sx, y: 14.17 * sy), control2: CGPoint(x: 10.33 * sx, y: 13 * sy))
        p.closeSubpath()

        p.move(to: CGPoint(x: 16 * sx, y: 13 * sy))
        p.addLine(to: CGPoint(x: 15.03 * sx, y: 13.05 * sy))
        p.addCurve(to: CGPoint(x: 17 * sx, y: 16.5 * sy), control1: CGPoint(x: 16.19 * sx, y: 13.89 * sy), control2: CGPoint(x: 17 * sx, y: 15.02 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 23 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 23 * sx, y: 16.5 * sy))
        p.addCurve(to: CGPoint(x: 16 * sx, y: 13 * sy), control1: CGPoint(x: 23 * sx, y: 14.17 * sy), control2: CGPoint(x: 18.33 * sx, y: 13 * sy))
        p.closeSubpath()
        return p
    }
}

struct FeedsVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRect(CGRect(x: 14 * sx, y: 3 * sy, width: 6 * sx, height: 6 * sy))
        p.move(to: CGPoint(x: 10 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 14 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 14 * sx, y: 13 * sy))
        p.move(to: CGPoint(x: 6 * sx, y: 13 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 13 * sy))
        p.move(to: CGPoint(x: 6 * sx, y: 10 * sy))
        p.addLine(to: CGPoint(x: 10 * sx, y: 10 * sy))
        return p
    }
}

struct ProfileVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 20 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 19 * sy))
        p.addCurve(to: CGPoint(x: 16 * sx, y: 15 * sy), control1: CGPoint(x: 20 * sx, y: 16.79 * sy), control2: CGPoint(x: 18.21 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 8 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 4 * sx, y: 19 * sy), control1: CGPoint(x: 5.79 * sx, y: 15 * sy), control2: CGPoint(x: 4 * sx, y: 16.79 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 21 * sy))
        p.addEllipse(in: CGRect(x: 8 * sx, y: 3 * sy, width: 8 * sx, height: 8 * sy))
        return p
    }
}

struct SyncVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 20 * sx, y: 12 * sy))
        p.addCurve(to: CGPoint(x: 6 * sx, y: 7.5 * sy), control1: CGPoint(x: 20 * sx, y: 7.5 * sy), control2: CGPoint(x: 13 * sx, y: 4.5 * sy))
        p.move(to: CGPoint(x: 4 * sx, y: 12 * sy))
        p.addCurve(to: CGPoint(x: 18 * sx, y: 16.5 * sy), control1: CGPoint(x: 4 * sx, y: 16.5 * sy), control2: CGPoint(x: 11 * sx, y: 19.5 * sy))
        p.move(to: CGPoint(x: 17 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 10 * sy))
        p.move(to: CGPoint(x: 7 * sx, y: 14 * sy))
        p.addLine(to: CGPoint(x: 4 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 7 * sx, y: 20 * sy))
        return p
    }
}

struct SignOutVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 9 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 21 * sy))
        p.addCurve(to: CGPoint(x: 3 * sx, y: 19 * sy), control1: CGPoint(x: 3.9 * sx, y: 21 * sy), control2: CGPoint(x: 3 * sx, y: 20.1 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 5 * sy))
        p.addCurve(to: CGPoint(x: 5 * sx, y: 3 * sy), control1: CGPoint(x: 3 * sx, y: 3.9 * sy), control2: CGPoint(x: 3.9 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 3 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 21 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 12 * sy))
        return p
    }
}

struct LiveTVVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3 * sx, y: 7 * sy, width: 18 * sx, height: 14 * sy), cornerSize: CGSize(width: 3 * sx, height: 3 * sy))
        p.move(to: CGPoint(x: 8 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 3 * sy))
        return p
    }
}

struct HeartVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12 * sx, y: 20.4 * sy))
        p.addCurve(
            to: CGPoint(x: 2.5 * sx, y: 8.8 * sy),
            control1: CGPoint(x: 6.8 * sx, y: 16.7 * sy),
            control2: CGPoint(x: 2.5 * sx, y: 13.0 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 7.7 * sx, y: 3.6 * sy),
            control1: CGPoint(x: 2.5 * sx, y: 5.8 * sy),
            control2: CGPoint(x: 4.8 * sx, y: 3.6 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 12 * sx, y: 6.1 * sy),
            control1: CGPoint(x: 9.6 * sx, y: 3.6 * sy),
            control2: CGPoint(x: 11.2 * sx, y: 4.6 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 16.3 * sx, y: 3.6 * sy),
            control1: CGPoint(x: 12.8 * sx, y: 4.6 * sy),
            control2: CGPoint(x: 14.4 * sx, y: 3.6 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 21.5 * sx, y: 8.8 * sy),
            control1: CGPoint(x: 19.2 * sx, y: 3.6 * sy),
            control2: CGPoint(x: 21.5 * sx, y: 5.8 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 12 * sx, y: 20.4 * sy),
            control1: CGPoint(x: 21.5 * sx, y: 13.0 * sy),
            control2: CGPoint(x: 17.2 * sx, y: 16.7 * sy)
        )
        p.closeSubpath()
        return p
    }
}

struct FeedCommentBubbleVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12 * sx, y: 3 * sy))
        p.addCurve(
            to: CGPoint(x: 2.5 * sx, y: 11.4 * sy),
            control1: CGPoint(x: 6.7 * sx, y: 3 * sy),
            control2: CGPoint(x: 2.5 * sx, y: 6.8 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 5.2 * sx, y: 17.4 * sy),
            control1: CGPoint(x: 2.5 * sx, y: 13.7 * sy),
            control2: CGPoint(x: 3.5 * sx, y: 15.8 * sy)
        )
        p.addLine(to: CGPoint(x: 4.0 * sx, y: 21.2 * sy))
        p.addLine(to: CGPoint(x: 8.2 * sx, y: 19.6 * sy))
        p.addCurve(
            to: CGPoint(x: 12 * sx, y: 19.9 * sy),
            control1: CGPoint(x: 9.4 * sx, y: 19.8 * sy),
            control2: CGPoint(x: 10.7 * sx, y: 19.9 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 21.5 * sx, y: 11.4 * sy),
            control1: CGPoint(x: 17.3 * sx, y: 19.9 * sy),
            control2: CGPoint(x: 21.5 * sx, y: 16.1 * sy)
        )
        p.addCurve(
            to: CGPoint(x: 12 * sx, y: 3 * sy),
            control1: CGPoint(x: 21.5 * sx, y: 6.8 * sy),
            control2: CGPoint(x: 17.3 * sx, y: 3 * sy)
        )
        p.closeSubpath()
        return p
    }
}

struct FeedShareVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 21.5 * sx, y: 3.2 * sy))
        p.addLine(to: CGPoint(x: 2.8 * sx, y: 10.6 * sy))
        p.addLine(to: CGPoint(x: 10.4 * sx, y: 13.8 * sy))
        p.addLine(to: CGPoint(x: 13.6 * sx, y: 21.4 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 21.5 * sx, y: 3.2 * sy))
        p.addLine(to: CGPoint(x: 10.4 * sx, y: 13.8 * sy))
        return p
    }
}

struct BookmarkVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 6 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 3 * sy))
        p.addCurve(to: CGPoint(x: 19 * sx, y: 4 * sy), control1: CGPoint(x: 18.6 * sx, y: 3 * sy), control2: CGPoint(x: 19 * sx, y: 3.4 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 12 * sx, y: 16.5 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 4 * sy))
        p.addCurve(to: CGPoint(x: 6 * sx, y: 3 * sy), control1: CGPoint(x: 5 * sx, y: 3.4 * sy), control2: CGPoint(x: 5.4 * sx, y: 3 * sy))
        p.closeSubpath()
        return p
    }
}

struct MoreHorizVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        for cx in [5.5, 12.0, 18.5] {
            p.addEllipse(in: CGRect(x: (cx - 1.8) * sx, y: 10.2 * sy, width: 3.6 * sx, height: 3.6 * sy))
        }
        return p
    }
}

struct EqualizerVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        let bars: [(Double, Double, Double)] = [
            (4.5, 9.0, 15.0),
            (9.5, 5.0, 19.0),
            (14.5, 8.0, 16.0),
            (19.5, 11.0, 13.0)
        ]
        for (x, y1, y2) in bars {
            p.move(to: CGPoint(x: x * sx, y: y1 * sy))
            p.addLine(to: CGPoint(x: x * sx, y: y2 * sy))
        }
        return p
    }
}

struct RepostVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 17 * sx, y: 2 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 6 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 10 * sy))
        p.move(to: CGPoint(x: 3 * sx, y: 11 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 9 * sy))
        p.addCurve(to: CGPoint(x: 7 * sx, y: 6 * sy), control1: CGPoint(x: 3 * sx, y: 7.3 * sy), control2: CGPoint(x: 4.8 * sx, y: 6 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 6 * sy))
        p.move(to: CGPoint(x: 7 * sx, y: 22 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 18 * sy))
        p.addLine(to: CGPoint(x: 7 * sx, y: 14 * sy))
        p.move(to: CGPoint(x: 21 * sx, y: 13 * sy))
        p.addLine(to: CGPoint(x: 21 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 17 * sx, y: 18 * sy), control1: CGPoint(x: 21 * sx, y: 16.7 * sy), control2: CGPoint(x: 19.2 * sx, y: 18 * sy))
        p.addLine(to: CGPoint(x: 3 * sx, y: 18 * sy))
        return p
    }
}

struct BlockCircleVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 3 * sx, y: 3 * sy, width: 18 * sx, height: 18 * sy))
        p.move(to: CGPoint(x: 5.7 * sx, y: 5.7 * sy))
        p.addLine(to: CGPoint(x: 18.3 * sx, y: 18.3 * sy))
        return p
    }
}

struct FlagReportVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 5 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 9 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 14 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 14 * sy))
        return p
    }
}

struct LockVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 4 * sx, y: 11 * sy, width: 16 * sx, height: 10 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.move(to: CGPoint(x: 8 * sx, y: 11 * sy))
        p.addLine(to: CGPoint(x: 8 * sx, y: 7 * sy))
        p.addCurve(to: CGPoint(x: 16 * sx, y: 7 * sy), control1: CGPoint(x: 8 * sx, y: 4.5 * sy), control2: CGPoint(x: 16 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 11 * sy))
        return p
    }
}

struct EditPencilVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 4 * sx, y: 20 * sy))
        p.addLine(to: CGPoint(x: 8 * sx, y: 19 * sy))
        p.addLine(to: CGPoint(x: 19 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 5 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 16 * sy))
        p.closeSubpath()
        return p
    }
}

struct VisibilityEyeVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 2 * sx, y: 12 * sy))
        p.addCurve(to: CGPoint(x: 22 * sx, y: 12 * sy), control1: CGPoint(x: 6 * sx, y: 5 * sy), control2: CGPoint(x: 18 * sx, y: 5 * sy))
        p.addCurve(to: CGPoint(x: 2 * sx, y: 12 * sy), control1: CGPoint(x: 18 * sx, y: 19 * sy), control2: CGPoint(x: 6 * sx, y: 19 * sy))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: 9.5 * sx, y: 9.5 * sy, width: 5 * sx, height: 5 * sy))
        return p
    }
}

struct MenuDashesVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 4 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 7 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 12 * sy))
        p.move(to: CGPoint(x: 4 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 17 * sy))
        return p
    }
}

struct GridFourSquaresVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        let corner = CGSize(width: 2 * sx, height: 2 * sy)
        p.addRoundedRect(in: CGRect(x: 3 * sx, y: 3 * sy, width: 7.5 * sx, height: 7.5 * sy), cornerSize: corner)
        p.addRoundedRect(in: CGRect(x: 13.5 * sx, y: 3 * sy, width: 7.5 * sx, height: 7.5 * sy), cornerSize: corner)
        p.addRoundedRect(in: CGRect(x: 3 * sx, y: 13.5 * sy, width: 7.5 * sx, height: 7.5 * sy), cornerSize: corner)
        p.addRoundedRect(in: CGRect(x: 13.5 * sx, y: 13.5 * sy, width: 7.5 * sx, height: 7.5 * sy), cornerSize: corner)
        return p
    }
}

struct ShareNodesVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 15.8 * sx, y: 6.4 * sy))
        p.addLine(to: CGPoint(x: 8.2 * sx, y: 10.9 * sy))
        p.move(to: CGPoint(x: 8.2 * sx, y: 13.1 * sy))
        p.addLine(to: CGPoint(x: 15.8 * sx, y: 17.6 * sy))
        p.addEllipse(in: CGRect(x: 15.2 * sx, y: 2.8 * sy, width: 5.6 * sx, height: 5.6 * sy))
        p.addEllipse(in: CGRect(x: 3.2 * sx, y: 9.2 * sy, width: 5.6 * sx, height: 5.6 * sy))
        p.addEllipse(in: CGRect(x: 15.2 * sx, y: 15.6 * sy, width: 5.6 * sx, height: 5.6 * sy))
        return p
    }
}

struct SettingsGearVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addEllipse(in: CGRect(x: 9 * sx, y: 9 * sy, width: 6 * sx, height: 6 * sy))
        p.addEllipse(in: CGRect(x: 4.5 * sx, y: 4.5 * sy, width: 15 * sx, height: 15 * sy))
        let teeth: [(Double, Double, Double, Double)] = [
            (12, 1.5, 12, 4.5), (12, 19.5, 12, 22.5),
            (1.5, 12, 4.5, 12), (19.5, 12, 22.5, 12),
            (4.6, 4.6, 6.7, 6.7), (17.3, 17.3, 19.4, 19.4),
            (19.4, 4.6, 17.3, 6.7), (6.7, 17.3, 4.6, 19.4)
        ]
        for (x1, y1, x2, y2) in teeth {
            p.move(to: CGPoint(x: x1 * sx, y: y1 * sy))
            p.addLine(to: CGPoint(x: x2 * sx, y: y2 * sy))
        }
        return p
    }
}

struct PhotoFrameVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 3 * sx, y: 4 * sy, width: 18 * sx, height: 16 * sy), cornerSize: CGSize(width: 2 * sx, height: 2 * sy))
        p.addEllipse(in: CGRect(x: 7 * sx, y: 7.5 * sy, width: 2.8 * sx, height: 2.8 * sx))
        p.move(to: CGPoint(x: 5 * sx, y: 18 * sy))
        p.addLine(to: CGPoint(x: 10.5 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 14 * sx, y: 15.5 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 12.5 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 18 * sy))
        return p
    }
}

struct PlayTriangleVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 7 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 19.5 * sx, y: 12 * sy))
        p.addLine(to: CGPoint(x: 7 * sx, y: 19.5 * sy))
        p.closeSubpath()
        return p
    }
}

struct TrashVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 4 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 9 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 9 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 4 * sy))
        p.addLine(to: CGPoint(x: 15 * sx, y: 7 * sy))
        p.move(to: CGPoint(x: 6 * sx, y: 7 * sy))
        p.addLine(to: CGPoint(x: 7.5 * sx, y: 20 * sy))
        p.addLine(to: CGPoint(x: 16.5 * sx, y: 20 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 7 * sy))
        return p
    }
}



