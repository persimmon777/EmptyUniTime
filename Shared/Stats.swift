import Foundation

/// Статистика семестра для секретного экрана.
struct SemesterStats {
    let from: LocalDate
    let to: LocalDate
    let pairs: Int
    let hours: Double
    let hoursDone: Double
    let bySubject: [(String, Double)]
    let topTeacher: (Teacher, Int)?
    let topRoom: (String, Int)?
    let hardestDay: (Int, Double)?
    let earlyPairs: Int
    let longestDay: (LocalDate, Int)?
    let windowHours: Double
    let freeDays: Int
}

enum Stats {
    static func semester(_ s: Schedule, subgroup: Int, now: LocalDateTime) -> SemesterStats {
        let today = now.date
        let from = s.termStart ?? today.plusDays(1 - today.day)
        let to = s.termEnd ?? today.plusWeeks(16)
        var days = [LocalDate]()
        var d = from
        while d <= to { days.append(d); d = d.plusDays(1) }
        var byDay = [LocalDate: [Occurrence]]()
        for day in days { byDay[day] = s.lessonsOn(day, subgroup: subgroup) }
        let all = days.flatMap { byDay[$0] ?? [] }
        func h(_ o: Occurrence) -> Double { Double(o.startAt.minutes(to: o.endAt)) / 60 }

        var teacherCount = [Int: (Teacher, Int)]()
        for t in all.flatMap({ $0.lesson.teachers }) {
            teacherCount[t.id] = (t, (teacherCount[t.id]?.1 ?? 0) + 1)
        }
        let topTeacher = teacherCount.values.max { $0.1 < $1.1 }

        var roomCount = [String: Int]()
        for r in all.map({ $0.lesson.rooms }) where !r.isBlank { roomCount[r, default: 0] += 1 }
        let topRoom = roomCount.max { $0.value < $1.value }.map { ($0.key, $0.value) }

        var weekday = [Int: Double]()
        for o in all { weekday[o.date.weekday, default: 0] += h(o) }
        let weeks = max(Double(days.count) / 7.0, 1)

        var longest: (LocalDate, Int)?
        var windows = 0.0
        for (day, list) in byDay where !list.isEmpty {
            let start = list.map { $0.startAt }.min()!
            let end = list.map { $0.endAt }.max()!
            let dur = start.minutes(to: end)
            if longest == nil || dur > longest!.1 { longest = (day, dur) }
            let sorted = list.sorted { $0.startAt < $1.startAt }
            var gaps = 0
            if sorted.count > 1 {
                for i in 1..<sorted.count {
                    let g = sorted[i - 1].endAt.minutes(to: sorted[i].startAt)
                    if g > 30 { gaps += g }
                }
            }
            windows += Double(gaps) / 60
        }

        var bySubject = [String: Double]()
        for o in all { bySubject[o.lesson.fullTitle, default: 0] += h(o) }

        return SemesterStats(
            from: from,
            to: to,
            pairs: all.count,
            hours: all.reduce(0) { $0 + h($1) },
            hoursDone: all.filter { $0.endAt.isBefore(now) }.reduce(0) { $0 + h($1) },
            bySubject: Array(bySubject.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }),
            topTeacher: topTeacher,
            topRoom: topRoom,
            hardestDay: weekday.max { $0.value < $1.value }.map { ($0.key, $0.value / weeks) },
            earlyPairs: all.filter { $0.lesson.start == LocalTime(8, 30) }.count,
            longestDay: longest,
            windowHours: windows,
            freeDays: days.filter { $0.weekday != 7 && (byDay[$0] ?? []).isEmpty }.count
        )
    }
}
