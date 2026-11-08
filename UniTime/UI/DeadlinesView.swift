import SwiftUI

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

        Screen {
            HStack(alignment: .top) {
                ScreenTitle(open.isEmpty ? "всё сдано" : "осталось \(open.count)", "Дедлайны")
                RoundButton(symbol: "plus", label: "Новый дедлайн") { model.newDeadline() }
            }
            if open.isEmpty {
                EmptyCard(title: "Добавь первый дедлайн", text: "Нажми сюда — лаба, реферат или зачёт. Напомню за сутки и за 2 часа.", symbol: "flag") {
                    model.newDeadline()
                }
            }
            ForEach(groups.indices, id: \.self) { i in
                SectionLabel(groups[i].0, color: groups[i].0 == "Просрочено" ? C.error : nil)
                DeadlineList(list: groups[i].1, now: now)
            }
            if !done.isEmpty {
                Button(showDone ? "Скрыть выполненные" : "Выполненные · \(done.count)") { withAnimation { showDone.toggle() } }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(C.accent).padding(.vertical, 8)
                if showDone { DeadlineList(list: done, now: now) }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.deadlines)
    }
}

private struct DeadlineList: View {
    @EnvironmentObject private var model: AppModel
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
        .card(18, padding: 0)
    }
}

private struct DeadlineRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let d: Deadline
    let now: LocalDateTime
    /// Сначала галочка дорисовывается и задача зачёркивается, потом она уезжает в «Выполненные».
    @State private var flipping = false

    var body: some View {
        let done = d.done != flipping
        HStack(spacing: 12) {
            Button {
                guard !flipping else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { flipping = true }
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
                    if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(C.onAccent).transition(.scale) }
                }
                .frame(width: 24, height: 24)
                .scaleEffect(flipping ? 1.1 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.done ? "Вернуть" : "Готово")
            Button { model.editing = d } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(done ? C.muted : C.ink)
                        .strikethrough(done).lineLimit(2).multilineTextAlignment(.leading)
                    Text([d.subject, deadlineLabel(d, now: now)].filter { !$0.isBlank }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(!done && d.due.isBefore(now) ? C.error : C.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .padding(.trailing, 8)
    }
}

/// Редактор дедлайна.
struct DeadlineEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    @Environment(\.dismiss) private var dismiss
    let draft: Deadline
    @State private var title = ""
    @State private var subject = ""
    @State private var due = LocalDateTime.now()
    @State private var titleError = false
    @State private var pickDate = false

    var body: some View {
        let now = LocalDateTime.now()
        let existing = model.deadlines.contains { $0.id == draft.id }
        let subjects = model.schedule?.subjects() ?? []
        let nextPair = subject.isBlank ? nil : model.schedule?.nextOf(subject, now: now, subgroup: model.store.subgroup)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Field(text: $title, placeholder: "Что сдать? Например: лаба №3")
                        .onChange(of: title) { _, _ in titleError = false }
                    if titleError {
                        Text("Введи название дедлайна — без него не сохранить").font(.system(size: 13, weight: .semibold)).foregroundStyle(C.error)
                    }
                    Text("Предмет").font(.system(size: 13)).foregroundStyle(C.muted)
                    FlowLayout(spacing: 6) {
                        Choice("Без предмета", subject.isBlank) { subject = "" }
                        ForEach(subjects.map { $0.short }, id: \.self) { s in Choice(s, subject == s) { subject = s } }
                    }
                    Text("Срок").font(.system(size: 13)).foregroundStyle(C.muted)
                    FlowLayout(spacing: 6) {
                        if let np = nextPair {
                            Choice("К след. паре · \(dayName(np.date, full: false)) \(np.lesson.start)", due == np.startAt) { due = np.startAt }
                        }
                        let tomorrow = now.date.plusDays(1).at(LocalTime(23, 59))
                        Choice("Завтра", due == tomorrow) { due = tomorrow }
                        let week = now.date.plusWeeks(1).at(LocalTime(23, 59))
                        Choice("Через неделю", due == week) { due = week }
                        Choice("Выбрать дату…", pickDate) { withAnimation { pickDate.toggle() } }
                    }
                    if pickDate {
                        DatePicker("", selection: Binding(
                            get: { due.toDate() },
                            set: { due = LocalDateTime($0) }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .tint(C.accent)
                        .padding(8)
                        .background(C.solidCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Text("Время").font(.system(size: 13)).foregroundStyle(C.muted)
                    FlowLayout(spacing: 6) {
                        ForEach([LocalTime(8, 30), LocalTime(12, 0), LocalTime(18, 0), LocalTime(23, 59)], id: \.self) { t in
                            Choice(t.description, due.time == t) { due = due.date.at(t) }
                        }
                    }
                    Text("Срок: \(dayTitle(due.date)), \(due.time)").font(.system(size: 15, weight: .semibold)).foregroundStyle(C.ink)
                    if existing {
                        Button("Удалить дедлайн", role: .destructive) { model.deleteDeadline(draft) }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(C.error).padding(.vertical, 8)
                    }
                }
                .padding(20)
            }
            .background(C.ground.ignoresSafeArea())
            .navigationTitle(existing ? "Дедлайн" : "Новый дедлайн")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.foregroundStyle(C.muted) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if title.isBlank { titleError = true; return }
                        var d = draft
                        d.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        d.subject = subject
                        d.due = due
                        model.saveDeadline(d)
                        Task { await Notifications.requestPermission() }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            title = draft.title
            subject = draft.subject
            due = draft.due
        }
    }
}
