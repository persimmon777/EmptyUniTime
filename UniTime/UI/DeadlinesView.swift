import SwiftUI

/// Дедлайны (DeadlinesScreen).
struct DeadlinesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    @State private var showDone = false

    var body: some View {
        let now = model.now
        let today = now.date
        let open = model.deadlines.filter { !$0.done }
        let groups: [(String, [Deadline])] = [
            ("Просрочено", open.filter { $0.due.isBefore(now) }),
            ("Сегодня", open.filter { !$0.due.isBefore(now) && $0.due.date == today }),
            ("На неделе", open.filter { $0.due.date > today && today.days(to: $0.due.date) < 7 }),
            ("Позже", open.filter { today.days(to: $0.due.date) >= 7 }),
        ].filter { !$0.1.isEmpty }
        let done = model.deadlines.filter { $0.done }.sorted { $0.due > $1.due }

        Screen(top: 20, bottom: 20) {
            HStack(alignment: .top) {
                ScreenTitle(open.isEmpty ? "всё сдано" : "осталось \(open.count)", "Дедлайны")
                Spacer()
                RoundButton(glyph: .plus, label: "Новый дедлайн") { model.newDeadline() }
            }
            .enter(0)
            if open.isEmpty {
                EmptyCard(title: "Добавь первый дедлайн", text: "Нажми сюда — лаба, реферат или зачёт. Напомню за сутки и за 2 часа.", glyph: .flag) {
                    model.newDeadline()
                }
                .enter(1)
            }
            ForEach(groups.indices, id: \.self) { g in
                SectionLabel(groups[g].0, color: groups[g].0 == "Просрочено" ? C.error : nil).enter(1 + g * 2)
                DeadlineList(list: groups[g].1, now: now).enter(2 + g * 2)
            }
            if !done.isEmpty {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showDone.toggle() } } label: {
                    Text(showDone ? "Скрыть выполненные" : "Выполненные · \(done.count)").ct(14, .semibold).foregroundStyle(C.accent)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                if showDone { DeadlineList(list: done, now: now) }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.deadlines)
    }
}

private struct DeadlineList: View {
    @Environment(\.look) private var C
    let list: [Deadline]
    let now: LocalDateTime

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Divider1() }
                DeadlineRow(d: d, now: now)
            }
        }
        .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DeadlineRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let d: Deadline
    let now: LocalDateTime
    /// Сначала галочка дорисовывается и задача зачёркивается, потом она уезжает в «Выполненные».
    @State private var flipping = false
    @State private var pop: CGFloat = 1

    var body: some View {
        let done = d.done != flipping
        HStack(spacing: 12) {
            Button {
                guard !flipping else { return }
                withAnimation(.easeInOut(duration: 0.2)) { flipping = true }
                if !d.done {
                    pop = 0.7
                    withAnimation(.interpolatingSpring(stiffness: 500, damping: 18)) { pop = 1 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    var x = d
                    x.done.toggle()
                    model.store.saveDeadline(x)
                    flipping = false
                    model.reloadLocal()
                }
            } label: {
                ZStack {
                    Circle().fill(done ? C.accent : C.card)
                    Circle().strokeBorder(done ? C.accent : C.line, lineWidth: 2)
                    if done { Glyph(.check, C.onAccent, 16).transition(.scale.combined(with: .opacity)) }
                }
                .frame(width: 24, height: 24)
                .scaleEffect(pop)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.done ? "Вернуть" : "Готово")
            Button { model.editing = d } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).ct(15, .semibold).foregroundStyle(done ? C.muted : C.ink)
                        .strikethrough(done).lineLimit(2).multilineTextAlignment(.leading)
                    Text([d.subject, deadlineLabel(d, now: now)].filter { !$0.isBlank }.joined(separator: " · "))
                        .ct(13).foregroundStyle(!done && d.due.isBefore(now) ? C.error : C.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// Редактор дедлайна — диалог как AlertDialog в оригинале.
struct DeadlineEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let draft: Deadline
    @State private var title = ""
    @State private var subject = ""
    @State private var due = LocalDateTime.now()
    @State private var titleError = false
    @State private var pickDate = false
    @State private var pickerDate = Date()

    var body: some View {
        let now = LocalDateTime.now()
        let existing = model.deadlines.contains { $0.id == draft.id }
        let subjects = model.schedule?.subjects() ?? []
        let nextPair = subject.isBlank ? nil : model.schedule?.nextOf(subject, now: now, subgroup: model.store.subgroup)
        ZStack {
            MaterialDialog(title: existing ? "Дедлайн" : "Новый дедлайн", confirm: "Сохранить", onConfirm: save, onDismiss: { model.editing = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    Field(text: $title, placeholder: "Что сдать? Например: лаба №3")
                        .onChange(of: title) { _, _ in titleError = false }
                    if titleError {
                        Text("Введи название дедлайна — без него не сохранить").ct(13, .semibold).foregroundStyle(C.error)
                    }
                    Text("Предмет").ct(13).foregroundStyle(C.muted)
                    FlowLayout(spacing: 6) {
                        Choice("Без предмета", subject.isBlank) { subject = "" }
                        ForEach(subjects.map { $0.short }, id: \.self) { s in Choice(s, subject == s) { subject = s } }
                    }
                    Text("Срок").ct(13).foregroundStyle(C.muted)
                    FlowLayout(spacing: 6) {
                        if let np = nextPair {
                            Choice("К след. паре · \(dayName(np.date, full: false)) \(np.lesson.start)", due == np.startAt) { due = np.startAt }
                        }
                        let tomorrow = now.date.plusDays(1).at(LocalTime(23, 59))
                        Choice("Завтра", due == tomorrow) { due = tomorrow }
                        let week = now.date.plusWeeks(1).at(LocalTime(23, 59))
                        Choice("Через неделю", due == week) { due = week }
                        Choice("Выбрать дату…", false) { pickerDate = due.toDate(); pickDate = true }
                    }
                    Text("Время").ct(13).foregroundStyle(C.muted)
                    FlowLayout(spacing: 6) {
                        ForEach([LocalTime(8, 30), LocalTime(12, 0), LocalTime(18, 0), LocalTime(23, 59)], id: \.self) { t in
                            Choice(t.description, due.time == t) { due = due.date.at(t) }
                        }
                    }
                    Text("Срок: \(dayTitle(due.date)), \(due.time)").ct(15, .semibold).foregroundStyle(C.ink)
                    if existing {
                        Button { model.deleteDeadline(draft) } label: {
                            Text("Удалить дедлайн").ct(14, .semibold).foregroundStyle(C.error).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if pickDate {
                MaterialDialog(title: "Выбери дату", confirm: "Готово", onConfirm: {
                    due = LocalDateTime(date: LocalDateTime(pickerDate).date, time: due.time)
                    pickDate = false
                }, onDismiss: { pickDate = false }) {
                    DatePicker("", selection: $pickerDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .tint(C.accent)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                }
            }
        }
        .onAppear {
            title = draft.title
            subject = draft.subject
            due = draft.due
        }
    }

    private func save() {
        if title.isBlank { titleError = true; return }
        var d = draft
        d.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        d.subject = subject
        d.due = due
        model.saveDeadline(d)
        Task { await Notifications.requestPermission() }
    }
}
