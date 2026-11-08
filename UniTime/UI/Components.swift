import SwiftUI

// Компоненты один в один с Components.kt / DetailScreens.kt Android-версии: те же размеры (dp → pt), шрифты и цвета.

// MARK: Тексты и плашки

struct ScreenTitle: View {
    @Environment(\.look) private var C
    let over: String?
    let title: String

    init(_ over: String?, _ title: String) {
        self.over = over
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let over = over { Text(over).ct(14, .medium).foregroundStyle(C.muted) }
            Text(title).ct(28, .heavy, track: -0.5).foregroundStyle(C.ink)
        }
    }
}

struct SectionLabel: View {
    @Environment(\.look) private var C
    let text: String
    var color: Color? = nil
    var top: CGFloat = 0
    init(_ text: String, color: Color? = nil, top: CGFloat = 0) { self.text = text; self.color = color; self.top = top }

    var body: some View {
        Text(text.uppercased()).ct(13, .semibold).foregroundStyle(color ?? C.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, top)
    }
}

struct SectionTitle: View {
    @Environment(\.look) private var C
    let text: String
    var right: String? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            Text(text).ct(17, .bold).foregroundStyle(C.ink)
            Spacer()
            if let right = right { Text(right).ct(13).foregroundStyle(C.muted) }
        }
        .padding(.top, 6)
    }
}

struct Pill: View {
    @Environment(\.look) private var C
    let text: String
    let bg: Color
    let fg: Color
    var border = false
    var action: (() -> Void)? = nil

    var body: some View {
        let label = Text(text).ct(13, .semibold).foregroundStyle(fg).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(border ? C.line : .clear, lineWidth: 1))
        if let action = action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

struct TypeChip: View {
    @Environment(\.look) private var C
    let type: String
    var full = false

    var body: some View {
        if !type.isBlank {
            let s = C.typeStyle(type)
            Text(full ? s.name : type).ct(12, .bold).foregroundStyle(s.fg).lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(s.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Плашка выбора (Choice).
struct Choice: View {
    @Environment(\.look) private var C
    let label: String
    let on: Bool
    let action: () -> Void

    init(_ label: String, _ on: Bool, action: @escaping () -> Void) {
        self.label = label
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label).ct(13, .semibold).foregroundStyle(on ? C.onAccent : C.ink).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(minHeight: 36)
                .background(on ? C.accent : C.card, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? C.accent : C.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// bounceClick: карточка чуть «проседает» под пальцем (0.96) и пружинит обратно.
struct Bounce: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.interpolatingSpring(stiffness: 420, damping: 25), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Круглая кнопка 44 с иконкой 22 (RoundButton / TopButton).
struct RoundButton: View {
    @Environment(\.look) private var C
    let glyph: GlyphKind
    let label: String
    var glassy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if glassy {
                    Glyph(glyph, C.ink, 22).frame(width: 44, height: 44).glass(Circle())
                } else {
                    Glyph(glyph, C.ink, 22).frame(width: 44, height: 44).background(C.card, in: Circle())
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(glassy ? AnyButtonStyle(Bounce()) : AnyButtonStyle(.plain))
        .accessibilityLabel(label)
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    init(_ s: PlainButtonStyle) { make = { AnyView($0.label) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Шапка вложенного экрана: кнопка «назад» и, справа, необязательная кнопка.
struct BackBar: View {
    @EnvironmentObject private var model: AppModel
    var trailing: (glyph: GlyphKind, label: String, action: () -> Void)? = nil

    var body: some View {
        HStack {
            RoundButton(glyph: .back, label: "Назад") { model.back() }
            Spacer()
            if let t = trailing { RoundButton(glyph: t.glyph, label: t.label, action: t.action) }
        }
    }
}

struct BigButton: View {
    @Environment(\.look) private var C
    let text: String
    var primary = true
    var enabled = true
    var busy = false
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(C.onAccent) }
                else {
                    Text(text).ct(16, .bold).foregroundStyle(!enabled ? C.muted : primary ? C.onAccent : C.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(!enabled ? C.segment : primary ? C.accent : C.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

struct Segmented: View {
    @Environment(\.look) private var C
    let labels: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = labels.count > 3 ? 4 : 6
            let n = CGFloat(max(labels.count, 1))
            let w = (geo.size.width - gap * (n - 1)) / n
            let sel = min(max(selected, 0), labels.count - 1)
            ZStack(alignment: .leading) {
                // Подложка выбранного пункта переезжает с пружинкой.
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.segOn)
                    .frame(width: w, height: 40)
                    .offset(x: (w + gap) * CGFloat(sel))
                    .animation(.interpolatingSpring(stiffness: 420, damping: 25), value: sel)
                HStack(spacing: gap) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                        Button { onSelect(i) } label: {
                            Text(label).ct(labels.count > 3 ? 13 : 14, .semibold).lineLimit(1)
                                .foregroundStyle(i == sel ? C.ink : C.muted)
                                .animation(.easeInOut(duration: 0.2), value: sel)
                                .frame(width: w, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 40)
        .padding(4)
        .background(C.segment, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Полоска прогресса; при появлении плавно заполняется от нуля.
struct ProgressBar: View {
    let fraction: Double
    let track: Color
    let bar: Color
    var height: CGFloat = 6
    @State private var shown = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(bar).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)) { shown = min(max(fraction, 0), 1) } }
        .onChange(of: fraction) { _, v in withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)) { shown = min(max(v, 0), 1) } }
    }
}

struct EmptyCard: View {
    @Environment(\.look) private var C
    let title: String
    let text: String
    var glyph: GlyphKind = .calendar
    var action: (() -> Void)? = nil

    var body: some View {
        let glass = C.style == .glass
        let content = VStack(spacing: 10) {
            Glyph(glyph, C.muted, 28)
                .frame(width: 56, height: 56)
                .background(glass ? C.glassFill() : C.ground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title).ct(17, .bold).foregroundStyle(C.ink).multilineTextAlignment(.center)
            Text(text).ct(14, lh: 20).foregroundStyle(C.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 28)
        .card(22, padding: 0)
        if let action = action {
            Button(action: action) { content }.buttonStyle(Bounce())
        } else {
            content
        }
    }
}

struct InfoTile: View {
    @Environment(\.look) private var C
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ct(12, .medium).foregroundStyle(C.muted)
            Text(value).ct(17, .bold).foregroundStyle(C.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Field: View {
    @Environment(\.look) private var C
    @Binding var text: String
    let placeholder: String
    var number = false
    var secure = false
    var glyph: GlyphKind? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let g = glyph { Glyph(g, C.muted, 20) }
            ZStack(alignment: .leading) {
                if text.isEmpty { Text(placeholder).font(.roboto(15)).foregroundStyle(C.muted).lineLimit(1) }
                Group {
                    if secure {
                        SecureField("", text: $text).textContentType(.password)
                    } else {
                        TextField("", text: $text).keyboardType(number ? .numberPad : .default)
                    }
                }
                .font(.roboto(15))
                .foregroundStyle(C.ink)
                .tint(C.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(C.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(C.line, lineWidth: 1))
    }
}

/// Строка-переключатель (Toggle): заголовок 15, подпись 12 и Switch из Material 3.
struct ToggleRow: View {
    @Environment(\.look) private var C
    let title: String
    var sub: String? = nil
    @Binding var on: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).ct(15, .medium).foregroundStyle(C.ink)
                if let sub = sub { Text(sub).ct(12).foregroundStyle(C.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MaterialSwitch(on: $on)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { on.toggle() } }
    }
}

/// Строка-ссылка в карточке: иконка акцентом, заголовок, подпись, шеврон.
struct LinkRow: View {
    @Environment(\.look) private var C
    let glyph: GlyphKind
    let title: String
    var sub: String? = nil
    var glyphSize: CGFloat = 22
    var subSize: CGFloat = 13
    var hPad: CGFloat = 14
    var vPad: CGFloat = 14
    var spacing: CGFloat = 12
    var minHeight: CGFloat = 0
    var bounce = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: spacing) {
                Glyph(glyph, C.accent, glyphSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).ct(15, .semibold).foregroundStyle(C.ink)
                    if let sub = sub { Text(sub).ct(subSize).foregroundStyle(C.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(.chevron, C.chevron, 18)
            }
            .padding(.horizontal, hPad).padding(.vertical, vPad)
            .frame(minHeight: minHeight)
            .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(bounce ? AnyButtonStyle(Bounce()) : AnyButtonStyle(.plain))
    }
}

struct Divider1: View {
    @Environment(\.look) private var C
    var body: some View { Rectangle().fill(C.divider).frame(height: 1) }
}

// MARK: Между парами

struct BreakRow: View {
    @Environment(\.look) private var C
    let minutes: Int
    var body: some View {
        Text("перемена \(minutes) мин").ct(11).foregroundStyle(C.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
    }
}

struct WindowRow: View {
    @Environment(\.look) private var C
    let minutes: Int
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(C.line).frame(height: 1)
            Text("Окно \(minutesText(minutes))").ct(12, .semibold).foregroundStyle(C.muted).fixedSize()
            Rectangle().fill(C.line).frame(height: 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 2)
    }
}

/// Что рисовать между парами: обычную перемену, окно или ничего.
struct Between: View {
    let gap: Int?
    var body: some View {
        if let g = gap, g > 0 {
            if g > 30 { WindowRow(minutes: g) } else { BreakRow(minutes: g) }
        }
    }
}

// MARK: Строка пары

struct LessonRow: View {
    @Environment(\.look) private var C
    let o: Occurrence
    let faded: Bool
    let highlighted: Bool
    let showGroups: Bool
    var extra: String? = nil
    var styled = true
    let action: () -> Void

    var body: some View {
        let l = o.lesson
        let place = [l.rooms, showGroups ? l.groups : l.teacher].filter { !$0.isBlank }.joined(separator: " · ")
        let glass = styled && C.style == .glass
        let tone = styled && C.style == .color ? C.typeTone(l.type) : nil
        let ink = tone?.ink ?? C.ink
        let muted = tone.map { $0.ink.opacity(0.7) } ?? C.muted
        let shape = RoundedRectangle(cornerRadius: glass || tone != nil ? 22 : 18, style: .continuous)

        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    if C.pairNumbers, let n = pairNumber(l.start) {
                        Text("\(n) пара").ct(11).foregroundStyle(muted).fixedSize()
                    }
                    Text(l.start.description).ct(15, .bold).foregroundStyle(ink).fixedSize()
                    Text(l.end.description).ct(12).foregroundStyle(muted).fixedSize()
                }
                .frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(C.title(l)).ct(15, .semibold).foregroundStyle(ink).lineLimit(1)
                    let sub = l.subgroup != 0 ? "\(place) · п/г \(l.subgroup)" : place
                    if !sub.isBlank { Text(sub).ct(13).foregroundStyle(muted).lineLimit(1) }
                    if let extra = extra {
                        Text(extra).ct(13, .semibold).foregroundStyle(tone?.ink ?? C.accent).lineLimit(1)
                    }
                    if !l.note.isBlank {
                        Text(l.note).ct(13, .semibold).foregroundStyle(tone?.ink ?? C.accent).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let tone = tone {
                    // На цветной карточке метка «наизнанку»: тёмная плашка, буквы цвета карточки.
                    Text(l.type).ct(12, .bold).foregroundStyle(tone.fill).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tone.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    TypeChip(type: l.type)
                }
            }
            .padding(.horizontal, tone != nil ? 16 : 14).padding(.vertical, 12)
            .background {
                if let tone = tone {
                    shape.fill(tone.fill)
                } else if glass {
                    Color.clear.glass(shape)
                } else {
                    shape.fill(C.card)
                }
            }
            .overlay {
                if let tone = tone {
                    shape.strokeBorder(highlighted ? tone.strong : tone.fill, lineWidth: 2)
                } else if glass {
                    if highlighted { shape.strokeBorder(C.accent, lineWidth: 1.5) }
                } else {
                    shape.strokeBorder(highlighted ? C.accent : C.card, lineWidth: 1)
                }
            }
            .opacity(faded ? (tone != nil ? 0.42 : 0.5) : 1)
        }
        .buttonStyle(Bounce())
    }
}

// MARK: Фото преподавателя

/// Фото преподавателя из IIS с кэшем на диске; пока грузится или если его нет — инициалы.
struct TeacherPhoto: View {
    @Environment(\.look) private var C
    let teacher: Teacher
    let size: CGFloat
    @State private var image: UIImage?
    @State private var full = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Group {
            if let img = image {
                Button { full = true } label: {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Фото: \(teacher.full)")
            } else {
                Text(teacher.initials).font(.roboto(size * 0.34, .bold)).foregroundStyle(C.softInk)
                    .frame(width: size, height: size).background(C.soft, in: shape)
            }
        }
        .task(id: teacher.id) { image = await PhotoCache.load(teacher) }
        .fullScreenCover(isPresented: $full) {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(teacher.full).ct(17, .semibold).foregroundStyle(.white).padding(32)
            }
            .onTapGesture { full = false }
        }
    }
}

enum PhotoCache {
    static func load(_ t: Teacher) async -> UIImage? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
        let f = dir.appendingPathComponent("\(t.id).img")
        if let data = try? Data(contentsOf: f), let img = UIImage(data: data) { return img }
        guard let data = try? await Net.get(t.photoUrl), let img = UIImage(data: data) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: f)
        return img
    }
}

// MARK: Раскладка «в строку с переносом» (FlowRow)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let ls = lineSpacing ?? spacing
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + ls; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ls = lineSpacing ?? spacing
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + ls; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(s.width, bounds.width), height: s.height))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: Экран-список

/// Прокручиваемый экран (LazyColumn): отступы по краям 20, сверху `top`, между элементами `spacing`.
/// Карточки, видимые при открытии, выезжают по очереди (как Modifier.enter).
struct Screen<Content: View>: View {
    var spacing: CGFloat = 14
    var top: CGFloat = 12
    var bottom: CGFloat = 32
    @ViewBuilder let content: () -> Content
    @State private var opened = Date()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 20)
                .padding(.top, top)
                .padding(.bottom, bottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .environment(\.enterClock, opened)
    }
}

/// Фон экрана: цвет темы и, в «Стекле», цветные пятна.
struct ScreenBackground: View {
    @Environment(\.look) private var C
    var body: some View {
        ZStack {
            C.ground.ignoresSafeArea()
            if C.style == .glass { GlassBackdrop() }
        }
    }
}

extension View {
    /// Вложенный экран: без системной панели навигации (кнопка «назад» — своя, как в оригинале), жест «назад» работает.
    func pushedScreen() -> some View {
        self.background(ScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Свайп от края «назад» при скрытой панели навигации.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: Нижняя панель

/// BottomNav: в «Стекле» и «Цвете пар» — парящая плашка, в обычном стиле — во всю ширину цвета карточки.
/// Подсветка под иконкой перепрыгивает на выбранную вкладку, иконка «подпрыгивает».
struct BottomNav: View {
    @Environment(\.look) private var C
    let current: Tab
    let onSelect: (Tab) -> Void

    var body: some View {
        let floating = C.style != .classic
        let solid = C.style == .color
        let glow: Color = C.style == .glass ? C.accent.opacity(0.2) : solid ? C.ink : C.soft
        let bar = GeometryReader { geo in
            let cell = geo.size.width / CGFloat(Tab.allCases.count)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(glow)
                    .frame(width: 56, height: 30)
                    .offset(x: cell * CGFloat(current.rawValue) + (cell - 56) / 2, y: 4)
                    .animation(.interpolatingSpring(stiffness: 420, damping: 25), value: current)
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        NavItem(tab: tab, on: tab == current, solid: solid) { onSelect(tab) }
                    }
                }
            }
        }
        .frame(height: 64)
        if floating {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            Group {
                if C.style == .glass {
                    bar.padding(.horizontal, 4).padding(.vertical, 6).glass(shape, strong: true)
                } else {
                    bar.padding(.horizontal, 4).padding(.vertical, 6)
                        .background(C.card, in: shape)
                        .overlay(shape.strokeBorder(C.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
        } else {
            bar.padding(.horizontal, 4).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(C.card.ignoresSafeArea(edges: .bottom))
        }
    }
}

private struct NavItem: View {
    @Environment(\.look) private var C
    let tab: Tab
    let on: Bool
    let solid: Bool
    let action: () -> Void
    @State private var pop: CGFloat = 1

    var body: some View {
        let color = on ? (solid ? C.ink : C.accent) : C.muted
        let iconColor = on && solid ? C.ground : color
        Button(action: action) {
            VStack(spacing: 4) {
                Glyph(tab.glyph, iconColor, 24)
                    .frame(height: 30)
                    .scaleEffect(pop)
                Text(tab.label).ct(12, on ? .semibold : .medium, lh: 16).foregroundStyle(color).lineLimit(1).fixedSize()
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: on)
        .onChange(of: on) { _, v in
            guard v else { return }
            pop = 0.75
            withAnimation(.interpolatingSpring(stiffness: 500, damping: 18)) { pop = 1 }
        }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
