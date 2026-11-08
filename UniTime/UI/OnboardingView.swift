import SwiftUI

/// Первый запуск (OnboardingScreen): вход в IIS (группа подставится сама) или ручной выбор группы, затем подгруппа.
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
                LoginView(onBack: { step = .welcome }) { step = .fetching }
            case .fetching:
                VStack(spacing: 12) {
                    ProgressView().tint(C.accent)
                    Text("Узнаю твою группу…").ct(14).foregroundStyle(C.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    let g = (try? await Iis.shared.get("/auth/user")).flatMap { $0.ok ? $0.json?.str("group") : nil } ?? ""
                    fromIis = true
                    if g.isBlank { step = .group } else { group = g; step = .subgroup }
                }
            case .group:
                GroupStep(initial: group, onBack: { step = .welcome }) { group = $0; step = .subgroup }
            case .subgroup:
                SubgroupStep(group: group, onBack: { step = fromIis ? .welcome : .group }) { onFinish(group, $0) }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            // Иконка приложения: синий фон и шапочка, как адаптивная иконка Android.
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x2B5CE6))
                SchoolIcon().fill(.white).padding(104 * 26.4 / 108)
            }
            .frame(width: 104, height: 104)
            Spacer().frame(height: 20)
            Text("UniTime").ct(34, .heavy).foregroundStyle(C.ink)
            Spacer().frame(height: 8)
            Text("Расписание БГУИР, следующая пара на экране блокировки, дедлайны и личный кабинет — в одном месте.")
                .ct(15, lh: 21).foregroundStyle(C.muted).multilineTextAlignment(.center)
            Spacer().frame(height: 36)
            BigButton(text: "Войти через IIS") { fromIis = true; step = .login }
            Text("Группа подставится сама, а ещё будут оценки, пропуски и уведомления о новом.")
                .ct(12).foregroundStyle(C.muted).multilineTextAlignment(.center).padding(.top, 6).padding(.bottom, 16)
            BigButton(text: "Без входа — указать группу", primary: false) { fromIis = false; step = .group }
            Spacer().frame(height: 24)
            Text("made by molex1le").ct(12).foregroundStyle(C.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Значок «school» из Material Icons (ic_launcher_foreground).
struct SchoolIcon: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var p = Path()
        p.addLines([pt(12, 3), pt(1, 9), pt(12, 15), pt(21, 10.09), pt(21, 17), pt(23, 17), pt(23, 9)]); p.closeSubpath()
        p.addLines([pt(5, 13.18), pt(5, 17.18), pt(12, 21), pt(19, 17.18), pt(19, 13.18), pt(12, 17)]); p.closeSubpath()
        return p
    }
}

private struct GroupStep: View {
    @Environment(\.look) private var C
    let initial: String
    let onBack: () -> Void
    let onPick: (String) -> Void
    @State private var query = ""
    @State private var groups: [Target]?
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = q.isEmpty ? [] : Array((groups ?? []).filter { $0.title.hasPrefix(q) }.prefix(8))
        Screen(spacing: 14, top: 12, bottom: 32) {
            RoundButton(glyph: .back, label: "Назад", action: onBack)
            ScreenTitle("шаг 1 из 2", "Твоя группа")
            Field(text: $query, placeholder: "Номер группы, например 572302", number: true, glyph: .search)
                .onChange(of: query) { _, v in
                    let digits = v.filter { $0.isNumber }
                    if digits != v { query = digits }
                    error = nil
                }
            if let e = error { Text(e).ct(14).foregroundStyle(C.error) }
            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.offset) { i, t in
                        if i > 0 { Divider1() }
                        Button { query = t.title; pick(t.title) } label: {
                            HStack(spacing: 12) {
                                Text(t.title).ct(16, .bold).foregroundStyle(C.ink).fixedSize()
                                Text(t.sub).ct(13).foregroundStyle(C.muted).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(C.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if groups == nil { Text("Загружаю список групп…").ct(13).foregroundStyle(C.muted) }
            BigButton(text: "Дальше", enabled: q.count >= 6, busy: checking, height: 52) { pick(q) }
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
    let onBack: () -> Void
    let onDone: (Int) -> Void
    @State private var sub = 0

    var body: some View {
        Screen(spacing: 14, top: 12, bottom: 32) {
            RoundButton(glyph: .back, label: "Назад", action: onBack)
            ScreenTitle("группа \(group) · шаг 2 из 2", "Подгруппа")
            Text("Лабораторные часто идут по подгруппам. Выбери свою — увидишь только свои пары. Если не знаешь, оставь «Все», поменять можно в настройках.")
                .ct(14, lh: 20).foregroundStyle(C.muted)
            Segmented(labels: ["Все", "1", "2"], selected: sub) { sub = $0 }
            BigButton(text: "Готово") { onDone(sub) }
        }
    }
}
