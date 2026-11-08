import SwiftUI

// MARK: Карточка пары (LessonScreen)

struct LessonView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.look) private var C
    @Environment(\.openURL) private var openURL
    let o: Occurrence
    let own: Bool
    @State private var note = ""
    @State private var remind = false
    @State private var loaded = false

    var body: some View {
        let l = o.lesson
        let now = model.now
        let whenText: String = {
            if !o.startAt.isAfter(now) && o.endAt.isAfter(now) { return "идёт, ещё \(minutesText(now.minutes(to: o.endAt) + 1))" }
            if o.endAt.isBefore(now) { return "уже прошла" }
            return untilText(o, now: now)
        }()
        let mine = model.deadlines.filter { $0.subject == l.subject && !$0.done }

        Screen(spacing: 18, top: 12, bottom: 24) {
            BackBar()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    TypeChip(type: l.type, full: true)
                    if l.subgroup != 0 { Pill(text: "Подгруппа \(l.subgroup)", bg: C.card, fg: C.ink, border: true) }
                    if let n = pairNumber(l.start) { Pill(text: "\(n) пара", bg: C.card, fg: C.ink, border: true) }
                }
                Text(l.fullTitle).ct(30, .heavy, lh: 33).foregroundStyle(C.ink)
                Text("\(dayTitle(o.date)) · \(whenText)").ct(15).foregroundStyle(C.muted)
                if !l.note.isBlank {
                    HStack(spacing: 10) {
                        Glyph(.bell, C.softInk, 18)
                        Text(l.note).ct(14, .semibold, lh: 19).foregroundStyle(C.softInk)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(C.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                InfoTile(label: "Время", value: "\(l.start)–\(l.end)")
                InfoTile(label: "Аудитория", value: l.rooms.ifBlank("—"))
            }
            .fixedSize(horizontal: false, vertical: true)
            if let p = roomPlace(l.rooms) {
                LinkRow(glyph: .pin, title: ["Корпус \(p.corpus)", p.floor].filter { !$0.isBlank }.joined(separator: " · "),
                        sub: "Открыть на карте") {
                    let q = "БГУИР учебный корпус \(p.corpus), Минск".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://maps.apple.com/?q=\(q)") { openURL(url) }
                }
            }
            ForEach(l.teachers, id: \.self) { t in
                VStack(alignment: .leading, spacing: 14) {
                    Text("Преподаватель").ct(12, .medium).foregroundStyle(C.muted)
                    HStack(spacing: 14) {
                        TeacherPhoto(teacher: t, size: 76)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.full).ct(18, .bold, lh: 22).foregroundStyle(C.ink)
                            if !t.title.isBlank { Text(t.title).ct(13).foregroundStyle(C.muted) }
                        }
                    }
                    if !t.urlId.isBlank {
                        Button { model.open(.other(Target(kind: "teacher", id: t.urlId, title: t.full, sub: t.title))) } label: {
                            Text("Расписание и где сейчас").ct(14, .semibold).foregroundStyle(C.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(C.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(22)
            }
            if !own && !l.groups.isBlank {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Группы").ct(12, .medium).foregroundStyle(C.muted)
                    FlowLayout(spacing: 8) {
                        ForEach(l.groups.components(separatedBy: ", "), id: \.self) { g in
                            Pill(text: g, bg: C.ground, fg: C.ink) { model.open(.other(.group(g))) }
                        }
                    }
                }
                .card(22)
            }
            if own {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Дедлайны по предмету").ct(12, .medium).foregroundStyle(C.muted)
                        Spacer()
                        Button {
                            let next = model.schedule?.nextOf(l.subject, now: now, subgroup: model.store.subgroup)
                            model.newDeadline(subject: l.subject, due: next?.startAt)
                        } label: {
                            Text("+ Добавить").ct(14, .semibold).foregroundStyle(C.accent).padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                    if mine.isEmpty { Text("Пока ничего не нужно сдавать").ct(14).foregroundStyle(C.ink) }
                    ForEach(mine) { d in
                        Button { model.editing = d } label: {
                            HStack {
                                Text(d.title).ct(15).foregroundStyle(C.ink).lineLimit(1)
                                Spacer()
                                Text(deadlineLabel(d, now: now)).ct(13).foregroundStyle(d.due.isBefore(now) ? C.error : C.muted)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(22)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Заметка к паре").ct(12, .medium).foregroundStyle(C.muted)
                    Field(text: $note, placeholder: "Например: взять ноутбук")
                        .onChange(of: note) { _, v in if loaded { model.store.setNote(l.key, v) } }
                }
                .card(22)
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Напомнить за \(settings.remindMinutes) минут").ct(15, .medium).foregroundStyle(C.ink)
                        Text("Каждую неделю для этой пары").ct(12).foregroundStyle(C.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MaterialSwitch(on: $remind)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onChange(of: remind) { _, v in
                    guard loaded else { return }
                    model.store.setReminder(l.key, v)
                    if v { Task { await Notifications.requestPermission() } }
                    model.reloadLocal()
                }
                VStack(spacing: 0) {
                    HideRow(title: "Скрыть эту пару", sub: "\(dayName(o.date, full: false)) \(l.start) каждую неделю") {
                        settings.hidden.insert(l.key); hidden()
                    }
                    Divider1()
                    HideRow(title: "Скрыть предмет целиком", sub: "Все пары «\(l.subject)»") {
                        settings.hidden.insert("S:\(l.subject)"); hidden()
                    }
                }
                .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("Скрытые пары можно вернуть в настройках.").ct(12).foregroundStyle(C.muted)
            }
        }
        .onAppear {
            guard !loaded else { return }
            note = model.store.note(l.key)
            remind = model.store.reminders.contains(l.key)
            DispatchQueue.main.async { loaded = true }
        }
    }

    private func hidden() {
        model.reloadLocal()
        model.back()
        model.show("Скрыто. Вернуть можно в настройках")
    }
}

private struct HideRow: View {
    @Environment(\.look) private var C
    let title: String
    let sub: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph(.eyeOff, C.muted, 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).ct(15, .medium).foregroundStyle(C.ink)
                    Text(sub).ct(12).foregroundStyle(C.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Поиск (SearchScreen)

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    @State private var query = ""
    @State private var tab = 0
    @State private var groups: [Target]?
    @State private var teachers: [Target]?
    @State private var error: String?
    @State private var favs: [Target] = []
    @State private var recents: [Target] = []
    @State private var friends: [Friend] = []

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let source = tab == 0 ? groups : teachers
        let results = q.isEmpty ? [] : Array((source ?? []).filter { $0.title.lowercased().contains(q) || $0.sub.lowercased().contains(q) }.prefix(60))

        Screen(top: 20, bottom: 20) {
            ScreenTitle(nil, "Поиск")
            Field(text: $query, placeholder: tab == 0 ? "Номер группы" : "Фамилия преподавателя", number: tab == 0, glyph: .search)
            Segmented(labels: ["Группы", "Преподаватели"], selected: tab) { tab = $0 }
            if let e = error { Text(e).ct(14).foregroundStyle(C.error) }
            if !q.isEmpty {
                if source == nil && error == nil {
                    ProgressView().tint(C.accent).frame(maxWidth: .infinity)
                } else if results.isEmpty {
                    Text("Ничего не нашлось").ct(14).foregroundStyle(C.muted)
                } else {
                    TargetList(list: results) { model.open(.other($0)) }
                }
            } else {
                Button { model.open(.friends) } label: {
                    HStack(spacing: 12) {
                        Glyph(.people, C.heroBar, 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Друзья и общие окна").ct(16, .bold).foregroundStyle(.white)
                            Text(friends.isEmpty ? "Узнай, когда вы оба свободны" : friends.map { $0.name }.joined(separator: ", "))
                                .ct(13).foregroundStyle(C.heroMuted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph(.chevron, C.heroMuted, 18)
                    }
                    .padding(16)
                    .background(C.hero, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !favs.isEmpty {
                    SectionLabel("Избранное")
                    TargetList(list: favs) { model.open(.other($0)) }
                }
                if !recents.isEmpty {
                    SectionLabel("Недавние")
                    FlowLayout(spacing: 8) {
                        ForEach(recents, id: \.self) { t in
                            Pill(text: t.isGroup ? t.title : shortName(t.title), bg: C.card, fg: C.ink, border: true) { model.open(.other(t)) }
                        }
                    }
                }
            }
        }
        .onAppear {
            favs = model.store.favorites()
            recents = model.store.recents()
            friends = model.store.friends()
        }
        .task(id: tab) {
            do {
                if tab == 0 && groups == nil { groups = try await model.store.allGroups() }
                if tab == 1 && teachers == nil { teachers = try await model.store.allTeachers() }
                error = nil
            } catch {
                self.error = "Нет связи с iis.bsuir.by"
            }
        }
    }
}

struct TargetList: View {
    @Environment(\.look) private var C
    let list: [Target]
    let onOpen: (Target) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                if i > 0 { Divider1() }
                Button { onOpen(t) } label: {
                    HStack(spacing: 12) {
                        let p = t.title.split(separator: " ")
                        let ab = t.isGroup ? String(t.title.prefix(2)) : "\(p.count > 1 ? String(p[1].prefix(1)) : "")\(p.first.map { String($0.prefix(1)) } ?? "")"
                        Text(ab).font(.roboto(15, .bold)).foregroundStyle(t.isGroup ? C.ground : C.softInk)
                            .frame(width: 44, height: 44)
                            .background(t.isGroup ? C.ink : C.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).ct(15, .semibold).foregroundStyle(C.ink).lineLimit(1)
                            if !t.sub.isBlank { Text(t.sub).ct(13).foregroundStyle(C.muted).lineLimit(1) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph(.chevron, C.chevron, 18)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: Чужое расписание (OtherScreen)

struct OtherView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let target: Target
    @State private var schedule: Schedule?
    @State private var error: String?
    @State private var fav = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RoundButton(glyph: .back, label: "Назад") { model.back() }
                Spacer()
                RoundButton(glyph: fav ? .starFilled : .star, label: fav ? "Убрать из избранного" : "В избранное") {
                    model.store.toggleFavorite(target)
                    fav.toggle()
                }
            }
            .padding(.horizontal, 12).padding(.top, 12)
            if let e = error {
                Text(e).ct(15).foregroundStyle(C.muted).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let s = schedule {
                ScheduleFeed(s: s, subgroup: 0, deadlines: [], showGroups: !target.isGroup, withExams: false, header: {
                    VStack(alignment: .leading, spacing: 10) {
                        ScreenTitle(target.sub.isBlank ? nil : target.sub, target.isGroup ? "Группа \(target.title)" : shortName(target.title))
                        if !target.isGroup { WhereNow(s: s) }
                    }
                    .padding(.top, 8)
                }) { o in model.open(.lesson(o, own: false)) }
            } else {
                ProgressView().tint(C.accent).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task(id: target) {
            fav = model.store.isFavorite(target)
            do { schedule = try await model.store.fetchOther(target) }
            catch { self.error = "Не удалось загрузить: \(error.localizedDescription)" }
        }
    }
}

/// Где сейчас преподаватель.
private struct WhereNow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let s: Schedule

    var body: some View {
        let now = model.now
        let (cur, next) = s.currentAndNext(now: now, subgroup: 0)
        let text: String = {
            if let c = cur { return "Сейчас в \(c.lesson.rooms.ifBlank("—")) · \(c.lesson.subject) до \(c.lesson.end)" }
            if let n = next { return "Сейчас пар нет · следующая \(untilText(n, now: now)), \(n.lesson.rooms.ifBlank("—"))" }
            return "Пар в ближайшие недели нет"
        }()
        Text(text).ct(14).foregroundStyle(C.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
