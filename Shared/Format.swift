import Foundation

let MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня",
              "июля", "августа", "сентября", "октября", "ноября", "декабря"]
let DAY_FULL = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
let DAY_SHORT = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

func month(_ d: LocalDate) -> String { MONTHS[d.month - 1] }

func dayName(_ d: LocalDate, full: Bool = true) -> String {
    full ? DAY_FULL[d.weekday - 1] : DAY_SHORT[d.weekday - 1]
}

func dayTitle(_ d: LocalDate) -> String { "\(dayName(d)), \(d.day) \(month(d))" }

func minutesText(_ min: Int) -> String {
    let h = min / 60
    let m = min % 60
    if h == 0 { return "\(m) мин" }
    if m == 0 { return "\(h) ч" }
    return "\(h) ч \(m) мин"
}

/// «через 25 мин», «завтра в 08:30», «Пт, 30 октября в 10:05».
func untilText(_ o: Occurrence, now: LocalDateTime) -> String {
    let today = now.date
    let t = o.lesson.start.description
    if o.date == today { return "через \(minutesText(now.minutes(to: o.startAt) + 1))" }
    if o.date == today.plusDays(1) { return "завтра в \(t)" }
    return "\(dayName(o.date, full: false)), \(o.date.day) \(month(o.date)) в \(t)"
}

/// «в 12:00», «завтра в 08:30», «пт 30 в 10:05» — короткое, для уведомлений.
func whenText(_ o: Occurrence, now: LocalDateTime) -> String {
    let t = o.lesson.start.description
    let today = now.date
    if o.date == today { return "в \(t)" }
    if o.date == today.plusDays(1) { return "завтра в \(t)" }
    return "\(dayName(o.date, full: false).lowercased()) \(o.date.day) в \(t)"
}

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    if n % 10 == 1 && n % 100 != 11 { return one }
    if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return few }
    return many
}

func pairs(_ n: Int) -> String { "\(n) \(plural(n, "пара", "пары", "пар"))" }

/// Номер пары БГУИР по времени начала.
func pairNumber(_ start: LocalTime) -> Int? {
    switch start.description {
    case "08:30": return 1
    case "10:05": return 2
    case "12:00": return 3
    case "13:35": return 4
    case "15:30": return 5
    case "17:05": return 6
    case "18:45": return 7
    case "20:20": return 8
    default: return nil
    }
}

func deadlineLabel(_ d: Deadline, now: LocalDateTime) -> String {
    let days = now.date.days(to: d.due.date)
    let t = d.due.time.description
    if d.due.isBefore(now) { return "просрочен" }
    if days == 0 { return "сегодня до \(t)" }
    if days == 1 { return "завтра до \(t)" }
    if days < 7 { return "\(dayName(d.due.date, full: false).lowercased()), до \(t)" }
    return "\(d.due.date.day) \(month(d.due.date))"
}

/// Название пары с типом: «КС (ЛР)».
func lessonName(_ o: Occurrence) -> String {
    o.lesson.type.isBlank ? o.lesson.subject : "\(o.lesson.subject) (\(o.lesson.type))"
}

func place(_ o: Occurrence) -> String { o.lesson.rooms.ifBlank("—") }

func lessonDetails(_ o: Occurrence, room: Bool = true, teacher: Bool = true) -> String {
    ["\(o.lesson.start)–\(o.lesson.end)", room ? o.lesson.rooms : "", teacher ? o.lesson.teacher : ""]
        .filter { !$0.isBlank }.joined(separator: " · ")
}

struct Display { let title: String; let text: String }

/// Текст «что сейчас и что дальше» — для Live Activity и уведомлений.
func describe(_ s: Schedule, now: LocalDateTime, subgroup: Int, room: Bool = true, teacher: Bool = true) -> Display {
    let (cur, next) = s.currentAndNext(now: now, subgroup: subgroup)
    if let cur = cur {
        let title = "Сейчас: \(lessonName(cur)) · до \(cur.lesson.end)"
        let text: String
        if let next = next {
            text = "Далее: \(lessonName(next)) \(whenText(next, now: now))" + (room ? " · \(place(next))" : "")
        } else {
            text = "Больше пар нет"
        }
        return Display(title: title, text: text)
    }
    guard let next = next else { return Display(title: "Пар не найдено", text: "В ближайшие три недели пусто") }
    return Display(title: "\(lessonName(next)) \(whenText(next, now: now))", text: lessonDetails(next, room: room, teacher: teacher))
}

/// Минуты между концом предыдущей пары и началом этой (может быть ≤ 0 у параллельных подгрупп).
func gapBefore(_ list: [Occurrence], _ i: Int) -> Int? {
    i == 0 ? nil : list[i - 1].endAt.minutes(to: list[i].startAt)
}

/// Свободное время между парами длиннее обычной перемены (30 мин у БГУИР).
func windowBefore(_ list: [Occurrence], _ i: Int) -> Int? {
    guard let g = gapBefore(list, i), g > 30 else { return nil }
    return g
}

/// В воскресенье показываем уже следующую неделю.
func mondayOf(_ d: LocalDate) -> LocalDate { d.weekday == 7 ? d.plusDays(1) : d.monday }

/// Общее свободное время двух людей за день.
struct Common {
    let windows: [(LocalTime, LocalTime)]
    let freeAfter: LocalTime?
    let bothFree: Bool
}

/// Окно — перерыв длиннее обычной перемены (больше `breakMinutes`).
func commonWindows(_ a: [Occurrence], _ b: [Occurrence], breakMinutes: Int = 30) -> Common {
    let busy = (a + b).map { ($0.lesson.start, $0.lesson.end) }.sorted { $0.0 < $1.0 }
    if busy.isEmpty { return Common(windows: [], freeAfter: nil, bothFree: true) }
    var merged = [(LocalTime, LocalTime)]()
    for iv in busy {
        if let last = merged.last, iv.0 <= last.1 {
            merged[merged.count - 1] = (last.0, max(last.1, iv.1))
        } else {
            merged.append(iv)
        }
    }
    var windows = [(LocalTime, LocalTime)]()
    if merged.count > 1 {
        for i in 1..<merged.count {
            let w = (merged[i - 1].1, merged[i].0)
            if w.1.minutes - w.0.minutes > breakMinutes { windows.append(w) }
        }
    }
    return Common(windows: windows, freeAfter: merged.last?.1, bothFree: false)
}

/// «221-5 к.» → корпус 5, 2 этаж.
func roomPlace(_ room: String) -> (corpus: String, floor: String)? {
    guard let re = try? NSRegularExpression(pattern: "(\\d+)[а-яА-Я]?-(\\d+)"),
          let m = re.firstMatch(in: room, range: NSRange(room.startIndex..., in: room)),
          let r1 = Range(m.range(at: 1), in: room), let r2 = Range(m.range(at: 2), in: room),
          let num = Int(room[r1]) else { return nil }
    let corpus = String(room[r2])
    return (corpus, num >= 100 ? "\(num / 100) этаж" : "")
}

/// «Иванов Иван Иванович» → «Иванов И. И.»
func shortName(_ full: String) -> String {
    let p = full.split(separator: " ").map(String.init)
    return p.count >= 3 ? "\(p[0]) \(p[1].prefix(1)). \(p[2].prefix(1))." : full
}

/// Ключ отдельной пары «КС|ЛР|1|FRIDAY|12:00» → «КС ЛР · п/г 1 · Пт 12:00».
func describeKey(_ key: String) -> String {
    let p = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard p.count >= 5 else { return key }
    let day = DAY_KEYS.firstIndex(of: p[3]).map { DAY_SHORT[$0] } ?? ""
    return ["\(p[0]) \(p[1])".trimmingCharacters(in: .whitespaces), p[2] != "0" ? "п/г \(p[2])" : "", "\(day) \(p[4])".trimmingCharacters(in: .whitespaces)]
        .filter { !$0.isBlank }.joined(separator: " · ")
}

func fmt1(_ d: Double) -> String {
    let s = String(format: "%.1f", d)
    return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
}

func fmt2(_ d: Double) -> String { String(format: "%.2f", d) }
