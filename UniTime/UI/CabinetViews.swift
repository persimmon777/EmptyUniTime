import SwiftUI

// MARK: Помощники

/// Дата из ответа IIS: миллисекунды, ISO или dd.MM.yyyy.
func parseDate(_ s: String) -> LocalDate? {
    if s.isBlank { return nil }
    if let ms = Int64(s), ms > 1_000_000_000_000 {
        return LocalDateTime(Date(timeIntervalSince1970: TimeInterval(ms) / 1000)).date
    }
    return LocalDate.parse(s)
}

func prettyValue(_ s: String) -> String {
    guard let d = parseDate(s) else { return s }
    return "\(d.day) \(month(d)) \(d.year)"
}

/// Осень: сентябрь–январь (с сессией), весна: февраль–август.
func semesterOf(_ d: LocalDate) -> String {
    if d.month >= 9 { return "Осень \(d.year)" }
    if d.month == 1 { return "Осень \(d.year - 1)" }
    return "Весна \(d.year)"
}

private func semesterSortKey(_ label: String) -> Int {
    let year = Int(label.split(separator: " ").last ?? "") ?? 0
    return year * 2 + (label.hasPrefix("Осень") ? 1 : 0)
}

private func hoursOf(_ o: JSON) -> Double { Double(o.str("hours").replacingOccurrences(of: ",", with: ".")) ?? 0 }
private func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

struct StatusChip: View {
    @Environment(\.look) private var C
    let text: String

    var body: some View {
        if !text.isBlank {
            let t = text.lowercased()
            let good = ["одобр", "выдан", "готов", "обработ", "поощр", "преми", "благодар", "подписан", "подтверждён", "новое"].contains { t.contains($0) }
                && !t.contains("не подтверждён")
            let bad = ["отклон", "взыск", "выгов", "замеч", "просроч", "отказ", "не подтверждён"].contains { t.contains($0) }
            let st = C.typeStyle(bad ? "Экз" : good ? "ЛК" : "ПЗ")
            Text(text).ct(12, .bold).foregroundStyle(st.fg)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(st.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .fixedSize()
        }
    }
}

/// Карточка записи: заголовок, плашка статуса, строка дат и пара деталей.
struct RecordCard: View {
    @Environment(\.look) private var C
    let title: String
    var chip = ""
    var meta = ""
    var lines: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(title.ifBlank("Запись")).ct(15, .bold).foregroundStyle(C.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(text: chip)
            }
            if !meta.isBlank { Text(meta).ct(13).foregroundStyle(C.muted) }
            ForEach(Array(lines.filter { !$0.1.isBlank }.enumerated()), id: \.offset) { _, kv in
                if kv.0.isBlank {
                    Text(kv.1).ct(14).foregroundStyle(C.ink)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(kv.0).ct(13).foregroundStyle(C.muted).frame(maxWidth: .infinity, alignment: .leading)
                        Text(kv.1).ct(13, .medium).foregroundStyle(C.ink).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .card(18, padding: 14)
    }
}

struct BigNumber: View {
    @Environment(\.look) private var C
    let value: String
    let label: String
    var sub: String? = nil
    var size: CGFloat = 44
    var labelBottom: CGFloat = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            CountUpText(value: value, color: .white, size: size).ct(size, .heavy, lh: size)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).ct(15, .semibold).foregroundStyle(C.heroMuted)
                if let sub = sub { Text(sub).ct(12).foregroundStyle(C.heroMuted) }
            }
            .padding(.bottom, labelBottom)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Переключатель семестров для списка записей с датами.
struct SemesterTabs<Content: View>: View {
    let items: [JSON]
    var dateKeys = ["date", "dateFrom", "startDate", "createdDate", "applicationDate", "dateOrder"]
    @ViewBuilder let content: ([JSON]) -> Content
    @State private var sel: String?

    var body: some View {
        var groups = [(String, [JSON])]()
        for o in items {
            let label = dateKeys.lazy.compactMap { parseDate(o.str($0)) }.first.map(semesterOf) ?? "Без даты"
            if let i = groups.firstIndex(where: { $0.0 == label }) { groups[i].1.append(o) } else { groups.append((label, [o])) }
        }
        groups.sort { semesterSortKey($0.0) > semesterSortKey($1.0) }
        return Group {
            if groups.count <= 1 {
                content(items)
            } else {
                let current = sel ?? groups[0].0
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups.indices, id: \.self) { i in
                                Choice("\(groups[i].0) · \(groups[i].1.count)", current == groups[i].0) { sel = groups[i].0 }
                            }
                        }
                    }
                    content(groups.first { $0.0 == current }?.1 ?? [])
                }
            }
        }
    }
}

// MARK: Профиль

struct ProfileCard: View {
    @Environment(\.look) private var C
    let o: JSON
    @State private var photo: UIImage?

    var body: some View {
        let fio = o.str("fio").ifBlank([o.str("lastName"), o.str("firstName"), o.str("middleName")].joined(separator: " ").trimmingCharacters(in: .whitespaces))
        let initials = fio.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined()
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Group {
                        if let p = photo { Image(uiImage: p).resizable().scaledToFill() }
                        else { Text(initials).ct(24, .bold).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(C.heroTrack) }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fio).ct(20, .bold).foregroundStyle(.white)
                        Text([o.str("group").isBlank ? "" : "Группа \(o.str("group"))", o.str("accountType") == "STUDENT" ? "студент" : ""]
                            .filter { !$0.isBlank }.joined(separator: " · "))
                            .ct(14).foregroundStyle(C.heroMuted)
                    }
                }
                if o.bool("isGroupHead") { Pill(text: "Староста", bg: C.heroTrack, fg: .white) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                InfoLine(label: "Студенческий / логин", value: o.str("username"))
                InfoLine(label: "Почта", value: o.str("email"))
                InfoLine(label: "Телефон", value: o.str("phone"))
                InfoLine(label: "Учётная запись активна до", value: prettyValue(o.str("ldapBanDate")))
            }
            .card(18)
            if o.bool("hasNotConfirmedContact") {
                Text("На сайте есть неподтверждённый контакт — подтверди его на iis.bsuir.by.").ct(13).foregroundStyle(C.error)
            }
        }
        .task {
            let url = o.str("photoUrl")
            if url.hasPrefix("http"), let data = try? await Net.get(url) { photo = UIImage(data: data) }
        }
    }
}

private struct InfoLine: View {
    @Environment(\.look) private var C
    let label: String
    let value: String
    var body: some View {
        if !value.isBlank {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).ct(12).foregroundStyle(C.muted)
                Text(value).ct(15, .medium).foregroundStyle(C.ink).textSelection(.enabled)
            }
        }
    }
}

// MARK: Зачётка

struct MarkbookView: View {
    @Environment(\.look) private var C
    let o: JSON
    @State private var sel: String?

    var body: some View {
        let pages = o["markPages"]?.fields ?? []
        let sems = pages.map { $0.0 }.sorted { (Int($0) ?? 99) < (Int($1) ?? 99) }
        // По умолчанию — последний семестр, где уже есть оценки.
        let lastWithMarks = sems.last { k in
            listIn(pages.first { $0.0 == k }?.1, "marks").contains { !$0.str("mark").isBlank }
        } ?? sems.first
        let current = sel ?? lastWithMarks
        VStack(alignment: .leading, spacing: 12) {
            BigNumber(value: o.str("averageMark").ifBlank("—"), label: "средний балл",
                      sub: o.str("number").isBlank ? nil : "зачётка № \(o.str("number"))", size: 48, labelBottom: 6)
            if sems.isEmpty {
                EmptyCard(title: "Зачётка пустая", text: "Оценок пока нет.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(sems, id: \.self) { k in Choice("\(k) семестр", current == k) { sel = k } } }
                }
                if let k = current, let page = pages.first(where: { $0.0 == k })?.1 {
                    let items = listIn(page, "marks")
                    let withMark = items.filter { !$0.str("mark").isBlank }.count
                    HStack(spacing: 8) {
                        InfoTile(label: "Средний за семестр", value: page.str("averageMark").ifBlank("—"))
                        InfoTile(label: "Сдано", value: "\(withMark) из \(items.count)")
                    }
                    if withMark == 0 && !items.isEmpty {
                        Text("Семестр ещё не закрыт — вот что предстоит сдавать.").ct(13).foregroundStyle(C.muted)
                    }
                    let order = ["Экзамен", "Дифф. зачет", "Зачет"]
                    let sorted = items.enumerated().sorted { a, b in
                        let x = order.firstIndex(of: a.element.str("formOfControl")) ?? 9
                        let y = order.firstIndex(of: b.element.str("formOfControl")) ?? 9
                        return x != y ? x < y : a.offset < b.offset
                    }.map { $0.element }
                    ForEach(sorted.indices, id: \.self) { i in SubjectMark(m: sorted[i]) }
                }
            }
        }
    }
}

private struct SubjectMark: View {
    @Environment(\.look) private var C
    let m: JSON

    var body: some View {
        let form = m.str("formOfControl")
        let st = C.typeStyle(form.hasPrefix("Экзамен") ? "Экз" : form.hasPrefix("Дифф") ? "ЛР" : "ЛК")
        let mark = m.str("mark")
        let common = num(m.str("commonMark"))
        let retakes = num(m.str("commonRetakes"))
        let mine = m.int("retakesCount")
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.str("fullSubject", "subject")).ct(16, .bold).foregroundStyle(C.ink)
                    if !form.isBlank {
                        Text(form).ct(12, .bold).foregroundStyle(st.fg)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(st.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(mark.isBlank ? "—" : (mark.lowercased() == "зачтено" || mark == "+") ? "✓" : mark)
                    .ct(22, .heavy).foregroundStyle(mark.isBlank ? C.muted : C.softInk)
                    .frame(width: 52, height: 52)
                    .background(mark.isBlank ? C.ground : C.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            let meta = [prettyValue(m.str("date")), m.str("teacher")].filter { !$0.isBlank }
            if !meta.isEmpty { Text(meta.joined(separator: " · ")).ct(13).foregroundStyle(C.muted) }
            HStack(spacing: 6) {
                if let c = common, c > 0 { Stat(label: "Средний по потоку", value: fmt1(c)) }
                if let r = retakes { Stat(label: "Пересдают", value: "\(fmt1(r))%") }
                if mine > 0 { Stat(label: "Твои пересдачи", value: "\(mine)") }
            }
            let extra = [num(m.str("hours")).map { "\(fmt1($0)) ч" }, num(m.str("credits")).map { "\(fmt1($0)) з.е." }].compactMap { $0 }
            if !extra.isEmpty { Text(extra.joined(separator: " · ")).ct(12).foregroundStyle(C.muted) }
        }
        .card(18, padding: 14)
    }
}

private struct Stat: View {
    @Environment(\.look) private var C
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).ct(14, .bold).foregroundStyle(C.ink)
            Text(label).ct(11).foregroundStyle(C.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(C.ground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: Успеваемость

private func collectMarks(_ v: JSON, _ out: inout [(String, String)]) {
    if let f = v.fields {
        let m = v.str("mark", "value")
        if !m.isBlank && m.count <= 3 && v.has("mark") { out.append((m, prettyValue(v.str("date", "dateString")))) }
        for (k, child) in f where k != "deadlines" { collectMarks(child, &out) }
    } else if let a = v.items {
        for x in a { collectMarks(x, &out) }
    }
}

private func collectOmissionHours(_ v: JSON, _ inside: Bool = false) -> Double {
    if let f = v.fields {
        return f.reduce(0) { sum, kv in
            let inner = inside || kv.0.lowercased().contains("omission") || kv.0.lowercased().contains("absence")
            return sum + (inner && kv.0 == "hours" ? hoursOf(v) : collectOmissionHours(kv.1, inner))
        }
    }
    if let a = v.items { return a.reduce(0) { $0 + collectOmissionHours($1, inside) } }
    return 0
}

struct PerformanceView: View {
    @Environment(\.look) private var C
    let v: JSON

    var body: some View {
        let subjects = listIn(v["personalRating"] ?? v, "subjects", "disciplines", "personalRating")
        if subjects.isEmpty {
            JsonView(v: v, depth: 0)
        } else {
            let marksBy = subjects.map { s -> [(String, String)] in var out = [(String, String)](); collectMarks(s, &out); return out }
            let all = marksBy.flatMap { $0 }.compactMap { num($0.0) }.filter { $0 > 0 }
            let withMarks = marksBy.filter { $0.contains { num($0.0) != nil } }.count
            let order = subjects.indices.sorted { subjects[$0].str("name", "discipline", "abbrev") < subjects[$1].str("name", "discipline", "abbrev") }
            VStack(alignment: .leading, spacing: 10) {
                // Общий средний — как в зачётке: сумма всех отметок, делённая на их количество.
                BigNumber(value: all.isEmpty ? "—" : fmt2(all.reduce(0, +) / Double(all.count)), label: "средний балл",
                          sub: all.isEmpty ? "отметок пока нет" : "\(all.count) отметок по \(withMarks) предметам из \(subjects.count)")
                ForEach(order, id: \.self) { i in
                    let s = subjects[i]
                    let marks = marksBy[i]
                    let numeric = marks.compactMap { num($0.0) }
                    let avg = num(s.str("average")) ?? (numeric.isEmpty ? nil : numeric.reduce(0, +) / Double(numeric.count))
                    let absent = collectOmissionHours(s)
                    let dl = listIn(s["deadlines"])
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(s.str("name", "discipline", "subject", "abbrev")).ct(15, .bold).foregroundStyle(C.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(avg.map { fmt1($0) } ?? "—").ct(17, .heavy).foregroundStyle(avg == nil ? C.muted : C.softInk)
                                .frame(width: 48, height: 48)
                                .background(avg == nil ? C.ground : C.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        if marks.isEmpty {
                            Text("Отметок пока нет").ct(13).foregroundStyle(C.muted)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(marks.indices, id: \.self) { j in
                                    Text(marks[j].0).ct(13, .bold).foregroundStyle(C.ink)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(C.ground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                        let info = [absent > 0 ? "Пропуски: \(fmt1(absent)) ч" : nil, dl.isEmpty ? nil : "Дедлайнов: \(dl.count)"].compactMap { $0 }
                        if !info.isEmpty { Text(info.joined(separator: " · ")).ct(12).foregroundStyle(C.muted) }
                    }
                    .card(18, padding: 14)
                }
            }
        }
    }
}

// MARK: Пропуски

private func period(_ o: JSON) -> String {
    let a = prettyValue(o.str("dateFrom", "startDate"))
    let b = prettyValue(o.str("dateTo", "endDate"))
    if !a.isBlank && !b.isBlank && a != b { return "\(a) – \(b)" }
    if !a.isBlank { return a }
    return prettyValue(o.str("date", "createdDate", "applicationDate", "dateOrder"))
}

private func byDateDesc(_ list: [JSON], _ keys: String...) -> [JSON] {
    list.sorted { (parseDate($0.str(keys)) ?? LocalDate(epochDay: Int.min / 2)) > (parseDate($1.str(keys)) ?? LocalDate(epochDay: Int.min / 2)) }
}

struct OmissionsView: View {
    @Environment(\.look) private var C
    let respectful: JSON?
    let disrespectful: JSON?

    var body: some View {
        let docs = listIn(respectful, "omissionDtoList")
        let bad = listIn(disrespectful, "omissions", "omissionDtoList")
        let total = bad.reduce(0) { $0 + hoursOf($1) }
        VStack(alignment: .leading, spacing: 12) {
            BigNumber(value: "\(fmt1(total)) ч", label: "всего пропущено", sub: "по неуважительной причине")
            SectionTitle(text: "По неуважительной причине", right: bad.isEmpty ? nil : "\(bad.count) записей")
            if bad.isEmpty {
                Text("Нет — так держать.").ct(14).foregroundStyle(C.muted)
            } else {
                SemesterTabs(items: bad) { list in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("За семестр: \(fmt1(list.reduce(0) { $0 + hoursOf($1) })) ч").ct(13, .semibold).foregroundStyle(C.accent)
                        let sorted = byDateDesc(list, "date", "dateFrom")
                        ForEach(sorted.indices, id: \.self) { i in
                            let o = sorted[i]
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(o.str("subject", "discipline", "subjectName").ifBlank("Занятие")).ct(15, .semibold).foregroundStyle(C.ink)
                                    Text([period(o), o.str("note")].filter { !$0.isBlank }.joined(separator: " · ")).ct(13).foregroundStyle(C.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                TypeChip(type: o.str("lessonTypeAbbrev"))
                                Text("\(fmt1(hoursOf(o))) ч").ct(15, .bold).foregroundStyle(C.ink)
                            }
                            .card(16, padding: 14)
                        }
                    }
                }
            }
            SectionTitle(text: "По уважительной причине", right: docs.isEmpty ? nil : "\(docs.count) документов")
            if docs.isEmpty {
                Text("Справок нет.").ct(14).foregroundStyle(C.muted)
            } else {
                SemesterTabs(items: docs) { list in
                    let sorted = byDateDesc(list, "dateFrom", "date")
                    VStack(spacing: 8) {
                        ForEach(sorted.indices, id: \.self) { i in
                            let o = sorted[i]
                            RecordCard(title: o.str("name", "documentType", "type", "omissionCertificateType").ifBlank("Справка"),
                                       meta: period(o), lines: [("Примечание", o.str("note", "description"))])
                        }
                    }
                }
            }
        }
    }
}

// MARK: Деканат, общежитие, группа, библиотека

struct DeanView: View {
    let v: JSON?
    var body: some View {
        let list = listIn(v, "certificateRequests", "certificates")
        if list.isEmpty {
            EmptyCard(title: "Заявок нет", text: "Справки заказываются на iis.bsuir.by в разделе «Деканат».")
        } else {
            SemesterTabs(items: list) { items in
                let sorted = byDateDesc(items, "createdDate", "dateOrder", "applicationDate", "date")
                VStack(spacing: 8) {
                    ForEach(sorted.indices, id: \.self) { i in
                        let o = sorted[i]
                        RecordCard(title: o.str("certificateType", "type", "name").ifBlank("Справка"), chip: o.str("status"),
                                   meta: prettyValue(o.str("createdDate", "dateOrder", "applicationDate", "date")),
                                   lines: [("Куда", o.str("provisionPlace", "place")), ("Номер", o.str("number")),
                                           ("Количество", o.str("count", "quantity")), ("Выдана", prettyValue(o.str("issueDate"))),
                                           ("Причина отказа", o.str("rejectionReason"))])
                    }
                }
            }
        }
    }
}

struct DormitoryView: View {
    @Environment(\.look) private var C
    let applications: JSON?
    let privileges: JSON?
    let premiumPenalty: JSON?

    var body: some View {
        let pp = listIn(premiumPenalty)
        let pr = listIn(privileges)
        let ap = listIn(applications)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Поощрения и взыскания", right: pp.isEmpty ? nil : "\(pp.count)")
            if pp.isEmpty {
                Text("Нет записей.").ct(14).foregroundStyle(C.muted)
            } else {
                SemesterTabs(items: pp) { items in
                    let sorted = byDateDesc(items, "date")
                    VStack(spacing: 8) {
                        ForEach(sorted.indices, id: \.self) { i in
                            let o = sorted[i]
                            let dir = o["directiveDto"]
                            let order = [dir.map { $0.str("number", "name") }.flatMap { $0.isBlank ? nil : "№ \($0)" },
                                         dir.map { $0.str("date") }.flatMap { $0.isBlank ? nil : "от \(prettyValue($0))" }].compactMap { $0 }.joined(separator: " ")
                            RecordCard(title: o.str("reason").ifBlank(o.str("eventTypeName")), chip: o.str("eventTypeName"),
                                       meta: prettyValue(o.str("date")), lines: [("Статус", o.str("status")), ("Приказ", order)])
                        }
                    }
                }
            }
            SectionTitle(text: "Льготы", right: pr.isEmpty ? nil : "\(pr.count)")
            if pr.isEmpty { Text("Льгот нет.").ct(14).foregroundStyle(C.muted) }
            ForEach(pr.indices, id: \.self) { i in
                let y = pr[i].str("year")
                RecordCard(title: pr[i].str("dormitoryPrivilegeCategoryName", "name"), meta: y.isBlank ? "" : "\(y) год")
            }
            SectionTitle(text: "Заявки на общежитие", right: ap.isEmpty ? nil : "\(ap.count)")
            if ap.isEmpty { Text("Заявок нет.").ct(14).foregroundStyle(C.muted) }
            ForEach(ap.indices, id: \.self) { i in
                let o = ap[i]
                RecordCard(title: o.str("dormitory", "dormitoryName", "name").ifBlank("Заявка"), chip: o.str("status"),
                           meta: prettyValue(o.str("applicationDate", "createdDate", "date")),
                           lines: [("Номер в очереди", o.str("queueNumber", "number")), ("Комментарий", o.str("comment", "note"))])
            }
        }
    }
}

struct GroupView: View {
    @Environment(\.look) private var C
    let v: JSON

    var body: some View {
        let students = listIn(v, "students", "groupInfoStudentDto")
        let head = v["headmanData"]?.str("fio") ?? ""
        if students.isEmpty {
            JsonView(v: v, depth: 0)
        } else {
            let subs = Array(Set(students.map { $0.int("subGroup") })).sorted()
            VStack(alignment: .leading, spacing: 10) {
                BigNumber(value: "\(students.count)", label: "студентов в группе", sub: head.isBlank ? nil : "староста: \(head)")
                ForEach(subs, id: \.self) { sub in
                    let list = students.filter { $0.int("subGroup") == sub }.sorted { $0.str("fio") < $1.str("fio") }
                    SectionTitle(text: sub == 0 ? "Без подгруппы" : "Подгруппа \(sub)", right: "\(list.count)")
                    VStack(spacing: 0) {
                        ForEach(list.indices, id: \.self) { i in
                            if i > 0 { Divider1() }
                            HStack {
                                Text("\(i + 1)").ct(13).foregroundStyle(C.muted).frame(width: 28, alignment: .leading)
                                Text(list[i].str("fio", "name")).ct(15).foregroundStyle(C.ink).lineLimit(1)
                                Spacer()
                                if !head.isBlank && list[i].str("fio") == head { StatusChip(text: "Староста") }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }
                    }
                    .card(18, padding: 0)
                }
            }
        }
    }
}

struct LibraryView: View {
    let v: JSON?
    var body: some View {
        let books = listIn(v, "books")
        if books.isEmpty {
            EmptyCard(title: "Книг на руках нет", text: "Здесь появятся книги, взятые в библиотеке БГУИР.")
        } else {
            VStack(spacing: 8) {
                ForEach(books.indices, id: \.self) { i in
                    let b = books[i]
                    let due = parseDate(b.str("returnDate", "dateTo", "deadline", "dateReturn"))
                    RecordCard(title: b.str("title", "name", "bookName", "description"),
                               chip: due.map { $0 < LocalDate.today() } == true ? "Просрочена" : "",
                               meta: b.str("author", "authors"),
                               lines: [("Выдана", prettyValue(b.str("issueDate", "dateFrom", "date"))),
                                       ("Вернуть до", due.map { "\($0.day) \(month($0)) \($0.year)" } ?? "")])
                }
            }
        }
    }
}

struct NotificationsView: View {
    let v: JSON?
    var body: some View {
        let list = listIn(v, "notifications")
        if list.isEmpty {
            EmptyCard(title: "Уведомлений нет", text: "Здесь будут сообщения из IIS.", glyph: .bell)
        } else {
            VStack(spacing: 8) {
                ForEach(list.indices, id: \.self) { i in
                    let n = list[i]
                    let title = n.str("title", "subject", "header")
                    RecordCard(title: title.ifBlank(String(n.str("message", "text").prefix(60))),
                               chip: n.has("isViewed") && !n.bool("isViewed") ? "Новое" : "",
                               meta: prettyValue(n.str("date", "createdDate", "creationDate")),
                               lines: [("", title.isBlank ? "" : n.str("message", "text", "content"))])
                }
            }
        }
    }
}

struct AccountSettingsView: View {
    @Environment(\.look) private var C
    let lastChange: JSON?
    let attempts: JSON?
    let contacts: JSON?
    let raw: Iis.Response?

    var body: some View {
        let last: String = {
            if let l = lastChange, l.isObject { return l.str("lastPasswordChange", "date", "lastChangeDate") }
            if let l = lastChange, let p = l.primitiveString { return p }
            return raw?.text.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n")) ?? ""
        }()
        let list = listIn(contacts, "contactDtoList")
        VStack(alignment: .leading, spacing: 10) {
            RecordCard(title: "Пароль", lines: [
                ("Последняя смена", prettyValue(last)),
                ("Осталось попыток входа", attempts?.str("passwordAttempts") ?? ""),
                ("Блокировка до", prettyValue(attempts?.str("passwordBanExpiredTime") ?? "")),
            ])
            SectionTitle(text: "Контакты")
            if list.isEmpty { Text("Контактов нет.").ct(14).foregroundStyle(C.muted) }
            ForEach(list.indices, id: \.self) { i in
                let c = list[i]
                RecordCard(title: c.str("contactValue", "value"), chip: c.bool("confirmed") ? "Подтверждён" : "Не подтверждён",
                           meta: c.str("contactType", "type", "contactTypeName"))
            }
            Text("Сменить пароль и контакты можно на iis.bsuir.by → Настройки.").ct(12).foregroundStyle(C.muted)
        }
    }
}

// MARK: Ответ как есть

private let LABELS: [String: String] = [
    "fio": "ФИО", "lastName": "Фамилия", "firstName": "Имя", "middleName": "Отчество",
    "username": "Логин", "email": "Почта", "group": "Группа", "groupName": "Группа",
    "course": "Курс", "faculty": "Факультет", "speciality": "Специальность",
    "subject": "Предмет", "subjectName": "Предмет", "mark": "Оценка", "marks": "Оценки",
    "date": "Дата", "dateFrom": "С", "dateTo": "По", "reason": "Причина",
    "eventTypeName": "Тип", "status": "Статус", "hours": "Часы", "averageMark": "Средний балл",
    "semester": "Семестр", "teacher": "Преподаватель", "year": "Год", "notifications": "Уведомления",
    "message": "Сообщение", "title": "Заголовок", "text": "Текст", "number": "Номер",
    "lessonTypeAbbrev": "Тип занятия", "type": "Тип", "name": "Название", "description": "Описание",
    "comment": "Комментарий", "createdDate": "Создано", "students": "Студенты", "subGroup": "Подгруппа",
]

private func skipKey(_ k: String) -> Bool {
    ["photoUrl", "photo", "authorities", "fullShow", "calendarId", "urlId", "hasNext", "totalElements"].contains(k)
        || k == "id" || k.hasSuffix("Id") || (k.hasPrefix("id") && k.count > 2 && k.dropFirst(2).first?.isUppercase == true)
}

private func primitiveText(_ v: JSON) -> String? {
    switch v {
    case .bool(let b): return b ? "да" : "нет"
    case .number(let n): return n
    case .string(let s): return s.isBlank || s == "null" ? nil : prettyValue(s)
    default: return nil
    }
}

/// Универсальный показ ответа, если раздел не удалось разобрать.
struct JsonView: View {
    @Environment(\.look) private var C
    let v: JSON
    let depth: Int

    var body: some View {
        if let a = v.items {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(a.indices, id: \.self) { i in
                    if let p = primitiveText(a[i]) {
                        Text("• \(p)").ct(14).foregroundStyle(C.ink)
                    } else if depth < 6 {
                        JsonView(v: a[i], depth: depth + 1)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(depth % 2 == 0 ? C.card : C.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        } else if let f = v.fields {
            let shown = f.filter { !skipKey($0.0) }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(shown.indices, id: \.self) { i in
                    let (k, child) = shown[i]
                    if let p = primitiveText(child) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(LABELS[k] ?? k).ct(13).foregroundStyle(C.muted).frame(maxWidth: .infinity, alignment: .leading)
                            Text(p).ct(14, .medium).foregroundStyle(C.ink).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if (child.items?.isEmpty == false || child.fields?.isEmpty == false) && depth < 6 {
                        Text(LABELS[k] ?? k).ct(13, .bold).foregroundStyle(C.ink).padding(.top, 6)
                        JsonView(v: child, depth: depth + 1)
                    }
                }
            }
        } else if let p = primitiveText(v) {
            Text(p).ct(14).foregroundStyle(C.ink)
        }
    }
}
