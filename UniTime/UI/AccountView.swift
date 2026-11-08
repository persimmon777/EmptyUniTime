import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    let isTab: Bool
    @State private var loggedIn = Iis.shared.loggedIn

    var body: some View {
        Group {
            if loggedIn {
                CabinetHome(isTab: isTab) {
                    loggedIn = false
                    Task {
                        await Iis.shared.logout()
                        IisWatch.reset()
                    }
                }
            } else {
                LoginView(showLabs: true) { loggedIn = true }
            }
        }
        .onAppear { loggedIn = Iis.shared.loggedIn }
    }
}

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    @Environment(\.openURL) private var openURL
    var showLabs = false
    let onDone: () -> Void
    @State private var login = Iis.shared.login
    @State private var password = ""
    @State private var remember = true
    @State private var savePw = true
    @State private var busy = false
    @State private var error: String?
    @State private var redirect: String?

    var body: some View {
        let ok = !login.isBlank && !password.isBlank && !busy
        Screen {
            ScreenTitle("iis.bsuir.by", "Профиль")
            // «Предметы» считаются по расписанию — им вход в кабинет не нужен.
            if showLabs { LabsRow() }
            VStack(spacing: 12) {
                Field(text: $login, placeholder: "Номер студенческого билета")
                Field(text: $password, placeholder: "Пароль", secure: true)
                ToggleRow(title: "Запомнить устройство", sub: "Чтобы не входить каждый раз", on: $remember)
                ToggleRow(title: "Запомнить пароль", sub: "Нужно для уведомлений о новых оценках и пропусках", on: $savePw)
                if let e = error { Text(e).font(.system(size: 14)).foregroundStyle(C.error).frame(maxWidth: .infinity, alignment: .leading) }
                BigButton(text: "Войти", enabled: ok, busy: busy) { submit() }
            }
            .card(18)
            if let url = redirect {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Сайт просит подтвердить вход").font(.system(size: 15, weight: .bold)).foregroundStyle(C.softInk)
                    Text("Открой страницу, подтверди и вернись сюда войти ещё раз.").font(.system(size: 14)).foregroundStyle(C.softInk)
                    Choice("Открыть iis.bsuir.by", true) {
                        if let u = URL(string: url.isBlank ? "https://iis.bsuir.by/login" : url) { openURL(u) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(C.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text("Логин и пароль отправляются только на iis.bsuir.by — как при входе на сайте. Если включить «Запомнить пароль», он хранится на телефоне в связке ключей iOS и нужен, чтобы входить заново, когда сайт завершит сессию. «Выйти» стирает и сессию, и пароль.")
                .font(.system(size: 12)).foregroundStyle(C.muted).lineSpacing(2)
        }
    }

    private func submit() {
        busy = true
        error = nil
        let (l, p) = (login.trimmingCharacters(in: .whitespaces), password)
        Task {
            do {
                switch try await Iis.shared.login(l, p, remember: remember, savePassword: savePw) {
                case .ok:
                    password = ""
                    IisWatch.reset()
                    // Первая проверка запоминает текущее состояние, без уведомлений.
                    Task { await IisWatch.check(notify: false) }
                    busy = false
                    onDone()
                case .redirect(let u):
                    busy = false
                    redirect = u
                case .failed(_, let m):
                    busy = false
                    error = m
                }
            } catch {
                busy = false
                self.error = "Нет связи с iis.bsuir.by"
            }
        }
    }
}

private struct LabsRow: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        LinkRow(symbol: "flag", title: "Предметы", sub: "Сколько лекций, практик и лаб осталось") {
            if model.schedule != nil { model.open(.subjects) } else { model.show("Сначала загрузите расписание") }
        }
    }
}

private struct CabinetHome: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let isTab: Bool
    let onLogout: () -> Void

    var body: some View {
        Screen {
            ScreenTitle("личный кабинет IIS · \(Iis.shared.login)", "Профиль")
            LabsRow()
            VStack(spacing: 0) {
                ForEach(Array(Iis.SECTIONS.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Divider1() }
                    Button {
                        if s.kind == .settings { model.open(.settings) } else { model.open(.iisSection(s.kind)) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: s.symbol).font(.system(size: 18)).foregroundStyle(C.accent).frame(width: 26)
                            Text(s.title).font(.system(size: 15, weight: .medium)).foregroundStyle(C.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(C.chevron)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(18, padding: 0)
            Choice("Выйти из аккаунта", false, action: onLogout)
        }
        .task {
            // Пока смотришь меню, в фоне подтягиваем самые нужные разделы — к нажатию они уже готовы.
            let wanted: Set<Iis.Kind> = [.markbook, .performance, .omissions, .profile]
            await Iis.shared.prefetch(Iis.SECTIONS.filter { wanted.contains($0.kind) }.flatMap { $0.paths })
        }
    }
}

/// Раздел кабинета: сначала сохранённое, в фоне — свежее с сервера.
struct IisSectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C
    let section: Iis.Section
    let onExpired: () -> Void
    @State private var shown: [Iis.Response?]?
    @State private var parsed: [JSON?] = []
    @State private var shownAt: Date?
    @State private var refreshing = true
    @State private var offline = false
    @State private var expired = false

    var body: some View {
        Screen(spacing: 12) {
            let status: String? = {
                if refreshing && shown != nil { return "обновляю…" }
                if offline && shown != nil { return "нет связи · данные от \(ago(shownAt))" }
                if shown != nil, shownAt != nil { return "обновлено \(ago(shownAt))" }
                return nil
            }()
            ScreenTitle(status, section.title)
            if shown == nil && refreshing {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(24)
            } else if shown == nil && expired {
                Text("Сессия закончилась — нужно войти заново.").font(.system(size: 15)).foregroundStyle(C.ink)
                Choice("Войти", true, action: onExpired)
            } else if shown == nil {
                Text("Нет связи с iis.bsuir.by").font(.system(size: 14)).foregroundStyle(C.error)
            } else if let rs = shown {
                if expired {
                    HStack(spacing: 10) {
                        Text("Сессия закончилась — показаны сохранённые данные.").font(.system(size: 13)).foregroundStyle(C.muted)
                        Choice("Войти", true, action: onExpired)
                    }
                }
                content(rs)
                Button("Скопировать данные для отладки") {
                    UIPasteboard.general.string = zip(section.paths, rs).map { "\($0) → \($1?.code ?? 0)\n\($1?.text ?? "")" }.joined(separator: "\n\n")
                    model.show("Скопировано")
                }
                .font(.system(size: 12)).foregroundStyle(C.muted).padding(.vertical, 8)
            }
        }
        .task(id: section) { await load() }
    }

    @ViewBuilder
    private func content(_ rs: [Iis.Response?]) -> some View {
        let first = parsed.first ?? nil
        let at = { (i: Int) -> JSON? in i < parsed.count ? parsed[i] : nil }
        switch section.kind {
        case .profile: if let f = first, f.isObject { ProfileCard(o: f) } else { Unavailable(rs: rs) }
        case .markbook: if let f = first, f.has("markPages") { MarkbookView(o: f) } else { Unavailable(rs: rs) }
        case .performance: if let f = first { PerformanceView(v: f) } else { Unavailable(rs: rs) }
        case .omissions: OmissionsView(respectful: at(0), disrespectful: at(1))
        case .dean: DeanView(v: first)
        case .dormitory: DormitoryView(applications: at(0), privileges: at(1), premiumPenalty: at(2))
        case .group: if let f = first { GroupView(v: f) } else { Unavailable(rs: rs) }
        case .library: LibraryView(v: first)
        case .notifications: NotificationsView(v: first)
        case .settings: AccountSettingsView(lastChange: at(0), attempts: at(1), contacts: at(2), raw: rs.first ?? nil)
        }
    }

    private func show(_ rs: [Iis.Response?], _ date: Date?) {
        parsed = rs.map { r in r.flatMap { $0.ok ? $0.json : nil } }
        shown = rs
        shownAt = date
    }

    private func load() async {
        let iis = Iis.shared
        // 1) Сразу — то, что сохранено с прошлого раза.
        let cached = section.paths.map { iis.cached($0) }
        if cached.contains(where: { $0 != nil }) { show(cached.map { $0?.0 }, cached.compactMap { $0?.1 }.min()) }
        // 2) Свежие данные с сервера, параллельно.
        var fresh = [Iis.Response?](repeating: nil, count: section.paths.count)
        await withTaskGroup(of: (Int, Iis.Response?).self) { g in
            for (i, p) in section.paths.enumerated() { g.addTask { (i, try? await iis.get(p)) } }
            for await (i, r) in g { fresh[i] = r }
        }
        refreshing = false
        if fresh.allSatisfy({ $0 == nil }) { offline = true }
        else if fresh.contains(where: { $0?.code == 401 }) || fresh.allSatisfy({ $0?.code == 403 }) { expired = true }
        else { show(fresh.enumerated().map { i, r in r ?? cached[i]?.0 }, Date()) }
    }
}

/// «только что», «5 мин назад», «8 нояб., 18:20».
private func ago(_ at: Date?) -> String {
    guard let at = at else { return "давно" }
    let min = Int(Date().timeIntervalSince(at) / 60)
    if min < 1 { return "только что" }
    if min < 60 { return "\(min) мин назад" }
    if min < 24 * 60 { return "\(min / 60) ч назад" }
    let d = LocalDateTime(at)
    return "\(d.date.day) \(month(d.date)), \(d.time)"
}

private struct Unavailable: View {
    let rs: [Iis.Response?]
    var body: some View {
        let code = (rs.first ?? nil)?.code
        EmptyCard(title: "Раздел недоступен",
                  text: code != nil ? "Сервер ответил \(code!) — возможно, у твоего аккаунта нет этого раздела." : "Нет связи с iis.bsuir.by.")
    }
}
