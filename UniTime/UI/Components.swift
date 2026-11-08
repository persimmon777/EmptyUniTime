import SwiftUI

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
            if let over = over { Text(over).font(.system(size: 14, weight: .medium)).foregroundStyle(C.muted) }
            Text(title).font(.system(size: 28, weight: .heavy)).tracking(-0.5).foregroundStyle(C.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    @Environment(\.look) private var C
    let text: String
    var color: Color? = nil
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold)).tracking(0.5)
            .foregroundStyle(color ?? C.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct SectionTitle: View {
    @Environment(\.look) private var C
    let text: String
    var right: String? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            Text(text).font(.system(size: 17, weight: .bold)).foregroundStyle(C.ink)
            Spacer()
            if let right = right { Text(right).font(.system(size: 13)).foregroundStyle(C.muted) }
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
        let label = Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(border ? C.line : .clear, lineWidth: 1))
        if let action = action {
            Button(action: action) { label }.buttonStyle(Bounce())
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
            Text(full ? s.name : type)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(s.fg)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(s.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Плашка выбора (как Choice в Android-версии).
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
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? C.onAccent : C.ink)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(minHeight: 36)
                .background(on ? C.accent : C.card, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? C.accent : C.line, lineWidth: 1))
        }
        .buttonStyle(Bounce())
    }
}

/// Нажатие с лёгким «проседанием».
struct Bounce: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct RoundButton: View {
    @Environment(\.look) private var C
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if C.style == .glass {
                    Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(C.ink)
                        .frame(width: 44, height: 44).glass(Circle())
                } else {
                    Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(C.ink)
                        .frame(width: 44, height: 44).background(C.card, in: Circle())
                }
            }
        }
        .buttonStyle(Bounce())
        .accessibilityLabel(label)
    }
}

struct BigButton: View {
    @Environment(\.look) private var C
    let text: String
    var primary = true
    var enabled = true
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(C.onAccent) }
                else {
                    Text(text).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(!enabled ? C.muted : primary ? C.onAccent : C.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(!enabled ? C.segment : primary ? C.accent : C.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Bounce())
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
            let w = (geo.size.width - 8 - gap * CGFloat(labels.count - 1)) / CGFloat(max(labels.count, 1))
            let sel = min(max(selected, 0), labels.count - 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(C.segOn)
                    .frame(width: w, height: 40)
                    .offset(x: (w + gap) * CGFloat(sel))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: sel)
                HStack(spacing: gap) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                        Button { onSelect(i) } label: {
                            Text(label)
                                .font(.system(size: labels.count > 3 ? 13 : 14, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(i == sel ? C.ink : C.muted)
                                .frame(width: w, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(4)
        }
        .frame(height: 48)
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
        .onAppear { withAnimation(.easeInOut(duration: 0.9)) { shown = min(max(fraction, 0), 1) } }
        .onChange(of: fraction) { _, v in withAnimation(.easeInOut(duration: 0.9)) { shown = min(max(v, 0), 1) } }
    }
}

struct EmptyCard: View {
    @Environment(\.look) private var C
    let title: String
    let text: String
    var symbol = "calendar"
    var action: (() -> Void)? = nil

    var body: some View {
        let content = VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(C.muted)
                .frame(width: 56, height: 56)
                .background(C.style == .glass ? C.glassFill() : C.ground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(C.ink).multilineTextAlignment(.center)
            Text(text).font(.system(size: 14)).foregroundStyle(C.muted).multilineTextAlignment(.center).lineSpacing(3)
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
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(C.muted)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(C.ink).lineLimit(2).minimumScaleFactor(0.8)
        }
        .card(18, padding: 14)
    }
}

struct Field: View {
    @Environment(\.look) private var C
    @Binding var text: String
    let placeholder: String
    var number = false
    var secure = false
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let s = symbol { Image(systemName: s).foregroundStyle(C.muted) }
            Group {
                if secure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(C.muted))
                        .textContentType(.password)
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(C.muted))
                        .keyboardType(number ? .numberPad : .default)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(C.ink)
            .tint(C.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(C.style == .glass ? C.glassFill(strong: true) : C.solidCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(C.line, lineWidth: 1))
    }
}

struct ToggleRow: View {
    @Environment(\.look) private var C
    let title: String
    var sub: String? = nil
    @Binding var on: Bool

    var body: some View {
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(C.ink)
                if let sub = sub { Text(sub).font(.system(size: 12)).foregroundStyle(C.muted) }
            }
        }
        .tint(C.accent)
        .frame(minHeight: 44)
    }
}

/// Строка-ссылка: значок, заголовок, подпись, шеврон.
struct LinkRow: View {
    @Environment(\.look) private var C
    let symbol: String
    let title: String
    var sub: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(C.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(C.ink)
                    if let sub = sub { Text(sub).font(.system(size: 12)).foregroundStyle(C.muted) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(C.chevron)
            }
            .frame(minHeight: 30)
            .card(18)
        }
        .buttonStyle(Bounce())
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
        Text("перемена \(minutes) мин").font(.system(size: 11)).foregroundStyle(C.muted)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
    }
}

struct WindowRow: View {
    @Environment(\.look) private var C
    let minutes: Int
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(C.line).frame(height: 1)
            Text("Окно \(minutesText(minutes))").font(.system(size: 12, weight: .semibold)).foregroundStyle(C.muted).fixedSize()
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
                VStack(alignment: .leading, spacing: 1) {
                    if C.pairNumbers, let n = pairNumber(l.start) {
                        Text("\(n) пара").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Text(l.start.description).font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                    Text(l.end.description).font(.system(size: 12)).foregroundStyle(muted)
                }
                .frame(width: 50, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(C.title(l)).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    let sub = l.subgroup != 0 ? "\(place) · п/г \(l.subgroup)" : place
                    if !sub.isBlank { Text(sub).font(.system(size: 13)).foregroundStyle(muted).lineLimit(1) }
                    if let extra = extra {
                        Text(extra).font(.system(size: 13, weight: .semibold)).foregroundStyle(tone?.ink ?? C.accent).lineLimit(1)
                    }
                    if !l.note.isBlank {
                        Text(l.note).font(.system(size: 13, weight: .semibold)).foregroundStyle(tone?.ink ?? C.accent).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let tone = tone, !l.type.isBlank {
                    // На цветной карточке метка «наизнанку»: тёмная плашка, буквы цвета карточки.
                    Text(l.type).font(.system(size: 12, weight: .bold)).foregroundStyle(tone.fill)
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
                    shape.strokeBorder(highlighted ? tone.strong : .clear, lineWidth: 2)
                } else {
                    shape.strokeBorder(highlighted ? C.accent : .clear, lineWidth: glass ? 1.5 : 1)
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
                Text(teacher.initials).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(C.softInk)
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
                Text(teacher.full).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).padding(32)
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

// MARK: Раскладка «в строку с переносом»

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: Экран-список

/// Прокручиваемый экран с отступами, как LazyColumn в Android-версии.
struct Screen<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
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
    /// Стандартное оформление вложенного экрана: фон темы и пустой заголовок навигации.
    func pushedScreen() -> some View {
        self.background(ScreenBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
