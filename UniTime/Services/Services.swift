import Foundation
import ActivityKit
import EventKit
import BackgroundTasks
import WidgetKit

// MARK: Live Activity

/// Текущая или следующая пара на экране блокировки и в Dynamic Island — замена постоянного уведомления Android.
enum LiveActivity {
    static func sync(_ s: Schedule?) async {
        let st = AppSettings.shared
        let activities = Activity<PairActivityAttributes>.activities
        guard st.liveActivity, ActivityAuthorizationInfo().areActivitiesEnabled, let s = s else {
            for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let store = Store.shared
        let now = LocalDateTime.now()
        let (cur, next) = s.currentAndNext(now: now, subgroup: store.subgroup)
        // Показываем только сегодняшние пары (или ближайшую в ближайшие 12 часов, если не прятать после последней).
        let target: Occurrence?
        if let cur = cur { target = cur }
        else if let n = next, n.date == now.date || (!st.hideAfterLast && now.minutes(to: n.startAt) <= 12 * 60) { target = n }
        else { target = nil }
        guard let o = target else {
            for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let l = o.lesson
        let after: Occurrence? = cur != nil ? next : s.upcoming(now: now, subgroup: store.subgroup, count: 3).first { $0.startAt.isAfter(o.startAt) }
        let typeName = ["ЛК": "Лекция", "ПЗ": "Практика", "ЛР": "Лабораторная", "Экз": "Экзамен", "Конс": "Консультация"][l.type] ?? l.type
        let state = PairActivityAttributes.ContentState(
            title: l.fullTitle,
            short: [l.subject, l.type].filter { !$0.isBlank }.joined(separator: " "),
            detail: [typeName, st.notifRoom ? l.rooms : "", st.notifTeacher ? l.teacher : ""].filter { !$0.isBlank }.joined(separator: " · "),
            room: l.rooms,
            isNow: cur != nil,
            start: o.startAt.toDate(),
            end: o.endAt.toDate(),
            next: after.flatMap { a in a.date == o.date ? "Далее: \(lessonName(a)) в \(a.lesson.start)" : nil } ?? ""
        )
        let content = ActivityContent(state: state, staleDate: o.endAt.toDate())
        if let a = activities.first {
            await a.update(content)
            for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else {
            _ = try? Activity.request(attributes: PairActivityAttributes(group: store.group), content: content, pushType: nil)
        }
    }
}

// MARK: Календарь

/// Пары до конца семестра и экзамены — в отдельный календарь «UniTime» (его можно целиком удалить).
enum CalendarExport {
    private static let key = "calendarId"

    static func access(_ store: EKEventStore) async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw Net.Failure.message("Без доступа к календарю не получится")
        }
    }

    @discardableResult
    static func remove() async throws -> Bool {
        let store = EKEventStore()
        try await access(store)
        let d = Store.shared.defaults
        guard let id = d.string(forKey: key), let cal = store.calendar(withIdentifier: id) else { return false }
        try store.removeCalendar(cal, commit: true)
        d.removeObject(forKey: key)
        return true
    }

    static func export(_ s: Schedule, subgroup: Int) async throws -> Int {
        let store = EKEventStore()
        try await access(store)
        let d = Store.shared.defaults
        if let id = d.string(forKey: key), let old = store.calendar(withIdentifier: id) { try? store.removeCalendar(old, commit: true) }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "UniTime"
        cal.cgColor = CGColor(red: 0.18, green: 0.31, blue: 0.85, alpha: 1)
        let sources = store.sources
        cal.source = store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? sources.first { $0.sourceType == .local }
            ?? sources.first
        try store.saveCalendar(cal, commit: true)
        d.set(cal.calendarIdentifier, forKey: key)

        let today = LocalDate.today()
        let end = s.termEnd ?? today.plusWeeks(16)
        var all = [Occurrence]()
        var day = today
        while day <= end { all += s.lessonsOn(day, subgroup: subgroup); day = day.plusDays(1) }
        all += s.exams.filter { $0.date >= today }
        for o in all {
            let l = o.lesson
            let e = EKEvent(eventStore: store)
            e.calendar = cal
            e.title = l.type.isBlank ? l.fullTitle : "\(l.fullTitle) (\(l.type))"
            e.location = l.rooms
            e.notes = [l.teacher, l.subgroup != 0 ? "Подгруппа \(l.subgroup)" : "", l.note].filter { !$0.isBlank }.joined(separator: "\n")
            e.startDate = o.startAt.toDate()
            e.endDate = o.endAt.toDate()
            try store.save(e, span: .thisEvent, commit: false)
        }
        try store.commit()
        return all.count
    }
}

// MARK: Фоновое обновление

/// Обновление расписания, проверка IIS, виджеты и напоминания. Вызывается при запуске и фоновой задачей iOS.
enum Refresh {
    static let taskId = "com.unitime.ios.refresh"

    /// Вернёт ошибку загрузки, если она была.
    @discardableResult
    static func run(force: Bool = false) async -> Error? {
        let store = Store.shared
        var err: Error?
        if !store.group.isBlank && (force || store.isStale()) {
            do {
                let changes = try await store.fetch()
                if !changes.isEmpty && AppSettings.shared.notifyChanges {
                    let text = changes.prefix(6).joined(separator: "\n") + (changes.count > 6 ? "\nи ещё \(changes.count - 6)" : "")
                    Notifications.post(title: "Расписание изменилось", body: text, id: "changes.\(Int(Date().timeIntervalSince1970))")
                }
            } catch {
                err = error
            }
        }
        await render()
        return err
    }

    /// Перерисовать всё, что зависит от расписания: виджеты, Live Activity, напоминания.
    static func render() async {
        let s = Store.shared.load()
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivity.sync(s)
        await Notifications.reschedule(schedule: s)
    }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            schedule()
            let work = Task {
                await run()
                if IisWatch.due() { await IisWatch.check() }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Попросить iOS разбудить приложение примерно через час (точное время решает система).
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: taskId)
        r.earliestBeginDate = Date().addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(r)
    }
}

// MARK: Обновления приложения

/// Новые версии — из релизов этого репозитория на GitHub; установка — заново через iLoader.
enum AppUpdate {
    static let repo = "persimmon777/EmptyUniTime"

    struct Release: Identifiable {
        let version: String
        let notes: String
        let url: URL
        var id: String { version }
    }

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// «1.10» новее «1.9»: сравниваем по числам.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            (s.hasPrefix("v") ? String(s.dropFirst()) : s).split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(installed)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func checkNewer() async throws -> Release? {
        let data = try await Net.get("https://api.github.com/repos/\(repo)/releases/latest")
        guard let j = JSON.parse(data) else { return nil }
        let tag = j.str("tag_name")
        guard !tag.isBlank, isNewer(tag, than: current), let url = URL(string: j.str("html_url")) else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, notes: j.str("body"), url: url)
    }
}
