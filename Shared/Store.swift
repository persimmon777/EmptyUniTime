import Foundation

/// Общее хранилище приложения и виджетов: настройки, кэш расписания, дедлайны, друзья, избранное.
/// Лежит в App Group, чтобы виджеты видели то же, что и приложение.
final class Store {
    static let shared = Store()

    static let API = "https://iis.bsuir.by/api/v1"
    static let defaultGroupId = "group.com.unitime.ios"

    let defaults: UserDefaults
    /// Папка для файлов (кэш расписания, справочники).
    let dir: URL
    /// Удалось ли подключиться к общему контейнеру App Group (без него виджеты не видят данные).
    let shared: Bool

    private init() {
        let (id, url) = Store.findGroup()
        if let id = id, let url = url {
            defaults = UserDefaults(suiteName: id) ?? .standard
            dir = url
            shared = true
        } else {
            defaults = .standard
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            shared = false
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Ищем App Group: при установке через iLoader/AltStore/SideStore к идентификаторам добавляется Team ID,
    /// поэтому пробуем несколько вариантов и берём тот, что реально доступен.
    private static func findGroup() -> (String?, URL?) {
        var candidates = [String]()
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { candidates += alt }
        if let id = Bundle.main.bundleIdentifier {
            // У виджета идентификатор «<app>.widgets» — группа строится от приложения.
            let base = id.hasSuffix(".widgets") ? String(id.dropLast(".widgets".count)) : id
            candidates.append("group.\(base)")
        }
        if let own = Bundle.main.object(forInfoDictionaryKey: "UniTimeAppGroup") as? String { candidates.append(own) }
        candidates.append(defaultGroupId)
        for c in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: c) {
                return (c, url)
            }
        }
        return (nil, nil)
    }

    // MARK: Группа

    var group: String {
        get { defaults.string(forKey: "group") ?? defaults.string(forKey: "cachedGroup") ?? "" }
        set { defaults.set(newValue, forKey: "group") }
    }

    /// 0 — все подгруппы, 1 или 2 — только своя.
    var subgroup: Int {
        get { defaults.integer(forKey: "subgroup") }
        set { defaults.set(newValue, forKey: "subgroup") }
    }

    var lastFetch: Date? {
        let t = defaults.double(forKey: "fetchedAt")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    private var cacheFile: URL { dir.appendingPathComponent("schedule.json") }
    private var cachedGroup: String? { defaults.string(forKey: "cachedGroup") }

    var hasCache: Bool { FileManager.default.fileExists(atPath: cacheFile.path) && cachedGroup != nil }

    func isStale() -> Bool {
        guard let last = lastFetch else { return true }
        return Date().timeIntervalSince(last) > 12 * 3600 || cachedGroup != group
    }

    /// Скрытые пары: ключ пары или "S:<предмет>".
    var hidden: Set<String> {
        get { Set(defaults.stringArray(forKey: "hidden") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "hidden") }
    }

    // MARK: Расписание

    /// Скачать своё расписание. Возвращает описания изменений по сравнению с прошлой версией.
    @discardableResult
    func fetch() async throws -> [String] {
        let g = group
        let json = try await Net.get(scheduleUrl(.group(g)))
        let week = try await currentWeek()
        let monday = LocalDate.today().monday
        let fresh = try Schedule.parse(json, anchorMonday: monday, anchorWeek: week) // проверяем, что ответ разбирается
        var old: Schedule?
        if cachedGroup == g, let data = try? Data(contentsOf: cacheFile) {
            old = try? Schedule.parse(data, anchorMonday: monday, anchorWeek: week)
        }
        try json.write(to: cacheFile, options: .atomic)
        defaults.set(monday.epochDay, forKey: "anchorMonday")
        defaults.set(week, forKey: "anchorWeek")
        defaults.set(g, forKey: "cachedGroup")
        defaults.set(Date().timeIntervalSince1970, forKey: "fetchedAt")
        guard let previous = old else { return [] }
        let a = previous.signatures()
        let b = fresh.signatures()
        func describe(_ l: Lesson) -> String {
            let day = l.day.map { DAY_SHORT[$0 - 1] } ?? l.exactDate.map { "\($0.day) \(month($0))" } ?? ""
            return "\(day) \(l.start) \(l.subject) \(l.type) \(l.rooms)".trimmingCharacters(in: .whitespaces)
        }
        let added = b.keys.filter { a[$0] == nil }.sorted().map { "+ " + describe(b[$0]!) }
        let removed = a.keys.filter { b[$0] == nil }.sorted().map { "− " + describe(a[$0]!) }
        return added + removed
    }

    func load() -> Schedule? {
        guard cachedGroup == group, let a = anchor(), let data = try? Data(contentsOf: cacheFile) else { return nil }
        let s = try? Schedule.parse(data, anchorMonday: a.0, anchorWeek: a.1)
        s?.hidden = hidden
        return s
    }

    private func anchor() -> (LocalDate, Int)? {
        guard defaults.object(forKey: "anchorMonday") != nil else { return nil }
        let week = defaults.integer(forKey: "anchorWeek")
        return (LocalDate(epochDay: defaults.integer(forKey: "anchorMonday")), week == 0 ? 1 : week)
    }

    private func currentWeek() async throws -> Int {
        let data = try await Net.get("\(Store.API)/schedule/current-week")
        guard let w = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Net.Failure.message("Не удалось узнать номер недели")
        }
        return w
    }

    /// Чужое расписание (группа или преподаватель) — по сети, без кэша.
    func fetchOther(_ t: Target) async throws -> Schedule {
        let json = try await Net.get(scheduleUrl(t))
        if let a = anchor() { return try Schedule.parse(json, anchorMonday: a.0, anchorWeek: a.1) }
        let week = try await currentWeek()
        return try Schedule.parse(json, anchorMonday: LocalDate.today().monday, anchorWeek: week)
    }

    private func scheduleUrl(_ t: Target) -> String {
        t.isGroup ? "\(Store.API)/schedule?studentGroup=\(Net.enc(t.id))" : "\(Store.API)/employees/schedule/\(Net.enc(t.id))"
    }

    // MARK: Заметки и напоминания

    func note(_ key: String) -> String { (defaults.dictionary(forKey: "notes") as? [String: String])?[key] ?? "" }

    func setNote(_ key: String, _ text: String) {
        var d = (defaults.dictionary(forKey: "notes") as? [String: String]) ?? [:]
        d[key] = text.isEmpty ? nil : text
        defaults.set(d, forKey: "notes")
    }

    var reminders: Set<String> {
        get { Set(defaults.stringArray(forKey: "reminders") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "reminders") }
    }

    func setReminder(_ key: String, _ on: Bool) {
        var s = reminders
        if on { s.insert(key) } else { s.remove(key) }
        reminders = s
    }

    // MARK: Дедлайны, друзья, избранное

    private func decode<T: Decodable>(_ key: String, _ def: T) -> T {
        guard let data = defaults.data(forKey: key), let v = try? JSONDecoder().decode(T.self, from: data) else { return def }
        return v
    }

    private func encode<T: Encodable>(_ key: String, _ v: T) {
        if let data = try? JSONEncoder().encode(v) { defaults.set(data, forKey: key) }
    }

    func deadlines() -> [Deadline] { decode("deadlines", [Deadline]()).sorted { $0.due < $1.due } }
    func saveDeadline(_ d: Deadline) { encode("deadlines", deadlines().filter { $0.id != d.id } + [d]) }
    func deleteDeadline(_ id: Int64) { encode("deadlines", deadlines().filter { $0.id != id }) }

    func friends() -> [Friend] { decode("friends", [Friend]()) }
    func saveFriends(_ list: [Friend]) { encode("friends", list) }

    func favorites() -> [Target] { decode("favorites", [Target]()) }
    func recents() -> [Target] { decode("recents", [Target]()) }

    func isFavorite(_ t: Target) -> Bool { favorites().contains { $0.kind == t.kind && $0.id == t.id } }

    func toggleFavorite(_ t: Target) {
        let all = favorites()
        let rest = all.filter { !($0.kind == t.kind && $0.id == t.id) }
        encode("favorites", rest.count == all.count ? rest + [t] : rest)
    }

    func addRecent(_ t: Target) {
        encode("recents", Array(([t] + recents().filter { !($0.kind == t.kind && $0.id == t.id) }).prefix(8)))
    }

    // MARK: Справочники для поиска (кэш на неделю)

    func allGroups() async throws -> [Target] {
        let root = try await cached("groups.json", "\(Store.API)/student-groups")
        return listIn(root).map { o in
            let name = o.opt("name") ?? ""
            let course = o.int("course")
            let sub = [o.opt("facultyAbbrev") ?? "", o.opt("specialityAbbrev") ?? "", course > 0 ? "\(course) курс" : ""]
                .filter { !$0.isBlank }.joined(separator: ", ")
            return Target(kind: "group", id: name, title: name, sub: sub)
        }
    }

    func allTeachers() async throws -> [Target] {
        let root = try await cached("teachers.json", "\(Store.API)/employees/all")
        return listIn(root).map { o in
            let t = Schedule.teacher(o)
            let deps = (o["academicDepartment"]?.items ?? []).compactMap { $0.primitiveString }.joined(separator: ", ")
            let sub = [t.rank, deps].filter { !$0.isBlank }.joined(separator: " · ")
            return Target(kind: "teacher", id: t.urlId, title: t.full, sub: sub)
        }
    }

    private func cached(_ name: String, _ url: String) async throws -> JSON {
        let f = dir.appendingPathComponent(name)
        let attrs = try? FileManager.default.attributesOfItem(atPath: f.path)
        if let m = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 7 * 86400,
           let data = try? Data(contentsOf: f), let j = JSON.parse(data) {
            return j
        }
        do {
            let data = try await Net.get(url)
            guard let j = JSON.parse(data) else { throw Net.Failure.message("Не удалось разобрать ответ") }
            try? data.write(to: f, options: .atomic)
            return j
        } catch {
            if let data = try? Data(contentsOf: f), let j = JSON.parse(data) { return j }
            throw error
        }
    }
}

/// Простые HTTP-запросы к открытому API.
enum Net {
    enum Failure: LocalizedError {
        case http(Int)
        case message(String)
        var errorDescription: String? {
            switch self {
            case .http(let c): return "HTTP \(c)"
            case .message(let m): return m
            }
        }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 40
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func get(_ url: String) async throws -> Data {
        guard let u = URL(string: url) else { throw Failure.message("Плохой адрес") }
        let (data, resp) = try await session.data(from: u)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code) }
        return data
    }

    static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
