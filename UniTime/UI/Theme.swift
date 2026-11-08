import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct Palette {
    var dark: Bool
    var ground: Color, card: Color, ink: Color, muted: Color
    var line: Color, divider: Color, segment: Color, segOn: Color
    var soft: Color, softInk: Color, hero: Color, heroTrack: Color
    var chevron: Color, error: Color
    /// Свой акцент у секретной темы — вместо выбранного в настройках.
    var accent: Color? = nil
    var heroBar: Color? = nil

    static let light = Palette(
        dark: false, ground: Color(hex: 0xF4F5F7), card: .white, ink: Color(hex: 0x11151C), muted: Color(hex: 0x5B6472),
        line: Color(hex: 0xE2E5EA), divider: Color(hex: 0xEEF0F3), segment: Color(hex: 0xE7E9EE), segOn: .white,
        soft: Color(hex: 0xE3E8FB), softInk: Color(hex: 0x2B44B8), hero: Color(hex: 0x141A26), heroTrack: Color(hex: 0x2A3244),
        chevron: Color(hex: 0x9AA2AE), error: Color(hex: 0x9B1C35)
    )

    /// Чёрная (AMOLED) тема.
    static let black = Palette(
        dark: true, ground: .black, card: Color(hex: 0x12151C), ink: Color(hex: 0xEDEFF3), muted: Color(hex: 0xA3ABB8),
        line: Color(hex: 0x2A3140), divider: Color(hex: 0x252C39), segment: Color(hex: 0x12151C), segOn: Color(hex: 0x323B4D),
        soft: Color(hex: 0x26304A), softInk: Color(hex: 0xB9C4FF), hero: Color(hex: 0x1A2133), heroTrack: Color(hex: 0x39445C),
        chevron: Color(hex: 0x6B7484), error: Color(hex: 0xFF8FA3)
    )

    static let neon = Palette(
        dark: true, ground: Color(hex: 0x0B0614), card: Color(hex: 0x170D28), ink: Color(hex: 0xF6EEFF), muted: Color(hex: 0xB3A3D1),
        line: Color(hex: 0x2E1C4A), divider: Color(hex: 0x241640), segment: Color(hex: 0x170D28), segOn: Color(hex: 0x3A2160),
        soft: Color(hex: 0x2A1450), softInk: Color(hex: 0x7DF9FF), hero: Color(hex: 0x1F0E3A), heroTrack: Color(hex: 0x3B2266),
        chevron: Color(hex: 0x7A6A99), error: Color(hex: 0xFF7A9C),
        accent: Color(hex: 0xFF4FD8), heroBar: Color(hex: 0x00E5FF)
    )
}

enum LookStyle: Int { case classic = 0, glass = 1, color = 2 }

/// Акценты: (светлая тема, тёмная тема).
let ACCENTS: [(name: String, light: Color, dark: Color)] = [
    ("Синий", Color(hex: 0x2F4FD8), Color(hex: 0x8EA2FF)),
    ("Зелёный", Color(hex: 0x0F7A55), Color(hex: 0x6FDDB0)),
    ("Оранжевый", Color(hex: 0xB4500B), Color(hex: 0xFFB27A)),
    ("Фиолетовый", Color(hex: 0x6D3FD1), Color(hex: 0xC3A6FF)),
]

/// Цвета пары по типу: fill и ink — карточка в списке, strong — главная карточка с белым текстом.
struct Tone { let fill: Color; let ink: Color; let strong: Color }

/// Текущее оформление: палитра, акцент, стиль и опции списков. Передаётся через Environment.
struct Look {
    var p: Palette = .light
    var accentIndex = 0
    var shortNames = true
    var pairNumbers = true
    var style: LookStyle = .classic

    private enum Kind { case light, black, neon }
    private var kind: Kind { !p.dark ? .light : (p.accent != nil ? .neon : .black) }

    var dark: Bool { p.dark }
    var ground: Color { p.ground }
    /// В «Стекле» все карточки — полупрозрачные поверх цветного фона.
    var card: Color { style == .glass ? glassFill() : p.card }
    var solidCard: Color { p.card }
    var ink: Color { p.ink }
    var muted: Color { p.muted }
    var line: Color { p.line }
    var divider: Color { p.divider }
    var segment: Color { style == .glass ? glassFill() : p.segment }
    var segOn: Color { p.segOn }
    var soft: Color { p.soft }
    var softInk: Color { p.softInk }
    var hero: Color { p.hero }
    var heroTrack: Color { p.heroTrack }
    var chevron: Color { p.chevron }
    var error: Color { p.error }
    var accent: Color { p.accent ?? (p.dark ? ACCENTS[accentIndex].dark : ACCENTS[accentIndex].light) }
    var heroBar: Color { p.heroBar ?? ACCENTS[accentIndex].dark }
    let heroMuted = Color(hex: 0xC9CED8)
    let heroLabel = Color(hex: 0xB9C4FF)
    let live = Color(hex: 0x7CF0B0)
    /// Текст поверх акцента.
    var onAccent: Color { p.dark ? Color(hex: 0x0F131B) : .white }
    /// Зелёный «идёт сейчас», который читается и на светлом стекле.
    var glassLive: Color { p.dark ? live : Color(hex: 0x0E8A4F) }

    func glassFill(strong: Bool = false) -> Color {
        switch kind {
        case .light: return Color.white.opacity(strong ? 0.78 : 0.6)
        case .black: return Color.white.opacity(strong ? 0.12 : 0.075)
        case .neon: return Color(hex: 0xF0D9FF).opacity(strong ? 0.12 : 0.07)
        }
    }

    var glassEdge: LinearGradient {
        switch kind {
        case .light: return LinearGradient(colors: [.white, Color(hex: 0x11151C, alpha: 0.1)], startPoint: .top, endPoint: .bottom)
        default: return LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// Пятна под стеклом: цвет, прозрачность, центр и радиус в долях ширины экрана.
    var spots: [(Color, Double, CGFloat, CGFloat, CGFloat)] {
        switch kind {
        case .light: return [(Color(hex: 0xA48BFF), 0.55, 0.10, 0.30, 0.80), (Color(hex: 0xFF9CCB), 0.45, 0.98, 0.45, 0.70),
                             (Color(hex: 0x7FDCEB), 0.50, 0.15, 1.05, 0.85), (Color(hex: 0x9DB2FF), 0.45, 0.95, 1.55, 0.75)]
        case .black: return [(Color(hex: 0x5B3BFF), 0.55, 0.08, 0.30, 0.85), (Color(hex: 0xD1338A), 0.38, 1.00, 0.50, 0.70),
                             (Color(hex: 0x0AA0B4), 0.40, 0.12, 1.10, 0.85), (Color(hex: 0x2F55FF), 0.40, 0.95, 1.60, 0.80)]
        case .neon: return [(Color(hex: 0xFF4FD8), 0.45, 0.08, 0.30, 0.85), (Color(hex: 0x7B2CFF), 0.55, 1.00, 0.55, 0.80),
                            (Color(hex: 0x00E5FF), 0.32, 0.12, 1.15, 0.85), (Color(hex: 0xFF4FD8), 0.25, 0.95, 1.65, 0.75)]
        }
    }

    /// Цвета пары в стиле «Цвет пар»; nil — тип неизвестен.
    func typeTone(_ type: String) -> Tone? {
        func t(_ f: UInt32, _ i: UInt32, _ s: UInt32) -> Tone { Tone(fill: Color(hex: f), ink: Color(hex: i), strong: Color(hex: s)) }
        switch kind {
        case .light:
            switch type {
            case "ЛК": return t(0x9BE8BF, 0x0B3A22, 0x0E8A4F)
            case "ПЗ": return t(0xFFC58F, 0x4A2400, 0xD45A08)
            case "ЛР": return t(0xB3C6FF, 0x0E2366, 0x3A55E0)
            case "Экз", "Экзамен": return t(0xFFB3C0, 0x5A0F1F, 0xC92A47)
            case "Конс", "Консультация": return t(0xD7C2FF, 0x2E1366, 0x7046F0)
            default: return nil
            }
        case .black:
            switch type {
            case "ЛК": return t(0x5FD39A, 0x052615, 0x0E8A4F)
            case "ПЗ": return t(0xFFA45C, 0x2E1400, 0xD45A08)
            case "ЛР": return t(0x8FA8FF, 0x08154A, 0x3A55E0)
            case "Экз", "Экзамен": return t(0xFF8A9C, 0x3A0712, 0xC92A47)
            case "Конс", "Консультация": return t(0xB897FF, 0x1E0B47, 0x7046F0)
            default: return nil
            }
        case .neon:
            switch type {
            case "ЛК": return t(0x3DFFB4, 0x00261A, 0x009660)
            case "ПЗ": return t(0xFFB547, 0x2E1700, 0xE55A00)
            case "ЛР": return t(0x2DE6FF, 0x00262B, 0x0068E0)
            case "Экз", "Экзамен": return t(0xFF5C9A, 0x2E0014, 0xE0005A)
            case "Конс", "Консультация": return t(0xFF6FE0, 0x2E0026, 0xB000FF)
            default: return nil
            }
        }
    }

    /// Цвет метки и полное название типа занятия.
    func typeStyle(_ type: String) -> (bg: Color, fg: Color, name: String) {
        func t(_ lb: UInt32, _ lf: UInt32, _ db: UInt32, _ df: UInt32, _ name: String) -> (Color, Color, String) {
            dark ? (Color(hex: db), Color(hex: df), name) : (Color(hex: lb), Color(hex: lf), name)
        }
        switch type {
        case "ЛК": return t(0xDCF2E8, 0x0E5E3E, 0x173A2C, 0x8BE3BC, "Лекция")
        case "ПЗ": return t(0xFDE7D6, 0x9A3A0B, 0x3E2516, 0xFFB98A, "Практика")
        case "ЛР": return t(0xE3E8FB, 0x2B44B8, 0x232D52, 0xB4C2FF, "Лабораторная")
        case "Экз", "Экзамен": return t(0xFBE2E6, 0x9B1C35, 0x44202A, 0xFFA3B4, "Экзамен")
        case "Конс", "Консультация": return t(0xEDE4FB, 0x5B2AA8, 0x2F2448, 0xD3BCFF, "Консультация")
        default: return (segment, ink, type.ifBlank("Занятие"))
        }
    }

    /// Название предмета с учётом настройки «коротко».
    func title(_ l: Lesson) -> String { shortNames ? l.subject : l.fullTitle }
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look()
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}

// MARK: Стекло

/// Цветной фон под стеклянными карточками. Пятна один раз мягко проявляются и дальше стоят.
struct GlassBackdrop: View {
    @Environment(\.look) private var C
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                ForEach(Array(C.spots.enumerated()), id: \.offset) { _, s in
                    Circle()
                        .fill(RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: s.0.opacity(s.1), location: 0),
                                .init(color: s.0.opacity(s.1 * 0.45), location: 0.55),
                                .init(color: .clear, location: 1),
                            ]),
                            center: .center, startRadius: 0, endRadius: s.4 * w))
                        .frame(width: s.4 * w * 2, height: s.4 * w * 2)
                        .position(x: s.2 * w, y: s.3 * w)
                }
            }
            .opacity(shown ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 1.4)) { shown = true } }
        .allowsHitTesting(false)
    }
}

struct GlassModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.look) private var C
    let shape: S
    let strong: Bool

    func body(content: Content) -> some View {
        content
            .background(shape.fill(C.glassFill(strong: strong)))
            .overlay(shape.strokeBorder(C.glassEdge, lineWidth: 1))
            .clipShape(shape)
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, strong: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, strong: strong))
    }

    /// Карточка с фоном в текущем стиле (в «Стекле» — стеклянная).
    func card(_ radius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(radius: radius, padding: padding))
    }
}

struct CardModifier: ViewModifier {
    @Environment(\.look) private var C
    let radius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        // В «Стекле» C.card уже полупрозрачный — как background(C.Card) в оригинале.
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(C.card, in: shape)
    }
}
