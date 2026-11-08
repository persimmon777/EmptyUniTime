import SwiftUI

/// Первый запуск: вход в IIS (группа подставится сама) или ручной выбор группы, затем подгруппа.
struct OnboardingView: View {
    @Environment(\.look) private var C
    let onFinish: (String, Int) -> Void

    private enum Step { case welcome, login, fetching, group, subgroup }
    @State private var step = Step.welcome
    @State private var group = ""
    @State private var fromIis = false

    var body: some View {
        Group {
            switch step {
            case .welcome: welcome
            case .login:
                VStack(spacing: 0) {
                    backBar { step = .welcome }
                    LoginView { step = .fetching }
                }
            case .fetching:
                VStack(spacing: 12) {
                    ProgressView().tint(C.accent)
                    Text("Узнаю твою группу…").font(.system(size: 14)).foregroundStyle(C.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    let g = (try? await Iis.shared.get("/auth/user")).flatMap { $0.ok ? $0.json?.str("group") : nil } ?? ""
                    fromIis = true
                    if g.isBlank { step = .group } else { group = g; step = .subgroup }
                }
            case .group:
                VStack(spacing: 0) {
                    backBar { step = .welcome }
                    GroupStep(initial: group) { group = $0; step = .subgroup }
                }
            case .subgroup:
                VStack(spacing: 0) {
                    backBar { step = fromIis ? .welcome : .group }
                    SubgroupStep(group: group) { onFinish(group, $0) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func backBar(_ action: @escaping () -> Void) -> some View {
        HStack { RoundButton(symbol: "chevron.left", label: "Назад", action: action); Spacer() }
            .padding(.horizontal, 20).padding(.top, 8)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x2B5CE6))
                Image(systemName: "graduationcap.fill").font(.system(size: 50, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 104, height: 104)
            Text("UniTime").font(.system(size: 34, weight: .heavy)).foregroundStyle(C.ink).padding(.top, 20)
            Text("Расписание БГУИР, следующая пара на экране блокировки, дедлайны и личный кабинет — в одном месте.")
                .font(.system(size: 15)).foregroundStyle(C.muted).multilineTextAlignment(.center).padding(.top, 8)
            Spacer().frame(height: 36)
            BigButton(text: "Войти через IIS") { fromIis = true; step = .login }
            Text("Группа подставится сама, а ещё будут оценки, пропуски и уведомления о новом.")
                .font(.system(size: 12)).foregroundStyle(C.muted).multilineTextAlignment(.center).padding(.top, 6).padding(.bottom, 16)
            BigButton(text: "Без входа — указать группу", primary: false) { fromIis = false; step = .group }
            Spacer()
            Text("made by molex1le").font(.system(size: 12)).foregroundStyle(C.muted).padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }
}

private struct GroupStep: View {
    @Environment(\.look) private var C
    let initial: String
    let onPick: (String) -> Void
    @State private var query = ""
    @State private var groups: [Target]?
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = q.isEmpty ? [] : Array((groups ?? []).filter { $0.title.hasPrefix(q) }.prefix(8))
        Screen {
            ScreenTitle("шаг 1 из 2", "Твоя группа")
            Field(text: $query, placeholder: "Номер группы, например 572302", number: true, symbol: "magnifyingglass")
                .onChange(of: query) { _, v in
                    let digits = v.filter { $0.isNumber }
                    if digits != v { query = digits }
                    error = nil
                }
            if let e = error { Text(e).font(.system(size: 14)).foregroundStyle(C.error) }
            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { i, t in
                        if i > 0 { Divider1() }
                        Button { query = t.title; pick(t.title) } label: {
                            HStack(spacing: 12) {
                                Text(t.title).font(.system(size: 16, weight: .bold)).foregroundStyle(C.ink)
                                Text(t.sub).font(.system(size: 13)).foregroundStyle(C.muted).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(18, padding: 0)
            }
            if groups == nil { Text("Загружаю список групп…").font(.system(size: 13)).foregroundStyle(C.muted) }
            BigButton(text: "Дальше", enabled: q.count >= 6, busy: checking) { pick(q) }
        }
        .onAppear { if query.isEmpty { query = initial } }
        .task { groups = try? await Store.shared.allGroups() }
    }

    /// Проверяем, что расписание группы существует, прежде чем идти дальше.
    private func pick(_ g: String) {
        error = nil
        checking = true
        Task {
            let ok = (try? await Store.shared.fetchOther(.group(g))) != nil
            checking = false
            if ok { onPick(g) } else { error = "Не нашёл расписание группы \(g). Проверь номер или интернет." }
        }
    }
}

private struct SubgroupStep: View {
    @Environment(\.look) private var C
    let group: String
    let onDone: (Int) -> Void
    @State private var sub = 0

    var body: some View {
        Screen {
            ScreenTitle("группа \(group) · шаг 2 из 2", "Подгруппа")
            Text("Лабораторные часто идут по подгруппам. Выбери свою — увидишь только свои пары. Если не знаешь, оставь «Все», поменять можно в настройках.")
                .font(.system(size: 14)).foregroundStyle(C.muted)
            Segmented(labels: ["Все", "1", "2"], selected: sub) { sub = $0 }
            BigButton(text: "Готово") { onDone(sub) }
        }
    }
}
