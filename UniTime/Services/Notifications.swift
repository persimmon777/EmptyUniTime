import Foundation
import UserNotifications

/// Локальные уведомления: напоминания о парах и дедлайнах, изменения расписания, новое в IIS.
enum Notifications {
    static let center = UNUserNotificationCenter.current()

    static func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func post(title: String, body: String, id: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        if AppSettings.shared.remindSound { c.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// Перепланировать напоминания. iOS хранит не больше 64 запланированных уведомлений, поэтому берём ближайшие.
    static func reschedule(schedule s: Schedule?) async {
        let store = Store.shared
        let st = AppSettings.shared
        let pending = await center.pendingNotificationRequests()
        let old = pending.map { $0.identifier }.filter { $0.hasPrefix("remind.") || $0.hasPrefix("deadline.") }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let now = LocalDateTime.now()
        var requests = [UNNotificationRequest]()

        // Пары с включённым напоминанием: за N минут до начала.
        let keys = store.reminders
        if let s = s, !keys.isEmpty {
            let before = st.remindMinutes
            let list = s.upcoming(now: now, subgroup: store.subgroup, count: 300)
                .filter { keys.contains($0.lesson.key) && $0.startAt.plusMinutes(-before).isAfter(now) }
                .prefix(30)
            for o in list {
                let c = UNMutableNotificationContent()
                c.title = "Через \(before) минут: \(lessonName(o))"
                let note = store.note(o.lesson.key)
                let text = [place(o), note].filter { !$0.isBlank && $0 != "—" }.joined(separator: " · ")
                c.body = text.isBlank ? lessonDetails(o) : text
                if st.remindSound { c.sound = .default }
                requests.append(request("remind.\(o.startAt)", c, o.startAt.plusMinutes(-before)))
            }
        }

        // Дедлайны: за сутки и за 2 часа.
        var dl = [(LocalDateTime, String, Deadline)]()
        for d in store.deadlines() where !d.done {
            dl.append((d.due.plusMinutes(-24 * 60), "Завтра", d))
            dl.append((d.due.plusMinutes(-120), "Через 2 часа", d))
        }
        for (at, label, d) in dl.filter({ $0.0.isAfter(now) }).sorted(by: { $0.0 < $1.0 }).prefix(24) {
            let c = UNMutableNotificationContent()
            c.title = "\(label) дедлайн: \(d.title)"
            let due = "срок \(d.due.date.day) \(month(d.due.date)), \(d.due.time)"
            c.body = [d.subject, due].filter { !$0.isBlank }.joined(separator: " · ")
            if st.remindSound { c.sound = .default }
            requests.append(request("deadline.\(d.id).\(label)", c, at))
        }

        for r in requests { try? await center.add(r) }
    }

    private static func request(_ id: String, _ c: UNNotificationContent, _ at: LocalDateTime) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at.toDate())
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }
}
