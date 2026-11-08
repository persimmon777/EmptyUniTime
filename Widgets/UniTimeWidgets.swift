import WidgetKit
import SwiftUI
import ActivityKit

@main
struct UniTimeWidgets: WidgetBundle {
    var body: some Widget {
        NextPairWidget()
        DayWidget()
        DeadlinesWidget()
        ExamsWidget()
        PairLiveActivity()
    }
}

// MARK: Данные

struct WEntry: TimelineEntry {
    let date: Date
    let schedule: Schedule?
    let subgroup: Int
    let deadlines: [Deadline]
    /// Общий контейнер недоступен — данные приложения не видны.
    let noShare: Bool
    var now: LocalDateTime { LocalDateTime(date) }
}

/// Все виджеты читают общее хранилище; если кэш устарел — сами подтягивают расписание.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WEntry {
        WEntry(date: Date(), schedule: nil, subgroup: 0, deadlines: [], noShare: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WEntry) -> Void) {
        let store = Store.shared
        completion(WEntry(date: Date(), schedule: store.load(), subgroup: store.subgroup, deadlines: store.deadlines(), noShare: !store.shared))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WEntry>) -> Void) {
        Task {
            let store = Store.shared
            if store.shared && !store.group.isBlank && store.isStale() { _ = try? await store.fetch() }
            let s = store.load()
            let sub = store.subgroup
            let dl = store.deadlines()
            // Записи на каждый момент, когда «текущая/следующая пара» меняется, — на сутки вперёд.
            var dates = [Date()]
            if let s = s {
                var t = LocalDateTime.now()
                for _ in 0..<40 {
                    t = s.nextChange(now: t, subgroup: sub)
                    let d = t.toDate().addingTimeInterval(1)
                    if d.timeIntervalSinceNow > 26 * 3600 { break }
                    dates.append(d)
                }
            }
            let midnight = LocalDate.today().plusDays(1).startOfDay.toDate().addingTimeInterval(1)
            if !dates.contains(where: { abs($0.timeIntervalSince(midnight)) < 60 }) { dates.append(midnight) }
            dates.sort()
            let entries = dates.map { WEntry(date: $0, schedule: s, subgroup: sub, deadlines: dl, noShare: !store.shared) }
            // Раз в несколько часов — заново (свежее расписание, если в приложение давно не заходили).
            let refresh = min(dates.last ?? Date(), Date().addingTimeInterval(6 * 3600))
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }
}

// MARK: Цвета

struct WC {
    let dark: Bool
    var ink: Color { dark ? Color(hex: 0xEDEFF3) : Color(hex: 0x11151C) }
    var muted: Color { dark ? Color(hex: 0xA3ABB8) : Color(hex: 0x5B6472) }
    var accent: Color { dark ? Color(hex: 0x8EA2FF) : Color(hex: 0x2F4FD8) }
    var chip: Color { dark ? Color(hex: 0x26304A) : Color(hex: 0xE3E8FB) }
    var late: Color { Color(hex: 0xD23B57) }
    var bg: Color { dark ? Color(hex: 0x12151C) : .white }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private func emptyText(_ e: WEntry) -> String {
    if e.noShare { return "Откройте UniTime" }
    return e.schedule == nil ? "Откройте приложение, чтобы загрузить расписание" : "Пар не найдено"
}

private func shortRoom(_ r: String) -> String { r.replacingOccurrences(of: " к.", with: "") }

// MARK: Следующая пара

struct NextPairWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPair", provider: Provider()) { e in
            NextPairView(e: e)
        }
        .configurationDisplayName("Следующая пара")
        .description("Что, где и во сколько. Работает и на экране блокировки.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextPairView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let e: WEntry

    var body: some View {
        let c = WC(dark: scheme == .dark)
        let now = e.now
        let list = e.schedule?.upcoming(now: now, subgroup: e.subgroup, count: 4) ?? []
        let o = list.first
        let ongoing = o.map { !$0.startAt.isAfter(now) } ?? false
        Group {
            switch family {
            case .accessoryInline:
                if let o = o {
                    Text(ongoing ? "до \(o.lesson.end) · \(o.lesson.subject) \(shortRoom(o.lesson.rooms))" : "\(o.lesson.start) · \(o.lesson.subject) \(shortRoom(o.lesson.rooms))")
                } else {
                    Text("Пар нет")
                }
            case .accessoryCircular:
                VStack(spacing: 0) {
                    if let o = o {
                        Text(ongoing ? "до" : (o.date == now.date ? "в" : dayName(o.date, full: false))).font(.system(size: 10))
                        Text(ongoing ? o.lesson.end.description : o.lesson.start.description).font(.system(size: 13, weight: .bold)).minimumScaleFactor(0.6)
                        Text(shortRoom(o.lesson.rooms).prefix(6)).font(.system(size: 9)).lineLimit(1)
                    } else {
                        Image(systemName: "graduationcap.fill")
                    }
                }
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    if let o = o {
                        Text(ongoing ? "Сейчас · до \(o.lesson.end)" : whenLabel(o, now)).font(.system(size: 12, weight: .semibold)).widgetAccentable()
                        Text([o.lesson.subject, o.lesson.type].filter { !$0.isBlank }.joined(separator: " ")).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text([shortRoom(o.lesson.rooms), o.lesson.teacher].filter { !$0.isBlank }.joined(separator: " · ")).font(.system(size: 12)).lineLimit(1)
                    } else {
                        Text("UniTime").font(.system(size: 12, weight: .semibold))
                        Text(emptyText(e)).font(.system(size: 13)).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemSmall:
                VStack(alignment: .leading, spacing: 4) {
                    if let o = o {
                        Text(ongoing ? "СЕЙЧАС" : whenLabel(o, now).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(c.accent)
                        Text(ongoing ? "до \(o.lesson.end)" : o.lesson.start.description).font(.system(size: 30, weight: .heavy)).foregroundStyle(c.ink)
                            .minimumScaleFactor(0.7)
                        Text(shortRoom(o.lesson.rooms).ifBlank(" ")).font(.system(size: 15, weight: .bold)).foregroundStyle(c.accent).lineLimit(1)
                        Spacer(minLength: 0)
                        Text([o.lesson.subject, o.lesson.type].filter { !$0.isBlank }.joined(separator: " ")).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.ink).lineLimit(2)
                        if !ongoing && o.date == now.date {
                            Text(o.startAt.toDate(), style: .relative).font(.system(size: 12)).foregroundStyle(c.muted).lineLimit(1)
                        }
                    } else {
                        Image(systemName: "graduationcap.fill").foregroundStyle(c.accent)
                        Spacer()
                        Text(emptyText(e)).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.muted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            default:
                MediumNext(e: e, c: c, list: list)
            }
        }
        .containerBackground(for: .widget) { c.bg }
    }

    private func whenLabel(_ o: Occurrence, _ now: LocalDateTime) -> String {
        if o.date == now.date { return "Сегодня в \(o.lesson.start)" }
        if o.date == now.date.plusDays(1) { return "Завтра в \(o.lesson.start)" }
        return "\(dayName(o.date, full: false)), \(o.date.day) в \(o.lesson.start)"
    }
}

private struct MediumNext: View {
    let e: WEntry
    let c: WC
    let list: [Occurrence]

    var body: some View {
        let now = e.now
        let today = now.date
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(dayName(today, full: false)), \(today.day)" + (e.schedule.map { " · \($0.weekNumber(today)) неделя" } ?? ""))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(c.muted)
                Spacer()
                let left = e.schedule?.lessonsOn(today, subgroup: e.subgroup).filter { $0.endAt.isAfter(now) }.count ?? 0
                if left > 0 { Text("сегодня ещё \(left)").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.accent) }
            }
            if let o = list.first {
                let ongoing = !o.startAt.isAfter(now)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(o.lesson.start.description).font(.system(size: 28, weight: .heavy)).foregroundStyle(c.ink)
                    Text(ongoing ? "идёт до \(o.lesson.end)" : o.date == today ? "сегодня" : whenText(o, now: now))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(c.muted)
                }
                Text(o.lesson.fullTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(c.ink).lineLimit(1)
                Text([o.lesson.type, o.lesson.rooms, o.lesson.teacher].filter { !$0.isBlank }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(c.muted).lineLimit(1)
                Spacer(minLength: 0)
                if let after = list.dropFirst().first, after.date == o.date {
                    Text("Затем \(after.lesson.start) · \(after.lesson.subject) \(after.lesson.type)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(c.ink).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(c.chip, in: Capsule())
                }
            } else {
                Spacer()
                Text(emptyText(e)).font(.system(size: 15, weight: .semibold)).foregroundStyle(c.muted)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: Пары на день

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Day", provider: Provider()) { e in DayView(e: e) }
            .configurationDisplayName("Пары на день")
            .description("Сегодня, пока есть пары; вечером — ближайший учебный день.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DayView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let e: WEntry

    var body: some View {
        let c = WC(dark: scheme == .dark)
        let now = e.now
        let today = now.date
        // Сегодня, пока есть пары; вечером — ближайший день с парами.
        let found: (LocalDate, [Occurrence]) = (0...7).lazy.map { i -> (LocalDate, [Occurrence]) in
            let d = today.plusDays(i)
            return (d, (e.schedule?.lessonsOn(d, subgroup: e.subgroup) ?? []).filter { d != today || $0.endAt.isAfter(now) })
        }.first { !$0.1.isEmpty } ?? (today, [])
        let (date, list) = found
        let label = date == today ? "Сегодня" : date == today.plusDays(1) ? "Завтра" : dayName(date)
        let max = family == .systemLarge ? 8 : 4
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(label) · \(date.day) \(month(date))" + (e.schedule.map { " · \($0.weekNumber(date)) нед." } ?? ""))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(c.ink)
                Spacer()
                if !list.isEmpty { Text(pairs(list.count)).font(.system(size: 12, weight: .semibold)).foregroundStyle(c.accent) }
            }
            if list.isEmpty {
                Spacer()
                Text(e.schedule == nil ? emptyText(e) : "На неделю вперёд пар нет").font(.system(size: 14)).foregroundStyle(c.muted)
                Spacer()
            } else {
                ForEach(Array(list.prefix(max).enumerated()), id: \.offset) { _, o in
                    let ongoing = !o.startAt.isAfter(now) && o.endAt.isAfter(now)
                    HStack(spacing: 8) {
                        Text(o.lesson.start.description).font(.system(size: 13, weight: .bold)).foregroundStyle(ongoing ? c.accent : c.ink)
                            .frame(width: 44, alignment: .leading)
                        Text("\(o.lesson.subject) \(o.lesson.type)").font(.system(size: 13, weight: ongoing ? .bold : .medium))
                            .foregroundStyle(ongoing ? c.accent : c.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(shortRoom(o.lesson.rooms)).font(.system(size: 12)).foregroundStyle(c.muted).lineLimit(1)
                    }
                }
                if list.count > max { Text("и ещё \(list.count - max)").font(.system(size: 12)).foregroundStyle(c.muted) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { c.bg }
    }
}

// MARK: Дедлайны

struct DeadlinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Deadlines", provider: Provider()) { e in DeadlinesWView(e: e) }
            .configurationDisplayName("Дедлайны")
            .description("Ближайшие лабы, рефераты и зачёты.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DeadlinesWView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let e: WEntry

    var body: some View {
        let c = WC(dark: scheme == .dark)
        let now = e.now
        let open = e.deadlines.filter { !$0.done }.sorted { $0.due < $1.due }
        let max = family == .systemSmall ? 3 : 4
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flag.fill").foregroundStyle(c.accent)
                Text("Дедлайны").font(.system(size: 13, weight: .bold)).foregroundStyle(c.ink)
                Spacer()
                if !open.isEmpty { Text("\(open.count)").font(.system(size: 13, weight: .bold)).foregroundStyle(c.accent) }
            }
            if open.isEmpty {
                Spacer()
                Text(e.noShare ? "Откройте UniTime" : "Всё сдано 🎉").font(.system(size: 14, weight: .semibold)).foregroundStyle(c.muted)
                Spacer()
            } else {
                ForEach(open.prefix(max)) { d in
                    let days = now.date.days(to: d.due.date)
                    let label: String = {
                        if d.due.isBefore(now) { return "просрочен" }
                        if days == 0 { return "сегодня \(d.due.time)" }
                        if days == 1 { return "завтра" }
                        if days < 7 { return dayName(d.due.date, full: false) }
                        return "\(d.due.date.day) \(month(d.due.date).prefix(3))"
                    }()
                    if family == .systemSmall {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(d.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.ink).lineLimit(1)
                            Text(label).font(.system(size: 11)).foregroundStyle(d.due.isBefore(now) ? c.late : days <= 1 ? c.accent : c.muted)
                        }
                    } else {
                        HStack {
                            Text([d.subject, d.title].filter { !$0.isBlank }.joined(separator: " · ")).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(c.ink).lineLimit(1)
                            Spacer()
                            Text(label).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(d.due.isBefore(now) ? c.late : days <= 1 ? c.accent : c.muted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { c.bg }
    }
}

// MARK: Сессия

struct ExamsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Exams", provider: Provider()) { e in ExamsWView(e: e) }
            .configurationDisplayName("До сессии")
            .description("Сколько дней осталось и ближайший экзамен.")
            .supportedFamilies([.systemSmall])
    }
}

struct ExamsWView: View {
    @Environment(\.colorScheme) private var scheme
    let e: WEntry

    var body: some View {
        let c = WC(dark: scheme == .dark)
        let now = e.now
        let today = now.date
        let s = e.schedule
        let next = s?.exams.first { $0.endAt.isAfter(now) }
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "graduationcap.fill").foregroundStyle(c.accent)
            Spacer()
            if let start = s?.examsStart, today < start {
                let n = today.days(to: start)
                Text("\(n)").font(.system(size: 44, weight: .heavy)).foregroundStyle(c.ink)
                Text("\(plural(n, "день", "дня", "дней")) до сессии").font(.system(size: 13, weight: .semibold)).foregroundStyle(c.muted)
                Text("с \(start.day) \(month(start))").font(.system(size: 12)).foregroundStyle(c.muted)
            } else if let x = next {
                let n = today.days(to: x.date)
                Text(n == 0 ? "сегодня" : "\(n)").font(.system(size: n == 0 ? 28 : 44, weight: .heavy)).foregroundStyle(c.ink)
                Text(n == 0 ? "экзамен в \(x.lesson.start)" : "\(plural(n, "день", "дня", "дней")) до экзамена").font(.system(size: 13, weight: .semibold)).foregroundStyle(c.muted)
                Text(x.lesson.subject).font(.system(size: 12, weight: .semibold)).foregroundStyle(c.accent).lineLimit(1)
            } else {
                Text("—").font(.system(size: 44, weight: .heavy)).foregroundStyle(c.ink)
                Text(s == nil ? emptyText(e) : "сессия: даты пока нет").font(.system(size: 13)).foregroundStyle(c.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { c.bg }
    }
}

// MARK: Live Activity

struct PairLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PairActivityAttributes.self) { ctx in
            LockScreenPair(state: ctx.state, stale: ctx.isStale)
                .activityBackgroundTint(Color(hex: 0x141A26))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.room.isBlank ? "—" : shortRoom(s.room), systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x8EA2FF))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if s.isNow {
                            ProgressView(timerInterval: s.start...max(s.end, s.start), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(Color(hex: 0x8EA2FF))
                        }
                        Text(s.next.isBlank ? s.detail : s.next).font(.system(size: 12)).foregroundStyle(Color(hex: 0xC9CED8)).lineLimit(1)
                    }
                }
            } compactLeading: {
                Text(s.short).font(.system(size: 13, weight: .bold)).lineLimit(1).foregroundStyle(Color(hex: 0x8EA2FF))
            } compactTrailing: {
                Countdown(state: s).font(.system(size: 13, weight: .semibold)).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: s.isNow ? "graduationcap.fill" : "clock").foregroundStyle(Color(hex: 0x8EA2FF))
            }
            .keylineTint(Color(hex: 0x8EA2FF))
        }
    }
}

/// Обратный отсчёт: до конца пары, если идёт, или до начала.
private struct Countdown: View {
    let state: PairActivityAttributes.ContentState
    var body: some View {
        let target = state.isNow ? state.end : state.start
        if target > Date() {
            Text(timerInterval: Date()...target, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            Text(state.isNow ? "конец" : "начало")
        }
    }
}

private struct LockScreenPair: View {
    let state: PairActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(state.isNow ? Color(hex: 0x7CF0B0) : Color(hex: 0x8EA2FF)).frame(width: 8, height: 8)
                Text(state.isNow ? "Идёт сейчас" : "Следующая пара").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xB9C4FF))
                Spacer()
                if stale {
                    Text("откройте UniTime").font(.system(size: 12)).foregroundStyle(Color(hex: 0xC9CED8))
                } else {
                    HStack(spacing: 4) {
                        Text(state.isNow ? "ещё" : "через")
                        Countdown(state: state).frame(maxWidth: 70)
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xC9CED8))
                }
            }
            Text(state.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(2)
            Text(state.detail).font(.system(size: 13)).foregroundStyle(Color(hex: 0xC9CED8)).lineLimit(1)
            if state.isNow {
                ProgressView(timerInterval: state.start...max(state.end, state.start), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Color(hex: 0x8EA2FF))
            } else {
                let t = DateFormatter.localizedString(from: state.start, dateStyle: .none, timeStyle: .short)
                Text("Начало в \(t)").font(.system(size: 12)).foregroundStyle(Color(hex: 0xC9CED8))
            }
            if !state.next.isBlank {
                Text(state.next).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
        }
        .padding(16)
    }
}
