import SwiftUI

/// «Сегодня» — как TodayScreen в MainScreens.kt.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.look) private var C
    let s: Schedule
    @State private var selected: LocalDate?

    var body: some View {
        let now = model.now
        let today = now.date
        let monday = mondayOf(today)
        let day = selected ?? (today.weekday == 7 ? monday : today)
        let sub = model.store.subgroup
        let group = model.store.group
        let lessons = s.lessonsOn(day, subgroup: sub)
        let (cur, next) = s.currentAndNext(now: now, subgroup: sub)
        let soon = Array(model.deadlines.filter { !$0.done && $0.due.isBefore(now.plusDays(4)) }.prefix(3))
        let glass = C.style == .glass

        Screen(spacing: 16, top: 20, bottom: 20) {
            HStack(alignment: .top) {
                ScreenTitle(dayTitle(today), "Сегодня")
                Spacer()
                HStack(spacing: 8) {
                    RoundButton(glyph: .doc, label: "Сессия", glassy: glass) { model.open(.exams) }
                    RoundButton(glyph: .gear, label: "Настройки", glassy: glass) { model.open(.settings) }
                }
            }
            .enter(0)
            HStack(spacing: 8) {
                if glass {
                    Pill(text: "\(s.weekNumber(day)) неделя", bg: C.glassFill(strong: true), fg: C.ink)
                    Pill(text: sub == 0 ? group : "\(group) · п/г \(sub)", bg: C.glassFill(), fg: C.ink) { model.open(.settings) }
                } else {
                    Pill(text: "\(s.weekNumber(day)) неделя", bg: C.soft, fg: C.softInk)
                    Pill(text: sub == 0 ? group : "\(group) · п/г \(sub)", bg: C.card, fg: C.ink, border: true) { model.open(.settings) }
                }
            }
            .enter(1)
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    let d = monday.plusDays(i)
                    let on = d == day
                    Button { withAnimation(.easeInOut(duration: 0.25)) { selected = d } } label: {
                        VStack(spacing: 2) {
                            Text(dayName(d, full: false)).ct(12, .medium).foregroundStyle(on ? C.ground.opacity(0.75) : C.muted)
                            Text("\(d.day)").ct(17, .bold).foregroundStyle(on ? C.ground : C.ink)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(on ? C.ink : (glass ? C.glassFill() : C.card), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(on ? C.ink : (glass ? C.glassFill(strong: true) : C.line), lineWidth: 1))
                    }
                    .buttonStyle(Bounce())
                }
            }
            .enter(2)
            if day == today, let hero = cur ?? next {
                HeroCard(o: hero, isNow: cur != nil, now: now) { model.open(.lesson(hero, own: true)) }.enter(3)
            }
            if !soon.isEmpty { SoonDeadlines(list: soon, now: now) { model.tab = .deadlines }.enter(4) }
            HStack(alignment: .bottom) {
                Text(day == today ? "Пары на сегодня" : dayTitle(day)).ct(17, .bold).foregroundStyle(C.ink)
                Spacer()
                if let last = lessons.map({ $0.lesson.end }).max() {
                    Text("\(pairs(lessons.count)) · до \(last)").ct(13).foregroundStyle(C.muted)
                }
            }
            .enter(4)
            if lessons.isEmpty {
                EmptyCard(title: "Пар нет", text: "Можно выдохнуть. Дальше — на вкладке «Пары».").enter(5)
            } else {
                // Смена дня: пары выезжают заново, по очереди.
                DayLessons(lessons: lessons, now: now, current: cur)
                    .id(day)
                    .environment(\.enterClock, Date())
            }
        }
    }
}

private struct DayLessons: View {
    @EnvironmentObject private var model: AppModel
    let lessons: [Occurrence]
    let now: LocalDateTime
    let current: Occurrence?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(lessons.enumerated()), id: \.offset) { i, o in
                Between(gap: gapBefore(lessons, i)).enter(5 + i)
                let dl = model.deadlines.filter { !$0.done && $0.subject == o.lesson.subject && !$0.due.isBefore(now) }.count
                LessonRow(o: o, faded: o.endAt.isBefore(now), highlighted: current == o, showGroups: false,
                          extra: dl > 0 ? "Дедлайнов по предмету: \(dl)" : nil) {
                    model.open(.lesson(o, own: true))
                }
                .enter(5 + i)
            }
        }
    }
}

private struct SoonDeadlines: View {
    @Environment(\.look) private var C
    let list: [Deadline]
    let now: LocalDateTime
    let action: () -> Void

    var body: some View {
        // В «Цвете пар» карточка дедлайнов в обратных цветах, чтобы не потеряться среди цветных пар.
        let colored = C.style == .color
        let ink = colored ? C.ground : C.ink
        let muted = colored ? C.ground.opacity(0.65) : C.muted
        let late = !colored ? C.error : (C.dark ? Color(hex: 0xB0213F) : Color(hex: 0xFF8FA3))
        let flag = !colored ? C.accent : (C.typeTone("ПЗ").map { C.dark ? $0.strong : $0.fill } ?? C.ground)
        let shape = RoundedRectangle(cornerRadius: C.style == .classic ? 18 : 22, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Glyph(.flag, flag, 18)
                    Text("Скоро дедлайны").ct(14, .bold).foregroundStyle(ink)
                }
                ForEach(list) { d in
                    HStack {
                        Text(d.title).ct(14).foregroundStyle(ink).lineLimit(1)
                        Spacer()
                        Text(deadlineLabel(d, now: now)).ct(13, .semibold).foregroundStyle(d.due.isBefore(now) ? late : muted)
                    }
                }
            }
            .padding(C.style == .classic ? 14 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if C.style == .glass { Color.clear.glass(shape) } else { shape.fill(colored ? C.ink : C.card) }
            }
        }
        .buttonStyle(Bounce())
    }
}

/// Главная карточка: идущая сейчас или следующая пара (HeroCard).
struct HeroCard: View {
    @Environment(\.look) private var C
    let o: Occurrence
    let isNow: Bool
    let now: LocalDateTime
    let action: () -> Void

    var body: some View {
        let l = o.lesson
        let typeName = C.typeStyle(l.type).name
        let glass = C.style == .glass
        let tone = C.style == .color ? C.typeTone(l.type) : nil
        let shape = RoundedRectangle(cornerRadius: C.style == .classic ? 22 : 28, style: .continuous)
        let colors: (ink: Color, muted: Color, label: Color, live: Color, track: Color, bar: Color) = {
            if tone != nil { return (.white, .white.opacity(0.85), .white, .white, .white.opacity(0.28), .white) }
            if glass { return (C.ink, C.muted, C.accent, C.glassLive, C.ink.opacity(0.12), C.dark ? C.heroBar : C.accent) }
            return (.white, C.heroMuted, C.heroLabel, C.live, C.heroTrack, C.heroBar)
        }()
        let total = max(o.startAt.minutes(to: o.endAt), 1)
        let done = isNow ? o.startAt.minutes(to: now) : 0

        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        if isNow { LiveDot(color: colors.live) } else { Circle().fill(colors.bar).frame(width: 8, height: 8) }
                        Text(isNow ? "Идёт сейчас" : "Следующая пара").ct(13, .semibold).foregroundStyle(colors.label)
                    }
                    Spacer()
                    Text(isNow ? "ещё \(minutesText(now.minutes(to: o.endAt) + 1))" : untilText(o, now: now))
                        .ct(13, .semibold).foregroundStyle(colors.muted).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.fullTitle)
                        .ct(C.style == .classic ? 22 : 23, tone != nil ? .heavy : .bold, lh: 26)
                        .foregroundStyle(colors.ink)
                        .multilineTextAlignment(.leading)
                        .padding(.trailing, tone != nil ? 40 : 0)
                    Text([typeName, l.rooms, l.teacher].filter { !$0.isBlank }.joined(separator: " · "))
                        .ct(14).foregroundStyle(colors.muted).multilineTextAlignment(.leading)
                    if !l.note.isBlank {
                        Text(l.note).ct(14, .semibold).foregroundStyle(colors.muted).lineLimit(3)
                    }
                }
                VStack(spacing: 6) {
                    ProgressBar(fraction: Double(done) / Double(total), track: colors.track, bar: colors.bar)
                    HStack {
                        Text(l.start.description)
                        Spacer()
                        Text(l.end.description)
                    }
                    .ct(12).foregroundStyle(colors.muted)
                }
            }
            .padding(C.style == .classic ? 18 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if let tone = tone {
                        LinearGradient(colors: [mix(tone.strong, .white, 0.16), tone.strong], startPoint: .topLeading, endPoint: .bottomTrailing)
                        // Крупная полупрозрачная метка типа в углу карточки.
                        Text(l.type).font(.roboto(110, .black)).tracking(-6)
                            .foregroundStyle(.white.opacity(0.16)).lineLimit(1).fixedSize()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .offset(x: 8, y: 30)
                    } else if glass {
                        Color.clear.glass(shape, strong: true)
                        // За стеклом светится пятно цвета занятия.
                        GeometryReader { g in
                            let glow = (C.typeTone(l.type)?.strong ?? C.accent).opacity(C.dark ? 0.55 : 0.35)
                            Circle().fill(RadialGradient(colors: [glow, .clear], center: .center, startRadius: 0, endRadius: g.size.width * 0.6))
                                .frame(width: g.size.width * 1.2, height: g.size.width * 1.2)
                                .position(x: g.size.width * 0.92, y: 0)
                        }
                    } else {
                        C.hero
                    }
                }
                .clipShape(shape)
            }
        }
        .buttonStyle(Bounce())
    }
}

/// lerp цветов, как в Compose.
func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let x = UIColor(a), y = UIColor(b)
    var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0)
    x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    let f = CGFloat(t)
    return Color(.sRGB, red: Double(r1 + (r2 - r1) * f), green: Double(g1 + (g2 - g1) * f), blue: Double(b1 + (b2 - b1) * f), opacity: Double(a1 + (a2 - a1) * f))
}
