import Foundation

/// Фоновая проверка кабинета IIS: сравнивает снимок с прошлым и уведомляет о новом.
/// Первая проверка только запоминает состояние, чтобы не засыпать старыми оценками.
enum IisWatch {
    private static var d: UserDefaults { Store.shared.defaults }

    // MARK: Снимки: ключ записи → её значение

    static func markbook(_ v: JSON?) -> [String: String] {
        guard let pages = v?["markPages"]?.fields else { return [:] }
        var out = [String: String]()
        for (sem, page) in pages {
            for m in listIn(page, "marks") {
                let mark = m.str("mark")
                if !mark.isBlank { out["\(sem)|\(m.str("subject", "fullSubject"))|\(m.str("formOfControl"))"] = mark }
            }
        }
        return out
    }

    /// Отметки из журнала: «предмет|дата|отметка|№», чтобы две одинаковые в один день не слились.
    static func journal(_ v: JSON?) -> [String: String] {
        let subjects = listIn(v?["personalRating"] ?? v, "subjects", "disciplines", "personalRating")
        var out = [String: String]()
        for s in subjects {
            let name = s.str("name", "discipline", "subject", "abbrev")
            var marks = [(String, String)]()
            collect(s, &marks)
            var seen = [String: Int]()
            for (m, date) in marks {
                let k = "\(m)|\(date)"
                let i = seen[k, default: 0]
                seen[k] = i + 1
                out["\(name)|\(date)|\(m)|\(i)"] = m
            }
        }
        return out
    }

    private static func collect(_ v: JSON, _ out: inout [(String, String)]) {
        if let f = v.fields {
            if v.has("mark") {
                let m = v.str("mark")
                if !m.isBlank && m.count <= 3 { out.append((m, v.str("date", "dateString"))) }
            }
            for (k, child) in f where k != "deadlines" { collect(child, &out) }
        } else if let a = v.items {
            for x in a { collect(x, &out) }
        }
    }

    static func omissions(_ v: JSON?) -> [String: String] {
        var out = [String: String]()
        for o in listIn(v, "omissions", "omissionDtoList") {
            out["\(o.str("date", "dateFrom"))|\(o.str("subject"))|\(o.str("lessonTypeAbbrev"))|\(o.str("hours"))"] = o.str("hours")
        }
        return out
    }

    static func messages(_ v: JSON?) -> [String: String] {
        var out = [String: String]()
        for n in listIn(v, "notifications") {
            let id = n.str("id")
            let key = id.isBlank ? "\(n.str("date", "createdDate"))|\(n.str("title", "message").prefix(40))" : id
            let title = n.str("title", "subject", "header")
            out[key] = title.isBlank ? String(n.str("message", "text").prefix(80)) : title
        }
        return out
    }

    static func penalties(_ v: JSON?) -> [String: String] {
        var out = [String: String]()
        for o in listIn(v) {
            out["\(o.str("date"))|\(o.str("eventTypeName"))|\(o.str("reason"))"] =
                "\(o.str("eventTypeName")): \(o.str("reason"))".trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        }
        return out
    }

    /// Что появилось или изменилось.
    static func diff(_ old: [String: String]?, _ new: [String: String]) -> [(String, String)] {
        guard let old = old else { return [] }
        return new.filter { old[$0.key] != $0.value }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: Проверка

    static var lastCheck: Date? {
        let t = d.double(forKey: "iisw.lastCheck")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Проверить кабинет. Возвращает найденное новое; nil — нет связи или не выполнен вход.
    @discardableResult
    static func check(notify: Bool = true) async -> [String]? {
        let st = AppSettings.shared
        let iis = Iis.shared
        guard iis.loggedIn else { return nil }
        var found = [String]()
        var anyOk = false

        func run(_ key: String, _ enabled: Bool, _ path: String, _ snap: (JSON?) -> [String: String], _ text: (String, String) -> String) async {
            guard enabled, let r = try? await iis.get(path), r.ok, let parsed = r.json else { return }
            anyOk = true
            let now = snap(parsed)
            let old = d.dictionary(forKey: "iisw.\(key)") as? [String: String]
            for (k, v) in diff(old, now) { found.append(text(k, v)) }
            d.set(now, forKey: "iisw.\(key)")
        }

        func part(_ k: String, _ i: Int) -> String {
            let p = k.split(separator: "|", omittingEmptySubsequences: false)
            return i < p.count ? String(p[i]) : ""
        }

        await run("markbook", st.iisMarks, "/markbook", markbook) { k, v in "Зачётка: \(part(k, 1)) — \(v)" }
        await run("journal", st.iisMarks, "/personal-rating", journal) { k, v in "Новая отметка: \(part(k, 0)) — \(v)" }
        await run("omissions", st.iisOmissions, "/disrespectful-omissions-by-student", omissions) { k, v in
            "Новый пропуск: \(part(k, 1)) \(part(k, 2)), \(v) ч".replacingOccurrences(of: "  ", with: " ")
        }
        await run("messages", st.iisMessages, "/notifications?pageNumber=1&pageSize=30", messages) { _, v in "Сообщение из IIS: \(v)" }
        await run("penalties", st.iisPenalties, "/dormitory-queue-application/premium-penalty", penalties) { _, v in v }

        guard anyOk else { return nil }
        d.set(Date().timeIntervalSince1970, forKey: "iisw.lastCheck")
        if notify && !found.isEmpty {
            let title = found.count == 1 ? found[0] : "Новое в IIS: \(found.count)"
            let body = found.count == 1 ? "Открыть личный кабинет"
                : found.prefix(8).joined(separator: "\n") + (found.count > 8 ? "\nи ещё \(found.count - 8)" : "")
            Notifications.post(title: title, body: body, id: "iis.\(Int(Date().timeIntervalSince1970))")
        }
        return found
    }

    /// Пора ли проверять снова (по настройке «каждые N часов»). Ночью (0:00–7:00) не проверяем.
    static func due() -> Bool {
        let st = AppSettings.shared
        guard st.iisNotify, Iis.shared.loggedIn else { return false }
        if Calendar.current.component(.hour, from: Date()) < 7 { return false }
        guard let last = lastCheck else { return true }
        return Date().timeIntervalSince(last) >= Double(st.iisHours) * 3600 - 300
    }

    /// Забыть снимки — после выхода из аккаунта следующий вход начнёт с чистого листа.
    static func reset() {
        for k in ["markbook", "journal", "omissions", "messages", "penalties", "lastCheck"] { d.removeObject(forKey: "iisw.\(k)") }
    }
}
