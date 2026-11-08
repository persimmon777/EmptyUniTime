import SwiftUI

enum Tab: Int, CaseIterable {
    case today, feed, deadlines, profile, search

    var label: String {
        switch self {
        case .today: return "Сегодня"
        case .feed: return "Пары"
        case .deadlines: return "Дедлайны"
        case .profile: return "Профиль"
        case .search: return "Поиск"
        }
    }

    var glyph: GlyphKind {
        switch self {
        case .today: return .clock
        case .feed: return .calendar
        case .deadlines: return .flag
        case .profile: return .user
        case .search: return .search
        }
    }
}

/// Экраны поверх вкладок.
enum Route: Hashable {
    case lesson(Occurrence, own: Bool)
    case other(Target)
    case settings
    case friends
    case exams
    case stats
    case subjects
    case iisSection(Iis.Kind)
    case account
}

/// Состояние приложения: расписание, дедлайны, текущее время, сообщения.
@MainActor
final class AppModel: ObservableObject {
    let store = Store.shared
    @Published var schedule: Schedule?
    @Published var loading = false
    @Published var deadlines: [Deadline] = []
    @Published var now = LocalDateTime.now()
    @Published var toast: String?
    @Published var editing: Deadline?
    @Published var update: AppUpdate.Release?
    /// Диалог поверх всего приложения (как AlertDialog в Android).
    @Published var overlay: AnyView?
    @Published var tab: Tab = .today
    @Published var paths: [Tab: [Route]] = [:]

    private var timer: Timer?
    private var toastTask: Task<Void, Never>?

    init() {
        schedule = store.load()
        deadlines = store.deadlines()
        tab = Tab(rawValue: AppSettings.shared.startTab) ?? .today
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = LocalDateTime.now() }
        }
    }

    func path(_ t: Tab) -> Binding<[Route]> {
        Binding(get: { self.paths[t] ?? [] }, set: { self.paths[t] = $0 })
    }

    /// Открыть экран на текущей вкладке.
    func open(_ r: Route) {
        if case .other(let t) = r { store.addRecent(t) }
        paths[tab, default: []].append(r)
    }

    func present(_ v: AnyView) { withAnimation(.easeOut(duration: 0.15)) { overlay = v } }
    func dismissOverlay() { withAnimation(.easeOut(duration: 0.15)) { overlay = nil } }

    func back() {
        if !(paths[tab] ?? []).isEmpty { paths[tab]?.removeLast() }
    }

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    func load(force: Bool) {
        loading = true
        Task {
            let err = await Refresh.run(force: force)
            schedule = store.load()
            loading = false
            if let e = err { show("Не удалось обновить: \(e.localizedDescription)") }
            else if force { show("Расписание обновлено") }
        }
    }

    /// Перечитать скрытые пары/дедлайны и перерисовать виджеты и напоминания.
    func reloadLocal() {
        schedule = store.load()
        deadlines = store.deadlines()
        Task { await Refresh.render() }
    }

    func saveDeadline(_ d: Deadline) {
        store.saveDeadline(d)
        editing = nil
        reloadLocal()
    }

    func deleteDeadline(_ d: Deadline) {
        store.deleteDeadline(d.id)
        editing = nil
        reloadLocal()
    }

    func newDeadline(subject: String = "", due: LocalDateTime? = nil) {
        editing = Deadline(
            id: Int64(Date().timeIntervalSince1970 * 1000),
            title: "",
            subject: subject,
            due: due ?? LocalDate.today().plusDays(1).at(LocalTime(23, 59)),
            done: false
        )
    }

    func checkUpdate(manual: Bool) {
        let st = AppSettings.shared
        if !manual && !st.updateCheck { return }
        if !manual {
            let last = store.defaults.double(forKey: "updateCheckedAt")
            if Date().timeIntervalSince1970 - last < 86400 { return }
        }
        Task {
            do {
                let r = try await AppUpdate.checkNewer()
                store.defaults.set(Date().timeIntervalSince1970, forKey: "updateCheckedAt")
                if let r = r { update = r }
                else if manual { show("У тебя последняя версия \(AppUpdate.current)") }
            } catch {
                if manual { show("Не удалось проверить: нет связи") }
            }
        }
    }

    /// Только для скриншотов в CI: открыть экран из аргумента запуска «-openRoute <имя>».
    func openForScreenshot() {
        guard let r = UserDefaults.standard.string(forKey: "openRoute") else { return }
        Task {
            for _ in 0..<40 where schedule == nil { try? await Task.sleep(nanoseconds: 250_000_000) }
            switch r {
            case "settings": open(.settings)
            case "exams": open(.exams)
            case "subjects": open(.subjects)
            case "stats": open(.stats)
            case "friends": open(.friends)
            case "account": open(.account)
            case "editor": newDeadline()
            case "lesson":
                if let o = schedule?.upcoming(now: now, subgroup: store.subgroup, count: 1).first { open(.lesson(o, own: true)) }
            case "teacher":
                if let t = schedule?.upcoming(now: now, subgroup: store.subgroup, count: 5).compactMap({ $0.lesson.teachers.first }).first {
                    open(.other(Target(kind: "teacher", id: t.urlId, title: t.full, sub: t.title)))
                }
            default: break
            }
        }
    }

    func unlockNeon() {
        let st = AppSettings.shared
        if st.neonUnlocked && st.theme == 4 { show("Ты уже в неоне ✨"); return }
        let first = !st.neonUnlocked
        st.neonUnlocked = true
        st.theme = 4
        show(first ? "Секретная тема «Неон» открыта! Вернуть обычную — в настройках" : "Снова неон ✨")
    }
}
