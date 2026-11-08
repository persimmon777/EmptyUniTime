import Foundation
import CryptoKit
import Security

/// Личный кабинет iis.bsuir.by. Тот же API, что у сайта: вход по студбилету и паролю, дальше сессия в cookie.
/// Пароль уходит только на iis.bsuir.by; сохраняется он, только если включено «Запомнить пароль», — в Keychain.
final class Iis {
    static let shared = Iis()

    enum LoginResult {
        case ok
        /// Сайт просит что-то подтвердить у себя (код 280).
        case redirect(String)
        case failed(Int, String)
    }

    struct Response {
        let code: Int
        let body: Data
        var text: String { String(decoding: body, as: UTF8.self) }
        var json: JSON? { JSON.parse(body) }
        var ok: Bool { (200...299).contains(code) }
    }

    enum Kind: String, CaseIterable { case profile, markbook, performance, omissions, dean, dormitory, group, library, notifications, settings }

    /// Раздел кабинета как в меню сайта; некоторые собираются из нескольких запросов.
    struct Section: Hashable {
        let title: String
        let kind: Kind
        let paths: [String]
        let glyph: GlyphKind
    }

    static let SECTIONS: [Section] = [
        Section(title: "Профиль", kind: .profile, paths: ["/auth/user"], glyph: .user),
        Section(title: "Зачётка", kind: .markbook, paths: ["/markbook"], glyph: .doc),
        Section(title: "Успеваемость", kind: .performance, paths: ["/personal-rating"], glyph: .star),
        Section(title: "Пропуски", kind: .omissions, paths: ["/omissions-by-student", "/disrespectful-omissions-by-student"], glyph: .clock),
        Section(title: "Деканат", kind: .dean, paths: ["/certificate"], glyph: .cap),
        Section(title: "Общежитие", kind: .dormitory, paths: [
            "/dormitory-queue-application",
            "/dormitory-queue-application/privileges",
            "/dormitory-queue-application/premium-penalty",
        ], glyph: .pin),
        Section(title: "Группа", kind: .group, paths: ["/student-groups/user-group-info"], glyph: .people),
        Section(title: "Библиотека", kind: .library, paths: ["/library/books"], glyph: .calendar),
        Section(title: "Уведомления", kind: .notifications, paths: ["/notifications?pageNumber=1&pageSize=30"], glyph: .bell),
        Section(title: "Настройки", kind: .settings, paths: ["/settings/last-password-change", "/settings/password-attempts", "/settings/contacts"], glyph: .gear),
    ]

    static func section(_ kind: Kind) -> Section { SECTIONS.first { $0.kind == kind }! }

    private let d = Store.shared.defaults
    private let cacheDir: URL
    private let session: URLSession
    private let gate = ReloginGate()

    private init() {
        cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iis_cache")
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.urlCache = nil
        c.timeoutIntervalForRequest = 25
        session = URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }

    var loggedIn: Bool { (!cookies.isEmpty && d.bool(forKey: "iis.ok")) || hasSavedPassword }
    var login: String { d.string(forKey: "iis.login") ?? "" }
    var hasSavedPassword: Bool { Keychain.get("iis.password") != nil }

    func login(_ username: String, _ password: String, remember: Bool, savePassword: Bool) async throws -> LoginResult {
        // Другой аккаунт — чужие сохранённые ответы не показываем.
        if username != login { try? FileManager.default.removeItem(at: cacheDir) }
        cookies = [:]
        d.removeObject(forKey: "iis.ok")
        Keychain.delete("iis.password")
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password, "rememberDevice": remember])
        let r = try await request("POST", "/auth/login", body: body)
        switch r.code {
        case 200, 201, 204:
            d.set(true, forKey: "iis.ok")
            d.set(username, forKey: "iis.login")
            if savePassword { Keychain.set("iis.password", password) }
            return .ok
        case 280:
            return .redirect(r.json?.str("redirectUrl") ?? "")
        default:
            let o = r.json
            let ban = o?.str("banExpiration") ?? ""
            let msg: String
            if !ban.isBlank {
                msg = "Вход временно заблокирован до \(ban)"
            } else if r.code == 401 || r.code == 403 {
                let e = o?.str("error") ?? ""
                msg = (e.isBlank || e == "Unauthorized" || e == "Forbidden") ? "Неверный номер студенческого или пароль" : e
            } else {
                msg = "Ошибка сервера (\(r.code))"
            }
            return .failed(r.code, msg)
        }
    }

    func logout() async {
        _ = try? await request("GET", "/auth/logout")
        cookies = [:]
        d.removeObject(forKey: "iis.ok")
        d.removeObject(forKey: "iis.login")
        Keychain.delete("iis.password")
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func forgetPassword() { Keychain.delete("iis.password") }

    // MARK: Кэш ответов

    private func cacheFile(_ path: String) -> URL {
        let hash = Insecure.SHA1.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hash).json")
    }

    /// Сохранённый ответ и когда он получен, если есть.
    func cached(_ path: String) -> (Response, Date)? {
        let f = cacheFile(path)
        guard let data = try? Data(contentsOf: f) else { return nil }
        let date = (try? FileManager.default.attributesOfItem(atPath: f.path)[.modificationDate] as? Date) ?? Date.distantPast
        return (Response(code: 200, body: data), date)
    }

    /// Подгрузить разделы заранее, если сохранённое старше `maxAge`.
    func prefetch(_ paths: [String], maxAge: TimeInterval = 120) async {
        await withTaskGroup(of: Void.self) { g in
            for p in paths {
                let age = cached(p).map { Date().timeIntervalSince($0.1) } ?? .infinity
                if age > maxAge { g.addTask { _ = try? await self.get(p) } }
            }
        }
    }

    /// GET к API кабинета. 401/403 — сессия кончилась: если пароль сохранён, входим заново и повторяем.
    func get(_ path: String) async throws -> Response {
        let r = try await fetch(path)
        if r.ok {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? r.body.write(to: cacheFile(path), options: .atomic)
        }
        return r
    }

    private func fetch(_ path: String) async throws -> Response {
        let r = try await request("GET", path)
        if r.code != 401 && r.code != 403 { return r }
        // Перезаход один на всех: параллельные запросы ждут его и повторяют уже с новой сессией.
        return try await gate.run {
            let retry = try await self.request("GET", path)
            if retry.code != 401 && retry.code != 403 { return retry }
            self.d.set(false, forKey: "iis.ok")
            guard let pw = Keychain.get("iis.password") else { return r }
            let again = try await self.login(self.login, pw, remember: true, savePassword: true)
            if case .ok = again { return try await self.request("GET", path) }
            return r
        }
    }

    // MARK: Cookie и запросы

    private var cookies: [String: String] {
        get { (d.dictionary(forKey: "iis.cookies") as? [String: String]) ?? [:] }
        set { d.set(newValue, forKey: "iis.cookies") }
    }

    private func saveCookies(_ resp: HTTPURLResponse, url: URL) {
        var headers = [String: String]()
        for (k, v) in resp.allHeaderFields {
            if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
        }
        let list = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        guard !list.isEmpty else { return }
        var jar = cookies
        for c in list {
            if c.value.isEmpty || (c.expiresDate.map { $0 < Date() } ?? false) { jar[c.name] = nil } else { jar[c.name] = c.value }
        }
        cookies = jar
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Response {
        guard let url = URL(string: "\(Store.API)\(path)") else { throw Net.Failure.message("Плохой адрес") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let jar = cookies
        if !jar.isEmpty { req.setValue(jar.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie") }
        if let xsrf = jar["XSRF-TOKEN"] { req.setValue(xsrf, forHTTPHeaderField: "X-XSRF-TOKEN") }
        if let body = body {
            req.httpBody = body
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Net.Failure.message("Нет ответа") }
        saveCookies(http, url: url)
        return Response(code: http.statusCode, body: data)
    }
}

/// Не ходим по редиректам: сайт отвечает 302 на страницу входа, а нам нужен сам код.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Выполняет перезаход по одному: остальные ждут результата.
private actor ReloginGate {
    private var running: Task<Iis.Response, Error>?

    func run(_ work: @escaping () async throws -> Iis.Response) async throws -> Iis.Response {
        if let t = running { return try await t.value }
        let t = Task { try await work() }
        running = t
        defer { running = nil }
        return try await t.value
    }
}

/// Пароль IIS — в связке ключей, доступен после первой разблокировки (нужно фоновым проверкам).
enum Keychain {
    private static let service = "unitime.iis"

    static func set(_ key: String, _ value: String) {
        delete(key)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
