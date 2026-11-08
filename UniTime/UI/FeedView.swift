import SwiftUI

/// Неделя ленты: заголовок и дни.
struct FeedWeek: Identifiable {
    let monday: LocalDate
    let n: Int
    var days: [FeedDay]
    var id: Int { monday.epochDay }
}

struct FeedDay: Identifiable {
    let date: LocalDate
    let list: [Occurrence]
    var id: Int { date.epochDay }
}

func buildFeed(_ s: Schedule, subgroup: Int, today: LocalDate, withExams: Bool) -> [FeedWeek] {
    var out = [FeedWeek]()
    var monday = mondayOf(today)
    let candidates = [s.termEnd, withExams ? s.examsEnd : nil].compactMap { $0 }
    let last = candidates.max().flatMap { $0 > today ? $0 : nil } ?? today.plusWeeks(4)
    let examDays = withExams ? Set(s.exams.map { $0.date }) : []
    while monday <= last {
        var week = FeedWeek(monday: monday, n: s.weekNumber(monday), days: [])
        for i in 0..<7 {
            let d = monday.plusDays(i)
            if d < today || d > last { continue }
            let list = (s.lessonsOn(d, subgroup: subgroup) + (withExams ? s.exams.filter { $0.date == d } : []))
                .sorted { $0.startAt < $1.startAt }
            if !list.isEmpty || (d.weekday != 7 && !examDays.contains(d)) {
                week.days.append(FeedDay(date: d, list: list))
            }
        }
        out.append(week)
        monday = monday.plusWeeks(1)
    }
    return out
}

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    let s: Schedule

    var body: some View {
        ScheduleFeed(s: s, subgroup: model.store.subgroup, deadlines: model.deadlines, showGroups: false, withExams: true,
                     onSecret: { model.unlockNeon() }) { o in model.open(.lesson(o, own: true)) }
    }
}

/// Лента до конца семестра с переключателем недель 1–4; используется и для чужих расписаний.
struct ScheduleFeed<Header: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let s: Schedule
    let subgroup: Int
    let deadlines: [Deadline]
    let showGroups: Bool
    let withExams: Bool
    var onSecret: (() -> Void)? = nil
    let header: Header
    let onLesson: (Occurrence) -> Void

    @State private var visible = Set<Int>()
    @State private var picked: Int?
    @State private var taps = [(Int, Date)]()
    private static var secret: [Int] { [1, 2, 3, 4, 4, 3, 2, 1] }

    init(s: Schedule, subgroup: Int, deadlines: [Deadline], showGroups: Bool, withExams: Bool,
         onSecret: (() -> Void)? = nil, @ViewBuilder header: () -> Header, onLesson: @escaping (Occurrence) -> Void) {
        self.s = s
        self.subgroup = subgroup
        self.deadlines = deadlines
        self.showGroups = showGroups
        self.withExams = withExams
        self.onSecret = onSecret
        self.header = header()
        self.onLesson = onLesson
    }

    var body: some View {
        let now = model.now
        let today = now.date
        let feed = buildFeed(s, subgroup: subgroup, today: today, withExams: withExams)
        let firstVisible = visible.min()
        let visibleWeek = firstVisible.map { s.weekNumber(LocalDate(epochDay: $0)) } ?? s.weekNumber(today)
        let firstDay = feed.first?.days.first?.id

        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Segmented(labels: (1...4).map { "\($0) нед." }, selected: (picked ?? visibleWeek) - 1) { i in
                    tapWeek(i + 1)
                    if let target = feed.first(where: { $0.n == i + 1 }) {
                        picked = i + 1
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("w\(target.id)", anchor: .top) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { picked = nil }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)

                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                            header.id("top")
                            if feed.allSatisfy({ $0.days.allSatisfy { $0.list.isEmpty } }) {
                                EmptyCard(title: "Пар не найдено", text: "Похоже, каникулы или расписание ещё не опубликовали.")
                            }
                            ForEach(feed) { w in
                                Section {
                                    ForEach(w.days) { d in
                                        Group {
                                            if d.list.isEmpty {
                                                Text("\(dayName(d.date, full: false)), \(d.date.day) \(month(d.date)) · пар нет")
                                                    .font(.system(size: 13)).foregroundStyle(C.muted).padding(.horizontal, 4).padding(.vertical, 2)
                                            } else {
                                                DayBlock(date: d.date, list: d.list, now: now, deadlines: deadlines, showGroups: showGroups, onLesson: onLesson)
                                            }
                                        }
                                        .id("d\(d.id)")
                                        .onAppear { visible.insert(d.id) }
                                        .onDisappear { visible.remove(d.id) }
                                    }
                                } header: {
                                    WeekHeader(w: w).id("w\(w.id)")
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 88)
                    }
                    let away = firstDay.map { !visible.contains($0) } ?? false
                    if away && !visible.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo("top", anchor: .top) }
                        } label: {
                            Image(systemName: "arrow.up").font(.system(size: 20, weight: .bold)).foregroundStyle(C.onAccent)
                                .frame(width: 52, height: 52).background(C.accent, in: Circle())
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                        }
                        .padding(20)
                        .accessibilityLabel("К сегодня")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }

    /// Пасхалка: недели 1-2-3-4-4-3-2-1 подряд, не дольше 8 секунд.
    private func tapWeek(_ n: Int) {
        guard let onSecret = onSecret else { return }
        let t = Date()
        taps.append((n, t))
        if taps.count > Self.secret.count { taps.removeFirst(taps.count - Self.secret.count) }
        if taps.map({ $0.0 }) == Self.secret, let first = taps.first, t.timeIntervalSince(first.1) < 8 {
            taps.removeAll()
            onSecret()
        }
    }
}

private struct WeekHeader: View {
    @Environment(\.look) private var C
    let w: FeedWeek

    var body: some View {
        let end = w.monday.plusDays(5)
        Text("\(w.n) неделя · \(w.monday.day) \(month(w.monday)) – \(end.day) \(month(end))")
            .font(.system(size: 13, weight: .bold)).foregroundStyle(C.softInk)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.vertical, 8)
            .background(C.style == .glass ? Color.clear : C.ground)
    }
}

private struct DayBlock: View {
    @Environment(\.look) private var C
    let date: LocalDate
    let list: [Occurrence]
    let now: LocalDateTime
    let deadlines: [Deadline]
    let showGroups: Bool
    let onLesson: (Occurrence) -> Void

    var body: some View {
        let isToday = date == now.date
        let due = deadlines.filter { !$0.done && $0.due.date == date }
        let colored = C.style == .color
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                // Сегодняшний день выделен цветом.
                Text("\(dayName(date)), \(date.day) \(month(date))")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(isToday ? C.accent : C.ink).lineLimit(1)
                Spacer()
                Text("\(pairs(list.count)) · \(list[0].lesson.start)–\(list.map { $0.lesson.end }.max()!)")
                    .font(.system(size: 12)).foregroundStyle(C.muted).lineLimit(1)
            }
            .padding(.top, 4)
            ForEach(due) { d in
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill").font(.system(size: 13)).foregroundStyle(C.softInk)
                    Text("\(d.title) · до \(d.due.time)").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.softInk).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(C.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            // В «Цвете пар» каждая пара — своя цветная плашка, без общей карточки.
            VStack(spacing: colored ? 4 : 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, o in
                    if let gap = gapBefore(list, i) {
                        if gap <= 0 { if !colored { Divider1() } } else { Between(gap: gap).padding(.vertical, 2) }
                    }
                    CompactRow(o: o, showGroups: showGroups, faded: o.endAt.isBefore(now)) { onLesson(o) }
                }
            }
            .background {
                if !colored {
                    if C.style == .glass { Color.clear.glass(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
                    else { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(C.card) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct CompactRow: View {
    @Environment(\.look) private var C
    let o: Occurrence
    let showGroups: Bool
    let faded: Bool
    let action: () -> Void

    var body: some View {
        let l = o.lesson
        let tone = C.style == .color ? C.typeTone(l.type) : nil
        let ink = tone?.ink ?? C.ink
        let muted = tone.map { $0.ink.opacity(0.7) } ?? C.muted
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.start.description).font(.system(size: 14, weight: .bold)).foregroundStyle(faded && tone == nil ? muted : ink)
                    Text(l.end.description).font(.system(size: 12)).foregroundStyle(muted)
                }
                .frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(C.title(l)).font(.system(size: 14, weight: .medium)).foregroundStyle(faded && tone == nil ? muted : ink).lineLimit(1)
                    let sub = [C.pairNumbers ? pairNumber(l.start).map { "\($0) пара" } : nil,
                               showGroups && !l.groups.isBlank ? l.groups : nil,
                               l.subgroup != 0 ? "п/г \(l.subgroup)" : nil].compactMap { $0 }.joined(separator: " · ")
                    if !sub.isBlank { Text(sub).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1) }
                    if !l.note.isBlank {
                        Text(l.note).font(.system(size: 12, weight: .semibold)).foregroundStyle(tone?.ink ?? C.accent).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(l.rooms.replacingOccurrences(of: " к.", with: "").ifBlank("—")).font(.system(size: 12)).foregroundStyle(muted)
                if let tone = tone, !l.type.isBlank {
                    Text(l.type).font(.system(size: 12, weight: .bold)).foregroundStyle(tone.fill)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tone.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    TypeChip(type: l.type)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(minHeight: 48)
            .background { if let tone = tone { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tone.fill) } }
            .opacity(tone != nil && faded ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ScheduleFeed where Header == EmptyView {
    init(s: Schedule, subgroup: Int, deadlines: [Deadline], showGroups: Bool, withExams: Bool,
         onSecret: (() -> Void)? = nil, onLesson: @escaping (Occurrence) -> Void) {
        self.init(s: s, subgroup: subgroup, deadlines: deadlines, showGroups: showGroups, withExams: withExams,
                  onSecret: onSecret, header: { EmptyView() }, onLesson: onLesson)
    }
}

// MARK: Сессия

struct ExamsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let s: Schedule

    var body: some View {
        let now = model.now
        let today = now.date
        Screen(spacing: 16) {
            ScreenTitle(s.termStart.map { "Семестр \($0.year)" }, "Сессия")
            if let start = s.examsStart {
                let days = today.days(to: start)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(days > 0 ? "\(days)" : "0").font(.system(size: 64, weight: .heavy)).foregroundStyle(.white)
                        Text(days > 0 ? "\(plural(days, "день", "дня", "дней")) до сессии" : "сессия идёт")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(C.heroMuted)
                    }
                    if let ts = s.termStart, let te = s.termEnd {
                        let frac = Double(ts.days(to: today)) / Double(max(ts.days(to: te), 1))
                        VStack(spacing: 6) {
                            ProgressBar(fraction: frac, track: C.heroTrack, bar: C.heroBar)
                            HStack {
                                Text("\(ts.day) \(month(ts).prefix(3))")
                                Spacer()
                                Text("пройдено \(Int(min(max(frac, 0), 1) * 100))%")
                                Spacer()
                                Text("\(te.day) \(month(te).prefix(3))")
                            }
                            .font(.system(size: 12)).foregroundStyle(C.heroMuted)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(C.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            HStack(spacing: 8) {
                let range: String = {
                    guard let es = s.examsStart, let ee = s.examsEnd else { return "—" }
                    return "\(es.day) \(month(es).prefix(3)) – \(ee.day) \(month(ee).prefix(3))"
                }()
                InfoTile(label: "Сессия", value: range)
                InfoTile(label: "Последняя пара", value: s.termEnd.map { "\($0.day) \(month($0))" } ?? "—")
            }
            if s.exams.isEmpty {
                EmptyCard(title: "Экзаменов пока нет", text: "Как только деканат опубликует расписание сессии, оно появится здесь.")
            } else {
                ForEach(Array(s.exams.enumerated()), id: \.offset) { _, o in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dayTitle(o.date)).font(.system(size: 15, weight: .bold)).foregroundStyle(C.ink)
                        LessonRow(o: o, faded: o.endAt.isBefore(now), highlighted: false, showGroups: false) {
                            model.open(.lesson(o, own: true))
                        }
                    }
                }
            }
        }
    }
}
