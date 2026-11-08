import Foundation

struct Teacher: Hashable, Codable {
    let id: Int
    let urlId: String
    let lastName: String
    let firstName: String
    let middleName: String
    let degree: String
    let rank: String

    var short: String { "\(lastName) \(firstName.prefix(1)). \(middleName.prefix(1)).".trimmingCharacters(in: .whitespaces) }
    var full: String { "\(lastName) \(firstName) \(middleName)".trimmingCharacters(in: .whitespaces) }
    var initials: String { "\(firstName.prefix(1))\(lastName.prefix(1))" }
    var photoUrl: String { "https://iis.bsuir.by/api/v1/employees/photo/\(id)" }
    var title: String { [degree, rank].filter { !$0.isBlank }.joined(separator: ", ") }
}

let DAY_KEYS = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]

struct Lesson: Hashable {
    /// 1 — понедельник … 7 — воскресенье; nil у экзаменов.
    let day: Int?
    let start: LocalTime
    let end: LocalTime
    let subject: String
    let subjectFull: String
    let type: String
    let rooms: String
    let teachers: [Teacher]
    let groups: String
    let weeks: Set<Int>
    let subgroup: Int
    let from: LocalDate?
    let to: LocalDate?
    let exactDate: LocalDate?
    /// Примечание из расписания БГУИР: перенос, «только 14.12», «будет лк по …».
    let note: String

    var teacher: String { teachers.map { $0.short }.joined(separator: ", ") }

    /// Ключ для заметок и напоминаний: одна и та же пара каждую неделю.
    var key: String { "\(subject)|\(type)|\(subgroup)|\(day.map { DAY_KEYS[$0 - 1] } ?? "null")|\(start)" }

    var fullTitle: String { subjectFull.isBlank ? subject : subjectFull }
}

/// Пара, привязанная к конкретной дате.
struct Occurrence: Hashable {
    let date: LocalDate
    let lesson: Lesson
    var startAt: LocalDateTime { date.at(lesson.start) }
    var endAt: LocalDateTime { date.at(lesson.end) }
}

final class Schedule {
    private let lessons: [Lesson]
    let exams: [Occurrence]
    /// Понедельник недели, номер которой известен из API, и сам номер (1..4).
    private let anchorMonday: LocalDate
    private let anchorWeek: Int
    let termStart: LocalDate?
    let termEnd: LocalDate?
    let examsStart: LocalDate?
    let examsEnd: LocalDate?
    let title: String

    /// Скрытые пары: ключ `Lesson.key` или "S:<предмет>" для всего предмета.
    var hidden: Set<String> = []

    init(lessons: [Lesson], exams: [Occurrence], anchorMonday: LocalDate, anchorWeek: Int,
         termStart: LocalDate?, termEnd: LocalDate?, examsStart: LocalDate?, examsEnd: LocalDate?, title: String) {
        self.lessons = lessons
        self.exams = exams
        self.anchorMonday = anchorMonday
        self.anchorWeek = anchorWeek
        self.termStart = termStart
        self.termEnd = termEnd
        self.examsStart = examsStart
        self.examsEnd = examsEnd
        self.title = title
    }

    func isHidden(_ l: Lesson) -> Bool { hidden.contains(l.key) || hidden.contains("S:\(l.subject)") }

    /// Отпечатки всех пар — для сравнения старого и нового расписания.
    func signatures() -> [String: Lesson] {
        var out = [String: Lesson]()
        for l in lessons {
            let k = "\(l.day.map { DAY_KEYS[$0 - 1] } ?? "null")|\(l.start)|\(l.subject)|\(l.type)|\(l.rooms)|\(l.weeks.sorted())|\(l.subgroup)|\(l.exactDate.map { $0.description } ?? "null")"
            out[k] = l
        }
        return out
    }

    /// Предметы для выбора: короткое → полное название.
    func subjects() -> [(short: String, full: String)] {
        var seen = Set<String>()
        var out = [(short: String, full: String)]()
        for l in lessons where !seen.contains(l.subject) {
            seen.insert(l.subject)
            out.append((l.subject, l.subjectFull.isBlank ? l.subject : l.subjectFull))
        }
        return out.sorted { $0.full < $1.full }
    }

    /// Ближайшая пара по предмету после `now`.
    func nextOf(_ subject: String, now: LocalDateTime, subgroup: Int) -> Occurrence? {
        for i in 0...60 {
            for o in lessonsOn(now.date.plusDays(i), subgroup: subgroup) where o.lesson.subject == subject && o.startAt.isAfter(now) {
                return o
            }
        }
        return nil
    }

    func weekNumber(_ date: LocalDate) -> Int {
        let diff = anchorMonday.days(to: date.monday) / 7
        return (anchorWeek - 1 + diff).floorMod(4) + 1
    }

    /// Оставшиеся пары одного предмета, по типам: «ЛК», «ПЗ», «ЛР»…
    struct SubjectLeft {
        let lesson: Lesson
        let byType: [(type: String, list: [Occurrence])]
        var total: Int { byType.reduce(0) { $0 + $1.list.count } }
        var first: LocalDateTime { byType.compactMap { $0.list.first?.startAt }.min()! }
    }

    /// Пары, которые ещё не закончились к `now`, до конца семестра (или 150 дней), по предметам и типам.
    func remaining(now: LocalDateTime, subgroup: Int) -> [SubjectLeft] {
        let today = now.date
        let end = (termEnd.flatMap { $0 >= today ? $0 : nil }) ?? today.plusDays(150)
        let order = ["ЛК", "ПЗ", "ЛР"]
        var bySubject = [(String, [Occurrence])]()
        var index = [String: Int]()
        var d = today
        while d <= end {
            for o in lessonsOn(d, subgroup: subgroup) where o.endAt.isAfter(now) && !o.lesson.type.isBlank {
                if let i = index[o.lesson.subject] {
                    bySubject[i].1.append(o)
                } else {
                    index[o.lesson.subject] = bySubject.count
                    bySubject.append((o.lesson.subject, [o]))
                }
            }
            d = d.plusDays(1)
        }
        func rank(_ t: String) -> Int { order.firstIndex(of: t) ?? order.count }
        return bySubject.map { (_, list) -> SubjectLeft in
            var types = [(type: String, list: [Occurrence])]()
            for o in list {
                if let i = types.firstIndex(where: { $0.type == o.lesson.type }) {
                    types[i].list.append(o)
                } else {
                    types.append((o.lesson.type, [o]))
                }
            }
            // Стабильная сортировка: ЛК, ПЗ, ЛР, потом остальные в порядке появления.
            let sorted = types.enumerated().sorted { a, b in
                rank(a.element.type) != rank(b.element.type) ? rank(a.element.type) < rank(b.element.type) : a.offset < b.offset
            }.map { $0.element }
            return SubjectLeft(lesson: list[0].lesson, byType: sorted)
        }.sorted { $0.first < $1.first }
    }

    func lessonsOn(_ date: LocalDate, subgroup: Int) -> [Occurrence] {
        let week = weekNumber(date)
        let wd = date.weekday
        return lessons.filter { l in
            if let exact = l.exactDate { return exact == date && subgroupOk(l, subgroup) }
            return l.day == wd &&
                (l.weeks.isEmpty || l.weeks.contains(week)) &&
                (l.from == nil || date >= l.from!) &&
                (l.to == nil || date <= l.to!) &&
                subgroupOk(l, subgroup)
        }
        .filter { !isHidden($0) }
        .enumerated().sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }
        .map { Occurrence(date: date, lesson: $0.element) }
    }

    private func subgroupOk(_ l: Lesson, _ subgroup: Int) -> Bool {
        subgroup == 0 || l.subgroup == 0 || l.subgroup == subgroup
    }

    func upcoming(now: LocalDateTime, subgroup: Int, count: Int) -> [Occurrence] {
        var out = [Occurrence]()
        for i in 0...21 {
            for o in lessonsOn(now.date.plusDays(i), subgroup: subgroup) where o.endAt.isAfter(now) {
                out.append(o)
                if out.count >= count { return out }
            }
        }
        return out
    }

    /// Текущая пара (если идёт) и следующая после неё.
    func currentAndNext(now: LocalDateTime, subgroup: Int) -> (Occurrence?, Occurrence?) {
        let list = upcoming(now: now, subgroup: subgroup, count: 3)
        let current = list.first { !$0.startAt.isAfter(now) }
        let next = list.first { $0.startAt.isAfter(now) }
        return (current, next)
    }

    /// Ближайший момент, когда «текущая/следующая пара» поменяется.
    func nextChange(now: LocalDateTime, subgroup: Int) -> LocalDateTime {
        let midnight = now.date.plusDays(1).startOfDay
        let (cur, next) = currentAndNext(now: now, subgroup: subgroup)
        let candidates = [cur?.endAt, next?.startAt, midnight].compactMap { $0 }.filter { $0.isAfter(now) }
        return candidates.min() ?? midnight
    }

    // MARK: Разбор ответа iis.bsuir.by

    private static let DAYS: [String: Int] = [
        "Понедельник": 1, "Вторник": 2, "Среда": 3, "Четверг": 4,
        "Пятница": 5, "Суббота": 6, "Воскресенье": 7,
    ]

    enum ParseError: Error { case badJSON }

    static func parse(_ data: Data, anchorMonday: LocalDate, anchorWeek: Int) throws -> Schedule {
        guard let root = JSON.parse(data), root.isObject else { throw ParseError.badJSON }
        var lessons = [Lesson]()
        if let schedules = root["schedules"]?.fields {
            for (dayName, arr) in schedules {
                guard let day = DAYS[dayName] else { continue }
                for o in arr.objects {
                    if let l = parseLesson(o, day: day) { lessons.append(l) }
                }
            }
        }
        let exams = (root["exams"]?.objects ?? []).compactMap { o -> Occurrence? in
            guard let l = parseLesson(o, day: nil), let d = l.exactDate else { return nil }
            return Occurrence(date: d, lesson: l)
        }.sorted { $0.startAt < $1.startAt }
        var title = ""
        if let g = root["studentGroupDto"], g.isObject { title = g.opt("name") ?? "" }
        else if let e = root["employeeDto"], e.isObject { title = teacher(e).short }
        return Schedule(
            lessons: lessons, exams: exams, anchorMonday: anchorMonday, anchorWeek: anchorWeek,
            termStart: LocalDate.parse(root.opt("startDate")), termEnd: LocalDate.parse(root.opt("endDate")),
            examsStart: LocalDate.parse(root.opt("startExamsDate")), examsEnd: LocalDate.parse(root.opt("endExamsDate")),
            title: title
        )
    }

    static func teacher(_ e: JSON) -> Teacher {
        Teacher(
            id: e.int("id"),
            urlId: e.opt("urlId") ?? "",
            lastName: e.opt("lastName") ?? "",
            firstName: e.opt("firstName") ?? "",
            middleName: e.opt("middleName") ?? "",
            degree: e.opt("degreeAbbrev") ?? e.opt("degree") ?? "",
            rank: e.opt("rank") ?? ""
        )
    }

    private static func parseLesson(_ o: JSON, day: Int?) -> Lesson? {
        guard let start = LocalTime.parse(o.opt("startLessonTime")), let end = LocalTime.parse(o.opt("endLessonTime")) else { return nil }
        let subject = o.opt("subject")
        return Lesson(
            day: day,
            start: start,
            end: end,
            subject: subject ?? o.opt("note") ?? "Мероприятие",
            subjectFull: o.opt("subjectFullName") ?? subject ?? "",
            type: o.opt("lessonTypeAbbrev") ?? "",
            rooms: (o["auditories"]?.items ?? []).compactMap { $0.primitiveString }.joined(separator: ", "),
            teachers: (o["employees"]?.objects ?? []).map { teacher($0) },
            groups: (o["studentGroups"]?.objects ?? []).map { $0.opt("name") ?? "" }.joined(separator: ", "),
            weeks: Set((o["weekNumber"]?.items ?? []).compactMap { $0.primitiveString.flatMap { Int($0) } }),
            subgroup: o.int("numSubgroup", 0),
            from: LocalDate.parse(o.opt("startLessonDate")),
            to: LocalDate.parse(o.opt("endLessonDate")),
            exactDate: LocalDate.parse(o.opt("dateLesson")),
            // Если предмета нет, примечание уже стало названием — второй раз не показываем.
            note: subject != nil ? (o.opt("note") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
        )
    }
}

// MARK: Свои данные

/// Чьё расписание: группа (id = номер) или преподаватель (id = urlId).
struct Target: Hashable, Codable {
    let kind: String
    let id: String
    let title: String
    let sub: String
    var isGroup: Bool { kind == "group" }

    static func group(_ g: String) -> Target { Target(kind: "group", id: g, title: g, sub: "") }
}

struct Deadline: Hashable, Codable, Identifiable {
    var id: Int64
    var title: String
    var subject: String
    var due: LocalDateTime
    var done: Bool
}

struct Friend: Hashable, Codable {
    let name: String
    let group: String
    let subgroup: Int
    var target: Target { .group(group) }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func ifBlank(_ other: String) -> String { isBlank ? other : self }
}
