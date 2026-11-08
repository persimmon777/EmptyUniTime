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
            if let t = model.toast {
                Text(t)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(look.dark ? Color.black : Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(look.dark ? Color.white.opacity(0.92) : Color.black.opacity(0.85), in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
        .environment(\.look, look)
        .tint(look.accent)
        .preferredColorScheme(settings.theme == 0 ? nil : (look.dark ? .dark : .light))
        .sheet(item: $model.editing) { d in
            DeadlineEditor(draft: d).environment(\.look, look).environmentObject(model)
        }
        .alert(item: $model.update) { r in
            Alert(
                title: Text("Доступна UniTime \(r.version)"),
                message: Text((r.notes.isBlank ? "" : r.notes + "\n\n") + "Скачай новый UniTime.ipa и установи его через iLoader поверх старого — данные сохранятся."),
                primaryButton: .default(Text("Открыть")) { UIApplication.shared.open(r.url) },
                secondaryButton: .cancel(Text("Позже"))
            )
        }
        .task {
            if settings.onboarded {
                await Notifications.requestPermission()
                model.checkUpdate(manual: false)
            }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var C

    var body: some View {
        TabView(selection: $model.tab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                NavigationStack(path: model.path(tab)) {
                    root(tab)
                        .background(ScreenBackground())
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Route.self) { destination($0) }
                }
                .tabItem { Label(tab.label, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .toolbarBackground(C.style == .classic ? C.solidCard : C.ground.opacity(0.6), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
                VStack(spacing: 16) {
                    EmptyCard(title: "Расписание не загружено", text: "Проверь интернет и номер группы в настройках.")
                    HStack {
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
                if let s = model.schedule { FriendsView(mine: s) } else { EmptyCard(title: "Сначала загрузите расписание", text: "") .padding(20) }
            case .exams:
                if let s = model.schedule { ExamsView(s: s) }
            case .stats:
                if let s = model.schedule { StatsView(s: s) }
            case .subjects:
                if let s = model.schedule { SubjectsView(s: s) }
            case .iisSection(let k): IisSectionView(section: Iis.section(k), onExpired: { model.back() })
            case .account: AccountView(isTab: false)
            }
        }
        .pushedScreen()
    }
}
