import Foundation

// Тесты логики расписания (порт ScheduleTest/FeaturesTest из Android-версии).
// Запуск: см. .github/workflows/ios.yml (swiftc Shared/*.swift Tests/main.swift).

var failures = 0
var passed = 0

func check(_ cond: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if cond { passed += 1 } else { failures += 1; print("FAIL [\(line)]: \(what)") }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ what: String, line: Int = #line) {
    check(a == b, "\(what): \(a) != \(b)", line: line)
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/schedule.json"
let data = try! Data(contentsOf: URL(fileURLWithPath: path))

// 23.10.2026 — 4-я учебная неделя (по API current-week)
func fresh() -> Schedule { try! Schedule.parse(data, anchorMonday: LocalDate(2026, 10, 19), anchorWeek: 4) }
let s = fresh()

// --- Даты ---
eq(LocalDate(2026, 10, 23).weekday, 5, "23.10.2026 — пятница")
eq(LocalDate(1970, 1, 1).weekday, 4, "1970-01-01 — четверг")
eq(LocalDate(2024, 2, 29).plusDays(1), LocalDate(2024, 3, 1), "високосный год")
eq(LocalDate.parse("01.09.2026"), LocalDate(2026, 9, 1), "разбор dd.MM.yyyy")
eq(LocalDate.parse("2026-09-01T10:00:00"), LocalDate(2026, 9, 1), "разбор ISO")
eq(LocalDate(2026, 10, 25).monday, LocalDate(2026, 10, 19), "понедельник недели")
eq(LocalDateTime.parse("2026-10-23T22:45")!.plusMinutes(90).description, "2026-10-24T00:15", "переход через полночь")

// --- Номера недель ---
eq(s.weekNumber(LocalDate(2026, 10, 23)), 4, "неделя 23.10")
eq(s.weekNumber(LocalDate(2026, 10, 26)), 1, "неделя 26.10")
eq(s.weekNumber(LocalDate(2026, 9, 1)), 1, "неделя 01.09")

// --- Разбор ---
eq(s.title, "572302", "название группы")
eq(s.termStart, LocalDate(2026, 9, 1), "начало семестра")
eq(s.examsEnd, LocalDate(2027, 1, 25), "конец сессии")

let mon = LocalDate(2026, 10, 26) // 1 неделя: Философия 12:00, ФизК 13:35
let fri = LocalDate(2026, 10, 30)

for t in ["2026-10-23T22:45", "2026-10-26T07:00", "2026-10-26T09:00", "2026-10-26T12:00"] {
    let now = LocalDateTime.parse(t)!
    let d = describe(s, now: now, subgroup: 0)
    print("\(t) -> \(d.title) | \(d.text) | next change \(s.nextChange(now: now, subgroup: 0))")
}
for o in s.lessonsOn(mon, subgroup: 0) {
    print("  пн 26.10: \(o.lesson.start) \(o.lesson.subject) \(o.lesson.type) \(o.lesson.rooms) подгр.\(o.lesson.subgroup)")
}

// --- Скрытие пары и предмета ---
do {
    let s = fresh()
    let physed = s.lessonsOn(mon, subgroup: 0).first { $0.lesson.subject == "ФизК" }!.lesson
    s.hidden = [physed.key]
    eq(s.lessonsOn(mon, subgroup: 0).map { $0.lesson.subject }, ["Философия"], "скрыта одна пара")
    s.hidden = ["S:Философия"]
    check(!s.lessonsOn(mon, subgroup: 0).contains { $0.lesson.subject == "Философия" }, "скрыт предмет")
    check(!s.lessonsOn(LocalDate(2026, 10, 28), subgroup: 0).contains { $0.lesson.subject == "Философия" }, "и ПЗ в среду")
}

// --- Оставшиеся пары по предметам ---
do {
    let s = fresh()
    let now = LocalDateTime(date: mon, time: LocalTime(9, 0))
    let left = s.remaining(now: now, subgroup: 1)
    check(!left.isEmpty, "есть оставшиеся пары")
    let order = ["ЛК", "ПЗ", "ЛР"]
    for subj in left {
        for (type, list) in subj.byType {
            check(list.allSatisfy { $0.lesson.subject == subj.lesson.subject && $0.lesson.type == type && $0.endAt.isAfter(now) }, "состав \(subj.lesson.subject) \(type)")
            eq(list.map { $0.startAt }, list.map { $0.startAt }.sorted(), "по времени \(subj.lesson.subject)")
        }
        let known = subj.byType.map { $0.type }.filter { order.contains($0) }
        eq(known, known.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }, "порядок типов")
    }
    eq(left.map { $0.lesson.subject }, left.sorted { $0.first < $1.first }.map { $0.lesson.subject }, "предметы по ближайшей паре")
    check(left.flatMap { $0.byType.flatMap { $0.list } }.allSatisfy { [0, 1].contains($0.lesson.subgroup) }, "п/г 1 не видит п/г 2")
    eq(pairs(1), "1 пара", "склонение 1")
    eq(pairs(3), "3 пары", "склонение 3")
    eq(pairs(12), "12 пар", "склонение 12")
}

// --- Ближайшая пара по предмету ---
do {
    let o = s.nextOf("КС", now: LocalDateTime(date: mon, time: LocalTime(9, 0)), subgroup: 1)
    check(o != nil, "есть следующая КС")
    eq(o?.date, fri, "КС в пятницу")
    eq(o?.lesson.start, LocalTime(10, 5), "КС в 10:05")
}

// --- Окна между парами ---
do {
    let tue = s.lessonsOn(LocalDate(2026, 10, 27), subgroup: 0)
    eq(windowBefore(tue, 1), nil, "перемена 10 мин")
    eq(windowBefore(tue, 2), nil, "перемена 30 мин — обычная")
}

// --- Общие окна с другом ---
do {
    let c = commonWindows(s.lessonsOn(fri, subgroup: 1), s.lessonsOn(fri, subgroup: 2))
    check(c.windows.isEmpty, "пятница: окон нет")
    eq(c.freeAfter, LocalTime(15, 0), "свободны после 15:00")
    let c2 = commonWindows(s.lessonsOn(mon, subgroup: 0), [])
    eq(c2.freeAfter, LocalTime(15, 0), "понедельник до 15:00")
    check(commonWindows([], []).bothFree, "оба свободны")
}

// --- Разное ---
eq(roomPlace("221-5 к.")?.corpus, "5", "корпус")
eq(roomPlace("221-5 к.")?.floor, "2 этаж", "этаж")
eq(describeKey("КС|ЛР|1|FRIDAY|12:00"), "КС ЛР · п/г 1 · Пт 12:00", "описание ключа")
eq(shortName("Иванов Иван Иванович"), "Иванов И. И.", "короткое имя")
eq(fmt1(4.0), "4", "fmt1 целое")
eq(fmt1(4.25), "4.2", "fmt1 дробное")
let st = Stats.semester(s, subgroup: 0, now: LocalDateTime(date: mon, time: LocalTime(9, 0)))
check(st.pairs > 0 && st.hours > 0, "статистика семестра")

// --- JSON ---
do {
    let j = JSON.parse(#"{"b":1,"a":[{"x":"Пр"},null],"c":{"name":"N"},"d":true,"e":-2.5e1}"#)!
    eq(j.keys, ["b", "a", "c", "d", "e"], "порядок ключей")
    eq(j["a"]?.items?.first?.str("x"), "Пр", "юникод")
    eq(j.str("c"), "N", "вложенный объект → name")
    eq(j.opt("b"), "1", "число как текст")
    check(j.bool("d"), "bool")
    eq(listIn(j).count, 1, "listIn")
}

print("passed: \(passed), failed: \(failures)")
exit(failures == 0 ? 0 : 1)
