import SwiftUI

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

        Screen(spacing: 16) {
            HStack(alignment: .top) {
                ScreenTitle(dayTitle(today), "Сегодня")
                HStack(spacing: 8) {
                    RoundButton(symbol: "doc.text", label: "Сессия") { model.open(.exams) }
                    RoundButton(symbol: "gearshape", label: "Настройки") { model.open(.settings) }
                }
            }
            HStack(spacing: 8) {
                Pill(text: "\(s.weekNumber(day)) неделя", bg: glass ? C.glassFill(strong: true) : C.soft, fg: glass ? C.ink : C.softInk)
                Pill(text: sub == 0 ? group : "\(group) · п/г \(sub)", bg: glass ? C.glassFill() : C.card, fg: C.ink, border: !glass) {
                    model.open(.settings)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    let d = monday.plusDays(i)
                    let on = d == day
                    Button { withAnimation(.snappy) { selected = d } } label: {
                        VStack(spacing: 2) {
                            Text(dayName(d, full: false)).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(on ? C.ground.opacity(0.75) : C.muted)
                            Text("\(d.day)").font(.system(size: 17, weight: .bold)).foregroundStyle(on ? C.ground : C.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(on ? C.ink : (glass ? C.glassFill() : C.card), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(on ? C.ink : (glass ? C.glassFill(strong: true) : C.line), lineWidth: 1))
                    }
                    .buttonStyle(Bounce())
                }
            }
            if day == today, let hero = cur ?? next {
                HeroCard(o: hero, isNow: cur != nil, now: now) { model.open(.lesson(hero, own: true)) }
            }
            if !soon.isEmpty { SoonDeadlines(list: soon, now: now) { model.tab = .deadlines } }
            HStack(alignment: .bottom) {
                Text(day == today ? "Пары на сегодня" : dayTitle(day)).font(.system(size: 17, weight: .bold)).foregroundStyle(C.ink)
                Spacer()
                if let last = lessons.map({ $0.lesson.end }).max() {
                    Text("\(pairs(lessons.count)) · до \(last)").font(.system(size: 13)).foregroundStyle(C.muted)
                }
            }
            if lessons.isEmpty {
                EmptyCard(title: "Пар нет", text: "Можно выдохнуть. Дальше — на вкладке «Пары».")
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(lessons.enumerated()), id: \.offset) { i, o in
                        Between(gap: gapBefore(lessons, i))
                        let dl = model.deadlines.filter { !$0.done && $0.subject == o.lesson.subject && !$0.due.isBefore(now) }.count
                        LessonRow(o: o, faded: o.endAt.isBefore(now), highlighted: cur == o, showGroups: false,
                                  extra: dl > 0 ? "Дедлайнов по предмету: \(dl)" : nil) {
                            model.open(.lesson(o, own: true))
                        }
                    }
                }
                .id(day)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .refreshable { model.load(force: true) }
    }
}

private struct SoonDeadlines: View {
    @Environment(\.look) private var C
    let list: [Deadline]
    let now: LocalDateTime
    let action: () -> Void

    var body: some View {
        let colored = C.style == .color
        let ink = colored ? C.ground : C.ink
        let muted = colored ? C.ground.opacity(0.65) : C.muted
        let late = !colored ? C.error : (C.dark ? Color(hex: 0xB0213F) : Color(hex: 0xFF8FA3))
        let flag = !colored ? C.accent : (C.typeTone("ПЗ").map { C.dark ? $0.strong : $0.fill } ?? C.ground)
        let shape = RoundedRectangle(cornerRadius: C.style == .classic ? 18 : 22, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill").font(.system(size: 15)).foregroundStyle(flag)
                    Text("Скоро дедлайны").font(.system(size: 14, weight: .bold)).foregroundStyle(ink)
                }
                ForEach(list) { d in
                    HStack {
                        Text(d.title).font(.system(size: 14)).foregroundStyle(ink).lineLimit(1)
                        Spacer()
                        Text(deadlineLabel(d, now: now)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(d.due.isBefore(now) ? late : muted)
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

/// Главная карточка: идущая сейчас или следующая пара.
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
                        Text(isNow ? "Идёт сейчас" : "Следующая пара").font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.label)
                    }
                    Spacer()
                    Text(isNow ? "ещё \(minutesText(now.minutes(to: o.endAt) + 1))" : untilText(o, now: now))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.fullTitle)
                        .font(.system(size: C.style == .classic ? 22 : 23, weight: tone != nil ? .heavy : .bold))
                        .foregroundStyle(colors.ink)
                        .multilineTextAlignment(.leading)
                        .padding(.trailing, tone != nil ? 40 : 0)
                    Text([typeName, l.rooms, l.teacher].filter { !$0.isBlank }.joined(separator: " · "))
                        .font(.system(size: 14)).foregroundStyle(colors.muted).multilineTextAlignment(.leading)
                    if !l.note.isBlank {
                        Text(l.note).font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.muted).lineLimit(3)
                    }
                }
                VStack(spacing: 6) {
                    ProgressBar(fraction: Double(done) / Double(total), track: colors.track, bar: colors.bar)
                    HStack {
                        Text(l.start.description)
                        Spacer()
                        Text(l.end.description)
                    }
                    .font(.system(size: 12)).foregroundStyle(colors.muted)
                }
            }
            .padding(C.style == .classic ? 18 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if let tone = tone {
                        shape.fill(LinearGradient(colors: [tone.strong.opacity(0.84), tone.strong], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .background(shape.fill(.white))
                        // Крупная полупрозрачная метка типа в углу карточки.
                        Text(l.type).font(.system(size: 110, weight: .black)).tracking(-6)
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
                        shape.fill(C.hero)
                    }
                }
                .clipShape(shape)
            }
        }
        .buttonStyle(Bounce())
    }
}

/// Пульсирующая точка «идёт сейчас».
struct LiveDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 18, height: 18).scaleEffect(pulse ? 1 : 0.4).opacity(pulse ? 0 : 1)
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 8, height: 8)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }
}
