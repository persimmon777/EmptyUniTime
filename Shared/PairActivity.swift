#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity «текущая / следующая пара» на экране блокировки и в Dynamic Island.
struct PairActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Предмет полностью.
        var title: String
        /// Короткое имя: «КС ЛР».
        var short: String
        /// «Лабораторная · 507-2 к. · Иванов И. И.»
        var detail: String
        var room: String
        var isNow: Bool
        var start: Date
        var end: Date
        /// Что дальше: «Далее: ОАиП (ЛК) в 12:00», может быть пустым.
        var next: String
    }

    var group: String
}
#endif
