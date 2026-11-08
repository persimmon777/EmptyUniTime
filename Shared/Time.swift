import Foundation

/// Дата без времени и часового пояса (как java.time.LocalDate). Хранится числом дней от 1970-01-01.
struct LocalDate: Hashable, Comparable, Codable, CustomStringConvertible {
    let epochDay: Int

    init(epochDay: Int) { self.epochDay = epochDay }
    init(_ y: Int, _ m: Int, _ d: Int) { epochDay = LocalDate.daysFromCivil(y, m, d) }

    static func today() -> LocalDate { LocalDateTime(Date()).date }

    var ymd: (y: Int, m: Int, d: Int) { LocalDate.civilFromDays(epochDay) }
    var year: Int { ymd.y }
    var month: Int { ymd.m }
    var day: Int { ymd.d }

    /// 1 — понедельник … 7 — воскресенье.
    var weekday: Int {
        let w = (epochDay + 3) % 7
        return (w < 0 ? w + 7 : w) + 1
    }

    func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + n) }
    func plusWeeks(_ n: Int) -> LocalDate { plusDays(n * 7) }

    /// Понедельник этой недели.
    var monday: LocalDate { plusDays(-(weekday - 1)) }

    func days(to other: LocalDate) -> Int { other.epochDay - epochDay }

    func at(_ t: LocalTime) -> LocalDateTime { LocalDateTime(date: self, time: t) }
    var startOfDay: LocalDateTime { LocalDateTime(date: self, time: LocalTime(minutes: 0)) }

    static func < (a: LocalDate, b: LocalDate) -> Bool { a.epochDay < b.epochDay }

    /// ISO: 2026-10-23
    var description: String {
        let (y, m, d) = ymd
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// «dd.MM.yyyy» (как в API расписания) или ISO «yyyy-MM-dd…».
    static func parse(_ s: String?) -> LocalDate? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s != "null" else { return nil }
        let parts = s.prefix(10)
        if parts.count == 10 {
            let chars = Array(parts)
            if chars[2] == ".", chars[5] == ".",
               let d = Int(String(chars[0...1])), let m = Int(String(chars[3...4])), let y = Int(String(chars[6...9])),
               (1...12).contains(m), (1...31).contains(d) {
                return LocalDate(y, m, d)
            }
            if chars[4] == "-", chars[7] == "-",
               let y = Int(String(chars[0...3])), let m = Int(String(chars[5...6])), let d = Int(String(chars[8...9])),
               (1...12).contains(m), (1...31).contains(d) {
                return LocalDate(y, m, d)
            }
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { epochDay = n; return }
        let s = try c.decode(String.self)
        guard let d = LocalDate.parse(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(s)") }
        epochDay = d.epochDay
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    // Алгоритмы Говарда Хиннанта: гражданская дата ↔ число дней.
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (y: Int, m: Int, d: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

/// Время суток в минутах от полуночи.
struct LocalTime: Hashable, Comparable, Codable, CustomStringConvertible {
    let minutes: Int

    init(minutes: Int) { self.minutes = minutes }
    init(_ h: Int, _ m: Int) { minutes = h * 60 + m }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// «08:30»
    var description: String { String(format: "%02d:%02d", hour, minute) }

    static func parse(_ s: String?) -> LocalTime? {
        guard let s = s else { return nil }
        let p = s.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return LocalTime(h, m)
    }

    static func < (a: LocalTime, b: LocalTime) -> Bool { a.minutes < b.minutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { minutes = n; return }
        let s = try c.decode(String.self)
        guard let t = LocalTime.parse(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad time \(s)") }
        minutes = t.minutes
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// Дата и время без часового пояса. В Беларуси нет перехода на летнее время, поэтому сутки — всегда 1440 минут.
struct LocalDateTime: Hashable, Comparable, Codable, CustomStringConvertible {
    let date: LocalDate
    let time: LocalTime

    init(date: LocalDate, time: LocalTime) {
        self.date = date
        self.time = time
    }

    init(_ d: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        date = LocalDate(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
        time = LocalTime(c.hour ?? 0, c.minute ?? 0)
    }

    static func now() -> LocalDateTime { LocalDateTime(Date()) }

    /// Минуты от 1970-01-01 00:00 (без пояса) — для сравнения и разницы.
    var stamp: Int { date.epochDay * 1440 + time.minutes }

    init(stamp: Int) {
        let d = stamp >= 0 ? stamp / 1440 : (stamp - 1439) / 1440
        date = LocalDate(epochDay: d)
        time = LocalTime(minutes: stamp - d * 1440)
    }

    func plusMinutes(_ n: Int) -> LocalDateTime { LocalDateTime(stamp: stamp + n) }
    func plusDays(_ n: Int) -> LocalDateTime { LocalDateTime(date: date.plusDays(n), time: time) }

    func minutes(to other: LocalDateTime) -> Int { other.stamp - stamp }

    func isAfter(_ o: LocalDateTime) -> Bool { stamp > o.stamp }
    func isBefore(_ o: LocalDateTime) -> Bool { stamp < o.stamp }

    static func < (a: LocalDateTime, b: LocalDateTime) -> Bool { a.stamp < b.stamp }

    func toDate(calendar: Calendar = .current) -> Date {
        let (y, m, d) = date.ymd
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = time.hour; c.minute = time.minute
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: TimeInterval(stamp * 60))
    }

    /// ISO: 2026-10-23T08:30
    var description: String { "\(date)T\(time)" }

    static func parse(_ s: String) -> LocalDateTime? {
        let p = s.split(separator: "T")
        guard p.count == 2, let d = LocalDate.parse(String(p[0])), let t = LocalTime.parse(String(p[1])) else { return nil }
        return LocalDateTime(date: d, time: t)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = LocalDateTime.parse(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad datetime \(s)") }
        self = v
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

extension Int {
    /// Остаток, всегда неотрицательный (как Math.floorMod).
    func floorMod(_ m: Int) -> Int {
        let r = self % m
        return r < 0 ? r + m : r
    }
}
