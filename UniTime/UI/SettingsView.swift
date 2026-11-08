import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var s: AppSettings
    @Environment(\.look) private var C
    @Environment(\.openURL) private var openURL
    @State private var group = ""
    @State private var sub = 0
    @State private var secretTaps = 0
    @State private var calendarBusy = false

    var body: some View {
        let store = model.store
        Screen(spacing: 12) {
            ScreenTitle(nil, "Настройки")
            LinkRow(symbol: "person.crop.circle", title: "Личный кабинет IIS", sub: "Оценки, пропуски, льготы, взыскания") { model.open(.account) }

            SectionLabel("Группа")
            SettingsCard {
                Field(text: $group, placeholder: "Номер группы", number: true)
                    .onChange(of: group) { _, v in
                        let digits = v.filter { $0.isNumber }
                        if digits != v { group = digits }
                    }
                Label13("Подгруппа")
                Segmented(labels: ["Все", "1", "2"], selected: sub) { sub = $0 }
                if group != store.group || sub != store.subgroup {
                    Choice("Сохранить и обновить", true) {
                        if !group.isBlank { store.group = group }
                        store.subgroup = sub
                        model.schedule = store.load()
                        model.load(force: true)
                    }
                }
            }

            SectionLabel("Внешний вид")
            SettingsCard {
                Label13("Тема")
                // В списке «Авто, Светлая, Чёрная, Неон», а хранятся номера 0, 1, 3, 4.
                let themes = [("Авто", 0), ("Светлая", 1), ("Чёрная", 3)] + (s.neonUnlocked ? [("Неон", 4)] : [])
                Segmented(labels: themes.map { $0.0 }, selected: themes.firstIndex { $0.1 == s.theme } ?? 0) { s.theme = themes[$0].1 }
                Label13("Стиль")
                Segmented(labels: ["Обычный", "Стекло", "Цвет пар"], selected: s.style) { s.style = $0 }
                Label13("Акцент")
                FlowLayout(spacing: 6) {
                    ForEach(ACCENTS.indices, id: \.self) { i in Choice(ACCENTS[i].name, s.accent == i) { s.accent = i } }
                }
                ToggleRow(title: "Короткие названия в списках", sub: "«МатПрог»", on: $s.shortNames)
                ToggleRow(title: "Номера пар", sub: "«3 пара»", on: $s.pairNumbers)
                Label13("Открывать при запуске")
                FlowLayout(spacing: 6) {
                    ForEach(Tab.allCases, id: \.self) { t in Choice(t.label, s.startTab == t.rawValue) { s.startTab = t.rawValue } }
                }
            }

            SectionLabel("Скрытые пары")
            SettingsCard {
                Label13("Нажми на предмет, чтобы скрыть его целиком")
                FlowLayout(spacing: 6) {
                    ForEach((model.schedule?.subjects() ?? []).map { $0.short }, id: \.self) { short in
                        let key = "S:\(short)"
                        Choice(short, s.hidden.contains(key)) {
                            if s.hidden.contains(key) { s.hidden.remove(key) } else { s.hidden.insert(key) }
                            model.reloadLocal()
                        }
                    }
                }
                let single = s.hidden.filter { !$0.hasPrefix("S:") }.sorted()
                if !single.isEmpty {
                    Label13("Отдельные пары (скрыты из карточки пары)")
                    ForEach(single, id: \.self) { key in
                        HStack {
                            Text(describeKey(key)).font(.system(size: 14)).foregroundStyle(C.ink)
                            Spacer()
                            Button("Вернуть") { s.hidden.remove(key); model.reloadLocal() }
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(C.accent)
                        }
                    }
                }
            }

            SectionLabel("Экран блокировки")
            SettingsCard {
                ToggleRow(title: "Live Activity с парой", sub: "Текущая или следующая пара с отсчётом на экране блокировки и в Dynamic Island", on: $s.liveActivity)
                ToggleRow(title: "Прятать, когда пары кончились", sub: "И в выходные", on: $s.hideAfterLast)
                ToggleRow(title: "Аудитория", on: $s.notifRoom)
                ToggleRow(title: "Преподаватель", on: $s.notifTeacher)
                Text("Ещё удобнее — виджет «Следующая пара» на экране блокировки: зажми экран блокировки → Настроить → Виджеты → UniTime.")
                    .font(.system(size: 12)).foregroundStyle(C.muted)
            }
            .onChange(of: s.liveActivity) { _, _ in model.reloadLocal() }
            .onChange(of: s.hideAfterLast) { _, _ in model.reloadLocal() }
            .onChange(of: s.notifRoom) { _, _ in model.reloadLocal() }
            .onChange(of: s.notifTeacher) { _, _ in model.reloadLocal() }

            SectionLabel("Напоминания")
            SettingsCard {
                Label13("За сколько минут до пары")
                FlowLayout(spacing: 6) {
                    ForEach(AppSettings.REMIND_OPTIONS, id: \.self) { m in
                        Choice("\(m) мин", s.remindMinutes == m) { s.remindMinutes = m; model.reloadLocal() }
                    }
                }
                ToggleRow(title: "Звук", sub: "Для пар и дедлайнов", on: $s.remindSound)
                ToggleRow(title: "Если расписание изменилось", sub: "Сравниваю при каждом обновлении", on: $s.notifyChanges)
                Text("Включить напоминание для пары — в её карточке.").font(.system(size: 12)).foregroundStyle(C.muted)
            }

            SectionLabel("Новое в личном кабинете")
            IisNotifyCard()

            SectionLabel("Календарь")
            SettingsCard {
                Text("Добавить все пары до конца семестра и экзамены в отдельный календарь «UniTime» на iPhone").font(.system(size: 14)).foregroundStyle(C.ink)
                HStack(spacing: 8) {
                    Choice(calendarBusy ? "Добавляю…" : "Добавить", true) { calendar(add: true) }
                    Choice("Убрать оттуда", false) { calendar(add: false) }
                }
            }

            SectionLabel("Обновления")
            SettingsCard {
                Text("Установлена UniTime \(AppUpdate.current)").font(.system(size: 15, weight: .medium)).foregroundStyle(C.ink)
                ToggleRow(title: "Сообщать о новых версиях", sub: "Проверка раз в день; установка — через iLoader", on: $s.updateCheck)
                HStack(spacing: 8) {
                    Choice("Проверить сейчас", false) { model.checkUpdate(manual: true) }
                    Choice("Все версии", false) {
                        if let u = URL(string: "https://github.com/\(AppUpdate.repo)/releases") { openURL(u) }
                    }
                }
            }

            SectionLabel("Данные")
            SettingsCard {
                Text(store.lastFetch.map { d in let l = LocalDateTime(d); return "Обновлено \(l.date.day) \(month(l.date)), \(l.time)" } ?? "Расписание ещё не загружалось")
                    .font(.system(size: 14)).foregroundStyle(C.ink)
                if !store.shared {
                    Text("Общее хранилище для виджетов недоступно — виджеты покажут «Откройте приложение». Обычно это значит, что установщик не выдал приложению App Group.")
                        .font(.system(size: 12)).foregroundStyle(C.error)
                }
                Choice("Обновить сейчас", false) { model.load(force: true) }
            }

            // Пасхалка: 7 тапов по подписи открывают секретную статистику.
            Text("UniTime · данные с iis.bsuir.by\nmade by molex1le · iOS-версия")
                .font(.system(size: 12)).foregroundStyle(C.muted)
                .padding(.top, 8)
                .onTapGesture {
                    secretTaps += 1
                    if secretTaps >= 7 {
                        secretTaps = 0
                        if model.schedule != nil { model.open(.stats) } else { model.show("Сначала загрузите расписание") }
                    }
                }
        }
        .onAppear {
            group = store.group
            sub = store.subgroup
        }
    }

    private func calendar(add: Bool) {
        guard !calendarBusy else { return }
        guard let sch = model.schedule else { model.show("Сначала загрузите расписание"); return }
        calendarBusy = true
        Task {
            do {
                if add {
                    let n = try await CalendarExport.export(sch, subgroup: model.store.subgroup)
                    model.show("Добавлено событий: \(n)")
                } else {
                    let removed = try await CalendarExport.remove()
                    model.show(removed ? "Календарь «UniTime» удалён" : "Нечего удалять")
                }
            } catch {
                model.show("Календарь: \(error.localizedDescription)")
            }
            calendarBusy = false
        }
    }
}

private struct Label13: View {
    @Environment(\.look) private var C
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(C.muted).frame(maxWidth: .infinity, alignment: .leading) }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }.card(18)
    }
}

private struct IisNotifyCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var s: AppSettings
    @Environment(\.look) private var C
    @State private var checking = false
    @State private var last = IisWatch.lastCheck
    @State private var hasPw = Iis.shared.hasSavedPassword

    var body: some View {
        SettingsCard {
            if !Iis.shared.loggedIn {
                Text("Войди на вкладке «Профиль», чтобы получать уведомления о новых оценках, пропусках и сообщениях.")
                    .font(.system(size: 14)).foregroundStyle(C.ink)
            } else {
                ToggleRow(title: "Уведомлять о новом", sub: "Оценки, пропуски, сообщения из IIS", on: $s.iisNotify)
                if s.iisNotify {
                    Label13("Проверять не чаще, чем раз в")
                    FlowLayout(spacing: 6) {
                        ForEach(AppSettings.IIS_HOURS, id: \.self) { h in Choice("\(h) ч", s.iisHours == h) { s.iisHours = h } }
                    }
                    ToggleRow(title: "Оценки и отметки", sub: "Зачётка и журнал успеваемости", on: $s.iisMarks)
                    ToggleRow(title: "Пропуски", on: $s.iisOmissions)
                    ToggleRow(title: "Сообщения из IIS", on: $s.iisMessages)
                    ToggleRow(title: "Поощрения и взыскания", on: $s.iisPenalties)
                    Text("iOS сама решает, когда разбудить приложение в фоне, поэтому проверки бывают реже. Открой приложение — проверка пройдёт сразу.")
                        .font(.system(size: 12)).foregroundStyle(C.muted)
                }
                Button { model.open(.iisSection(.settings)) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Пароль и контакты IIS").font(.system(size: 15, weight: .medium)).foregroundStyle(C.ink)
                            Text("Последняя смена пароля, попытки входа, почта и телефон").font(.system(size: 12)).foregroundStyle(C.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(C.chevron)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !hasPw {
                    Text("Пароль не сохранён: когда сайт завершит сессию, проверки остановятся до следующего входа. Чтобы этого не было, выйди и войди снова с «Запомнить пароль».")
                        .font(.system(size: 12)).foregroundStyle(C.muted)
                }
                Text(last.map { d in let l = LocalDateTime(d); return "Последняя проверка: \(l.date.day) \(month(l.date)), \(l.time)" } ?? "Ещё не проверялось")
                    .font(.system(size: 13)).foregroundStyle(C.muted)
                FlowLayout(spacing: 8) {
                    Choice(checking ? "Проверяю…" : "Проверить сейчас", false) {
                        guard !checking else { return }
                        checking = true
                        Task {
                            let found = await IisWatch.check()
                            checking = false
                            last = IisWatch.lastCheck
                            model.show(found == nil ? "Нет связи с iis.bsuir.by" : found!.isEmpty ? "Ничего нового" : "Нового: \(found!.count)")
                        }
                    }
                    if hasPw { Choice("Забыть пароль", false) { Iis.shared.forgetPassword(); hasPw = false } }
                }
            }
        }
    }
}
