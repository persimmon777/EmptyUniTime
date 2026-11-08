import SwiftUI

extension View {
    /// Высота строки как lineHeight в Compose: межстрочный интервал = lineHeight − собственная высота строки Roboto (1,172 em).
    func lineHeight(_ lh: CGFloat, size: CGFloat) -> some View {
        lineSpacing(max(lh - size * 1.172, 0))
    }

    /// Текст как в Compose: в MaterialTheme у Text по умолчанию стиль bodyLarge — разрядка 0,5
    /// и высота строки 24 (текст по центру строки, без обрезки). Отсюда «воздух» вокруг подписей в оригинале.
    /// `lh` — lineHeight из макета, `track` — letterSpacing.
    func ct(_ size: CGFloat, _ weight: Font.Weight = .regular, lh: CGFloat = 24, track: CGFloat = 0.5) -> some View {
        let extra = lh - size * 1.172
        return font(.roboto(size, weight))
            .tracking(track)
            .lineSpacing(max(extra, 0))
            .padding(.vertical, extra / 2)
    }
}

// MARK: Переключатель Material 3

/// Тот же Switch, что в Android-версии: дорожка 52×32, бегунок 16 → 24.
struct MaterialSwitch: View {
    @Environment(\.look) private var C
    @Binding var on: Bool

    var body: some View {
        let track = on ? C.accent : (C.dark ? Color(hex: 0x36343B) : Color(hex: 0xE6E0E9))
        let outline = C.dark ? Color(hex: 0x938F99) : Color(hex: 0x79747E)
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(track)
                .overlay(Capsule().strokeBorder(on ? Color.clear : outline, lineWidth: 2))
            Circle().fill(on ? C.onAccent : outline)
                .frame(width: on ? 24 : 16, height: on ? 24 : 16)
                .padding(.horizontal, on ? 4 : 8)
        }
        .frame(width: 52, height: 32)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { on.toggle() } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "включено" : "выключено")
    }
}

// MARK: Диалог Material 3

/// AlertDialog как в Android: карточка по центру поверх затемнения, заголовок, содержимое, кнопки справа внизу.
struct MaterialDialog<Content: View>: View {
    @Environment(\.look) private var C
    let title: String
    let confirm: String
    var confirmEnabled = true
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.roboto(24)).foregroundStyle(C.ink)
                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
                    .scrollBounceBehavior(.basedOnSize)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Отмена").font(.roboto(14, .medium)).tracking(0.1).foregroundStyle(C.muted)
                            .padding(.horizontal, 12).frame(minHeight: 40)
                    }
                    Button(action: onConfirm) {
                        Text(confirm).font(.roboto(14, .semibold)).tracking(0.1).foregroundStyle(confirmEnabled ? C.accent : C.muted)
                            .padding(.horizontal, 12).frame(minHeight: 40)
                    }
                    .disabled(!confirmEnabled)
                }
            }
            .padding(24)
            .background(C.ground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
        }
        .transition(.opacity)
    }
}

// MARK: Анимации из Motion.kt

/// Когда показан экран: карточки, появившиеся в первые полсекунды, выезжают по очереди.
private struct EnterClockKey: EnvironmentKey { static let defaultValue: Date? = nil }

extension EnvironmentValues {
    var enterClock: Date? {
        get { self[EnterClockKey.self] }
        set { self[EnterClockKey.self] = newValue }
    }
}

private struct EnterModifier: ViewModifier {
    @Environment(\.enterClock) private var clock
    let index: Int
    @State private var shown: Bool?

    func body(content: Content) -> some View {
        content
            .opacity(shown == false ? 0 : 1)
            .offset(y: shown == false ? 22 : 0)
            .onAppear {
                guard shown == nil else { return }
                guard let c = clock, Date().timeIntervalSince(c) < 0.5 else { shown = true; return }
                shown = false
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(min(index, 8)) * 0.045)) { shown = true }
            }
    }
}

extension View {
    /// Плавное появление снизу; index — порядок на экране, задаёт задержку.
    func enter(_ index: Int) -> some View { modifier(EnterModifier(index: index)) }
}

/// Число, которое «досчитывается» от нуля при появлении: «8,42», «24 ч».
struct CountUpText: View {
    let value: String
    let color: Color
    let size: CGFloat
    var weight: Font.Weight = .heavy
    @State private var p: Double = 0

    var body: some View {
        CountUpLabel(value: value, progress: p)
            .font(.roboto(size, weight)).foregroundStyle(color)
            .onAppear { withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.9)) { p = 1 } }
    }
}

private struct CountUpLabel: View, Animatable {
    let value: String
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(shown)
    }

    private var shown: String {
        guard let re = try? NSRegularExpression(pattern: "^(\\d+)(?:([.,])(\\d+))?(.*)$"),
              let m = re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return value }
        func g(_ i: Int) -> String { Range(m.range(at: i), in: value).map { String(value[$0]) } ?? "" }
        let int = g(1), sep = g(2), frac = g(3), rest = g(4)
        let target = Double("\(int).\(frac.isEmpty ? "0" : frac)") ?? 0
        let v = target * progress
        if frac.isEmpty { return "\(Int(v.rounded()))\(rest)" }
        return String(format: "%.\(frac.count)f", v).replacingOccurrences(of: ".", with: sep) + rest
    }
}

/// Точка «идёт сейчас» с расходящимся кольцом.
struct LiveDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        TimelineView(.animation) { t in
            let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let e = 1 - (1 - p) * (1 - p)
            ZStack {
                Circle().fill(color).frame(width: size, height: size)
                    .scaleEffect(1 + e * 1.8).opacity((1 - p) * 0.6)
                Circle().fill(color).frame(width: size, height: size)
            }
            .frame(width: size * 3, height: size * 3)
        }
        .frame(width: size, height: size)
    }
}
