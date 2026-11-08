import SwiftUI

// MARK: Друзья (FriendsScreen)

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let mine: Schedule
    @State private var friends: [Friend] = []
    @State private var schedules: [String: Schedule] = [:]
    @State private var failed: Set<String> = []
    @State private var day: LocalDate?

    var body: some View {
        let now = model.now
        let today = now.date
        let days = Array((0...7).map { today.plusDays($0) }.filter { $0.weekday != 7 }.prefix(6))
        let selected = day ?? days[0]

        Screen(spacing: 14, top: 12, bottom: 24) {
            BackBar(trailing: (glyph: .plus, label: "Добавить друга", action: { add() }))
            ScreenTitle("когда вы оба свободны", "Друзья")
            if friends.isEmpty {
                EmptyCard(title: "Добавь первого друга", text: "Нажми сюда — укажи имя и группу, и я покажу, где он сейчас и когда у вас общие окна.", glyph: .people) {
                    add()
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        let on = d == selected
                        Button { day = d } label: {
                            VStack(spacing: 0) {
                                Text(d == today ? "Сег" : dayName(d, full: false)).ct(12).foregroundStyle(on ? C.ground.opacity(0.75) : C.muted)
                                Text("\(d.day)").ct(16, .bold).foregroundStyle(on ? C.ground : C.ink)
                            }
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(on ? C.ink : C.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? C.ink : C.line, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(friends, id: \.self) { f in
                    FriendCard(f: f, s: schedules[f.group], failed: failed.contains(f.group), mine: mine, now: now, day: selected,
                               onOpen: { model.open(.other(f.target)) },
                               onRemove: {
                                   friends.removeAll { $0 == f }
                                   model.store.saveFriends(friends)
                               })
                }
            }
        }
        .onAppear { if friends.isEmpty { friends = model.store.friends() } }
        .task(id: friends.map { $0.group }) {
            for g in Set(friends.map { $0.group }) where schedules[g] == nil {
                do { schedules[g] = try await model.store.fetchOther(.group(g)) } catch { failed.insert(g) }
            }
        }
    }

    private func add() {
        model.present(AnyView(AddFriendDialog { f in
            friends.append(f)
            model.store.saveFriends(friends)
            model.dismissOverlay()
        }))
    }
}

private struct FriendCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let f: Friend
    let s: Schedule?
    let failed: Bool
    let mine: Schedule
    let now: LocalDateTime
    let day: LocalDate
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(f.name.prefix(1).uppercased()).font(.roboto(18, .bold)).foregroundStyle(C.softInk)
                    .frame(width: 44, height: 44).background(C.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(f.name).ct(16, .bold).foregroundStyle(C.ink)
                        Text(f.group + (f.subgroup != 0 ? " · п/г \(f.subgroup)" : "")).ct(13).foregroundStyle(C.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onRemove) {
                    Glyph(.trash, C.muted, 20).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить")
            }
            if failed {
                Text("Не удалось загрузить расписание группы").ct(14).foregroundStyle(C.error)
            } else if let s = s {
                if day == now.date {
                    let (cur, next) = s.currentAndNext(now: now, subgroup: f.subgroup)
                    let status: String = {
                        if let c = cur { return "Сейчас на паре: \(c.lesson.subject) \(c.lesson.type) в \(c.lesson.rooms.ifBlank("—")), до \(c.lesson.end)" }
                        if let n = next, n.date == day { return "Сейчас свободен · следующая пара в \(n.lesson.start)" }
                        return "Сегодня пары закончились"
                    }()
                    Text(status).ct(14).foregroundStyle(C.ink)
                }
                let my = mine.lessonsOn(day, subgroup: model.store.subgroup)
                let their = s.lessonsOn(day, subgroup: f.subgroup)
                let c = commonWindows(my, their)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Общие окна").ct(12, .semibold).foregroundStyle(C.muted)
                    if c.bothFree {
                        Text("Оба свободны весь день").ct(15, .semibold).foregroundStyle(C.accent)
                    } else {
                        if c.windows.isEmpty { Text("Между парами общих окон нет").ct(14).foregroundStyle(C.ink) }
                        ForEach(Array(c.windows.enumerated()), id: \.offset) { _, w in
                            Text("\(w.0)–\(w.1) · \(minutesText(w.1.minutes - w.0.minutes))").ct(15, .semibold).foregroundStyle(C.accent)
                        }
                        if let fa = c.freeAfter { Text("Оба свободны после \(fa)").ct(14).foregroundStyle(C.ink) }
                    }
                    Text("У тебя: \(span(my)) · у \(f.name): \(span(their))").ct(12).foregroundStyle(C.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(C.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(C.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func span(_ l: [Occurrence]) -> String {
        guard let first = l.first, let last = l.map({ $0.lesson.end }).max() else { return "пар нет" }
        return "\(first.lesson.start)–\(last)"
    }
}

private struct AddFriendDialog: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let onAdd: (Friend) -> Void
    @State private var name = ""
    @State private var group = ""
    @State private var sub = 0

    var body: some View {
        let ok = !name.isBlank && group.count >= 6
        MaterialDialog(title: "Добавить друга", confirm: "Добавить", confirmEnabled: ok,
                       onConfirm: { onAdd(Friend(name: name.trimmingCharacters(in: .whitespaces), group: group, subgroup: sub)) },
                       onDismiss: { model.dismissOverlay() }) {
            VStack(alignment: .leading, spacing: 12) {
                Field(text: $name, placeholder: "Имя")
                Field(text: $group, placeholder: "Номер группы", number: true)
                    .onChange(of: group) { _, v in
                        let digits = v.filter { $0.isNumber }
                        if digits != v { group = digits }
                    }
                Text("Подгруппа").ct(13).foregroundStyle(C.muted)
                Segmented(labels: ["Все", "1", "2"], selected: sub) { sub = $0 }
            }
        }
    }
}

// MARK: Предметы (SubjectsScreen)

struct SubjectsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let s: Schedule
    @State private var filter = 0
    @State private var open: String?
    private let filters = ["Все", "ЛК", "ПЗ", "ЛР"]

    private func typePlural(_ type: String) -> String {
        switch type {
        case "ЛК": return "Лекции"
        case "ПЗ": return "Практики"
        case "ЛР": return "Лабы"
        default: return C.typeStyle(type).name
        }
    }

    var body: some View {
        let all = s.remaining(now: model.now, subgroup: model.store.subgroup)
        let type = filter > 0 ? filters[filter] : nil
        let shown: [Schedule.SubjectLeft] = type == nil ? all : all.compactMap { subj in
            subj.byType.first { $0.type == type }.map { Schedule.SubjectLeft(lesson: subj.lesson, byType: [$0]) }
        }
        let total = shown.reduce(0) { $0 + $1.total }

        Screen(spacing: 12, top: 12, bottom: 32) {
            BackBar()
            ScreenTitle("осталось \(type == nil ? pairs(total) : "\(pairs(total)) · \(typePlural(type!).lowercased())") до конца семестра", "Предметы").enter(0)
            Segmented(labels: filters, selected: filter) { filter = $0 }.enter(1)
            if shown.isEmpty {
                EmptyCard(title: type == nil ? "Пар не осталось" : "\(typePlural(type!)) закончились",
                          text: "По расписанию до конца семестра больше ничего нет.", glyph: .doc).enter(2)
            }
            ForEach(Array(shown.enumerated()), id: \.element.lesson.subject) { idx, subj in
                let expanded = open == subj.lesson.subject
                Button { withAnimation(.interpolatingSpring(stiffness: 420, damping: 25)) { open = expanded ? nil : subj.lesson.subject } } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(subj.lesson.fullTitle).ct(16, .bold, lh: 20).foregroundStyle(C.ink).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Glyph(.chevron, C.chevron, 18).rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        FlowLayout(spacing: 6) {
                            ForEach(subj.byType.indices, id: \.self) { i in
                                let t = subj.byType[i]
                                let st = C.typeStyle(t.type)
                                Text("\(t.type) \(t.list.count)").ct(13, .bold).foregroundStyle(st.fg)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(st.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        if expanded {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(subj.byType.indices, id: \.self) { i in
                                    let t = subj.byType[i]
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(typePlural(t.type)) · осталось \(pairs(t.list.count))").ct(14, .semibold).foregroundStyle(C.muted)
                                        FlowLayout(spacing: 6) {
                                            ForEach(t.list, id: \.self) { o in
                                                Pill(text: "\(o.date.day) \(month(o.date)), \(dayName(o.date, full: false).lowercased()) · \(o.lesson.start)",
                                                     bg: C.soft, fg: C.softInk) { model.open(.lesson(o, own: true)) }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(Bounce())
                .enter(2 + idx)
            }
        }
    }
}

// MARK: Секретная статистика (SecretStatsScreen)

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let s: Schedule

    private func h(_ d: Double) -> String { d >= 10 ? "\(Int(d))" : fmt1(d) }

    var body: some View {
        let st = Stats.semester(s, subgroup: model.store.subgroup, now: model.now)
        Screen(spacing: 12, top: 12, bottom: 32) {
            BackBar()
            ScreenTitle("ты нашёл пасхалку", "Твой семестр")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text(h(st.hours)).ct(56, .heavy, lh: 56).foregroundStyle(.white)
                    Text("\(plural(Int(st.hours), "час", "часа", "часов")) на парах\nза семестр")
                        .ct(15, .semibold, lh: 19).foregroundStyle(C.heroMuted).padding(.bottom, 6)
                }
                ProgressBar(fraction: st.hoursDone / max(st.hours, 1), track: C.heroTrack, bar: C.heroBar)
                Text("Позади \(h(st.hoursDone)) ч, осталось \(h(st.hours - st.hoursDone)) ч · всего \(pairs(st.pairs))")
                    .ct(13).foregroundStyle(C.heroMuted)
                Text("Это \(h(st.hours / 24)) суток без перерыва.").ct(13, .semibold).foregroundStyle(C.heroLabel)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let top = st.topTeacher {
                let t = top.0, n = top.1
                HStack(spacing: 14) {
                    TeacherPhoto(teacher: t, size: 60)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Чаще всех ты видишь").ct(12).foregroundStyle(C.muted)
                        Text(t.full).ct(16, .bold, lh: 20).foregroundStyle(C.ink)
                        Text("\(pairs(n)) за семестр — почти родственник").ct(13, .semibold).foregroundStyle(C.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            HStack(spacing: 8) {
                FunTile(label: "Второй дом", value: st.topRoom?.0 ?? "—", sub: st.topRoom.map { "\(pairs($0.1)) там" } ?? "")
                FunTile(label: "Самый тяжёлый день", value: st.hardestDay.map { DAY_FULL[$0.0 - 1] } ?? "—",
                        sub: st.hardestDay.map { "≈ \(h($0.1)) ч в неделю" } ?? "")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                FunTile(label: "Пар в 8:30", value: "\(st.earlyPairs)", sub: st.earlyPairs == 0 ? "везунчик" : "держись")
                FunTile(label: "Самый длинный день", value: st.longestDay.map { "\($0.0.day) \(month($0.0))" } ?? "—",
                        sub: st.longestDay.map { "\(minutesText($0.1)) в универе" } ?? "")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                FunTile(label: "Окна за семестр", value: "\(h(st.windowHours)) ч", sub: st.windowHours < 1 ? "ни одного — расписание мечты" : "можно было выучить японский")
                FunTile(label: "Дней без пар", value: "\(st.freeDays)", sub: "кроме воскресений")
            }
            .fixedSize(horizontal: false, vertical: true)
            if let top = st.bySubject.first?.1 {
                SectionTitle(text: "Куда уходит время")
                VStack(spacing: 10) {
                    ForEach(st.bySubject.indices, id: \.self) { i in
                        let item = st.bySubject[i]
                        VStack(spacing: 4) {
                            HStack {
                                Text(item.0).ct(14).foregroundStyle(C.ink).lineLimit(1)
                                Spacer()
                                Text("\(h(item.1)) ч").ct(14, .bold).foregroundStyle(C.ink)
                            }
                            ProgressBar(fraction: item.1 / top, track: C.ground, bar: C.accent, height: 5)
                        }
                    }
                }
                .padding(14)
                .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text("Подсказка: в «Парах» спрятана ещё одна пасхалка. Попробуй поиграть с неделями.")
                .ct(12, lh: 17).foregroundStyle(C.muted)
        }
    }
}

private struct FunTile: View {
    @Environment(\.look) private var C
    let label: String
    let value: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ct(12).foregroundStyle(C.muted)
            Text(value).ct(18, .heavy).foregroundStyle(C.ink).lineLimit(1)
            if !sub.isBlank { Text(sub).ct(12).foregroundStyle(C.accent) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
