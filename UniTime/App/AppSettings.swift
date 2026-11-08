import SwiftUI

/// Пользовательские настройки. Хранятся в общем UserDefaults (App Group), чтобы фоновые задачи и виджеты видели их.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = Store.shared.defaults

    static let REMIND_OPTIONS = [5, 10, 15, 30]
    static let IIS_HOURS = [1, 2, 4, 8, 12]

    private func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
    private func i(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }

    /// Первый запуск пройден (выбрана группа).
    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }
    /// Секретная тема открыта комбинацией недель.
    @Published var neonUnlocked: Bool { didSet { d.set(neonUnlocked, forKey: "neonUnlocked") } }
    /// 0 — как в системе, 1 — светлая, 3 — чёрная, 4 — «Неон».
    @Published var theme: Int { didSet { d.set(theme, forKey: "theme") } }
    /// Стиль: 0 — обычный, 1 — стекло, 2 — цвет занятия.
    @Published var style: Int { didSet { d.set(style, forKey: "style") } }
    @Published var accent: Int { didSet { d.set(accent, forKey: "accent") } }
    @Published var shortNames: Bool { didSet { d.set(shortNames, forKey: "shortNames") } }
    @Published var pairNumbers: Bool { didSet { d.set(pairNumbers, forKey: "pairNumbers") } }
    @Published var startTab: Int { didSet { d.set(startTab, forKey: "startTab") } }

    /// Live Activity с текущей/следующей парой на экране блокировки.
    @Published var liveActivity: Bool { didSet { d.set(liveActivity, forKey: "liveActivity") } }
    /// Прятать Live Activity, когда сегодня пар больше нет.
    @Published var hideAfterLast: Bool { didSet { d.set(hideAfterLast, forKey: "hideAfterLast") } }
    @Published var notifRoom: Bool { didSet { d.set(notifRoom, forKey: "notifRoom") } }
    @Published var notifTeacher: Bool { didSet { d.set(notifTeacher, forKey: "notifTeacher") } }
    @Published var remindMinutes: Int { didSet { d.set(remindMinutes, forKey: "remindMinutes") } }
    @Published var remindSound: Bool { didSet { d.set(remindSound, forKey: "remindSound") } }
    @Published var notifyChanges: Bool { didSet { d.set(notifyChanges, forKey: "notifyChanges") } }

    @Published var iisNotify: Bool { didSet { d.set(iisNotify, forKey: "iisNotify") } }
    @Published var iisHours: Int { didSet { d.set(iisHours, forKey: "iisHours") } }
    @Published var iisMarks: Bool { didSet { d.set(iisMarks, forKey: "iisMarks") } }
    @Published var iisOmissions: Bool { didSet { d.set(iisOmissions, forKey: "iisOmissions") } }
    @Published var iisMessages: Bool { didSet { d.set(iisMessages, forKey: "iisMessages") } }
    @Published var iisPenalties: Bool { didSet { d.set(iisPenalties, forKey: "iisPenalties") } }

    @Published var updateCheck: Bool { didSet { d.set(updateCheck, forKey: "updateCheck") } }

    /// Скрытые пары живут в Store (их читают и виджеты); здесь — для перерисовки экранов.
    @Published var hidden: Set<String> { didSet { Store.shared.hidden = hidden } }

    private init() {
        onboarded = false
        neonUnlocked = false
        theme = 0; style = 0; accent = 0
        shortNames = true; pairNumbers = true; startTab = 0
        liveActivity = true; hideAfterLast = false; notifRoom = true; notifTeacher = true
        remindMinutes = 10; remindSound = true; notifyChanges = true
        iisNotify = true; iisHours = 4; iisMarks = true; iisOmissions = true; iisMessages = true; iisPenalties = true
        updateCheck = true
        hidden = Store.shared.hidden
        // didSet в init не срабатывает — читаем сохранённое после значений по умолчанию.
        onboarded = b("onboarded", false)
        neonUnlocked = b("neonUnlocked", false)
        theme = i("theme", 0)
        style = i("style", 0)
        accent = i("accent", 0)
        shortNames = b("shortNames", true)
        pairNumbers = b("pairNumbers", true)
        startTab = i("startTab", 0)
        liveActivity = b("liveActivity", true)
        hideAfterLast = b("hideAfterLast", false)
        notifRoom = b("notifRoom", true)
        notifTeacher = b("notifTeacher", true)
        remindMinutes = i("remindMinutes", 10)
        remindSound = b("remindSound", true)
        notifyChanges = b("notifyChanges", true)
        iisNotify = b("iisNotify", true)
        iisHours = i("iisHours", 4)
        iisMarks = b("iisMarks", true)
        iisOmissions = b("iisOmissions", true)
        iisMessages = b("iisMessages", true)
        iisPenalties = b("iisPenalties", true)
        updateCheck = b("updateCheck", true)
    }

    func look(systemDark: Bool) -> Look {
        let palette: Palette
        switch theme {
        case 1: palette = .light
        case 4: palette = .neon
        case 2, 3: palette = .black
        default: palette = systemDark ? .black : .light
        }
        return Look(p: palette, accentIndex: min(max(accent, 0), ACCENTS.count - 1), shortNames: shortNames,
                    pairNumbers: pairNumbers, style: LookStyle(rawValue: style) ?? .classic)
    }
}
