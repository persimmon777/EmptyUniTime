import SwiftUI

@main
struct UniTimeApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var phase

    init() {
        Refresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                model.now = LocalDateTime.now()
                if settings.onboarded { model.load(force: false) }
            case .background:
                Refresh.schedule()
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = settings.look(systemDark: scheme == .dark)
        ZStack(alignment: .bottom) {
            Group {
                if settings.onboarded {
                    MainTabs()
                } else {
                    OnboardingView { group, sub in
                        Store.shared.group = group
                        Store.shared.subgroup = sub
                        settings.onboarded = true
                        model.load(force: true)
                        Task { await Notifications.requestPermission() }
                    }
                    .background(ScreenBackground())
                }
            }
            if let d = model.editing {
                DeadlineEditor(draft: d).id(d.id).zIndex(2)
            }
            if let o = model.overlay {
                o.zIndex(3)
            }
            if let t = model.toast {
                // Как Toast в Android: серая плашка внизу.
                Text(t)
                    .ct(14, lh: 20, track: 0.25)
                    .foregroundStyle(look.dark ? Color.black : Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(look.dark ? Color(hex: 0xE6E6E6) : Color(hex: 0x323232), in: Capsule())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 96)
                    .transition(.opacity)
                    .onTapGesture { model.toast = nil }
                    .zIndex(4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .font(.roboto(16))
        .tracking(0.5)
        .environment(\.look, look)
        .tint(look.accent)
        .preferredColorScheme(settings.theme == 0 ? nil : (look.dark ? .dark : .light))
        .alert(item: $model.update) { r in
            Alert(
                title: Text("Доступна UniTime \(r.version)"),
                message: Text((r.notes.isBlank ? "" : r.notes + "\n\n") + "Скачай новый UniTime.ipa и установи его через iLoader поверх старого — данные сохранятся."),
                primaryButton: .default(Text("Открыть")) { UIApplication.shared.open(r.url) },
                secondaryButton: .cancel(Text("Позже"))
            )
        }
        .task {
            // В CI делаем скриншоты в симуляторе — системные запросы разрешений там мешают.
            if ProcessInfo.processInfo.arguments.contains("-screenshots") {
                model.openForScreenshot()
                return
            }
            if settings.onboarded {
                await Notifications.requestPermission()
                model.checkUpdate(manual: false)
            }
        }
    }
}

/// Вкладки и стек экранов поверх них — как App() в MainActivity: открытый поверх экран занимает всё окно,
/// нижняя панель видна только на самих вкладках. Состояние каждой вкладки (прокрутка, выбранный день) сохраняется.
struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C

    var body: some View {
        let pushed = !(model.paths[model.tab] ?? []).isEmpty
        VStack(spacing: 0) {
            ZStack {
                ForEach(Tab.allCases, id: \.self) { tab in
                    let on = tab == model.tab
                    NavigationStack(path: model.path(tab)) {
                        root(tab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(ScreenBackground())
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: Route.self) { destination($0) }
                    }
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.97)
                    .allowsHitTesting(on)
                    .accessibilityHidden(!on)
                    .animation(on ? .easeOut(duration: 0.22).delay(0.06) : .easeIn(duration: 0.09), value: model.tab)
                }
            }
            if !pushed {
                BottomNav(current: model.tab) { model.tab = $0 }
            }
        }
        .background(ScreenBackground())
    }

    @ViewBuilder
    private func root(_ tab: Tab) -> some View {
        switch tab {
        case .profile: AccountView(isTab: true)
        case .search: SearchView()
        case .deadlines: DeadlinesView()
        case .today, .feed:
            if let s = model.schedule {
                if tab == .today { TodayView(s: s) } else { FeedView(s: s) }
            } else if model.loading {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    EmptyCard(title: "Расписание не загружено", text: "Проверь интернет и номер группы в настройках (шестерёнка на вкладке «Сегодня»).")
                    HStack(spacing: 8) {
                        Choice("Обновить", true) { model.load(force: true) }
                        Choice("Настройки", false) { model.open(.settings) }
                    }
                }
                .padding(20)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func destination(_ r: Route) -> some View {
        Group {
            switch r {
            case .lesson(let o, let own): LessonView(o: o, own: own)
            case .other(let t): OtherView(target: t)
            case .settings: SettingsView()
            case .friends:
                if let s = model.schedule { FriendsView(mine: s) } else { Missing() }
            case .exams:
                if let s = model.schedule { ExamsView(s: s) } else { Missing() }
            case .stats:
                if let s = model.schedule { StatsView(s: s) } else { Missing() }
            case .subjects:
                if let s = model.schedule { SubjectsView(s: s) } else { Missing() }
            case .iisSection(let k): IisSectionView(section: Iis.section(k), onExpired: { model.back() })
            case .account: AccountView(isTab: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pushedScreen()
    }
}

/// Расписания нет — экран сразу закрывается (как LaunchedEffect { back() }).
private struct Missing: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Color.clear.onAppear {
            model.back()
            model.show("Сначала загрузите расписание")
        }
    }
}
