import Foundation

/// JSON с сохранением порядка ключей (ответы IIS показываются в том порядке, в каком пришли).
indirect enum JSON {
    case null
    case bool(Bool)
    /// Число храним как текст из ответа, чтобы «5» не превратилось в «5.0».
    case number(String)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    // MARK: Разбор

    static func parse(_ data: Data) -> JSON? {
        var p = Parser(bytes: [UInt8](data))
        p.skipSpace()
        guard let v = p.value() else { return nil }
        return v
    }

    static func parse(_ s: String) -> JSON? { parse(Data(s.utf8)) }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func skipSpace() {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09 { i += 1 }
        }

        mutating func value() -> JSON? {
            skipSpace()
            guard i < bytes.count else { return nil }
            switch bytes[i] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string().map { .string($0) }
            case UInt8(ascii: "t"): return literal("true", .bool(true))
            case UInt8(ascii: "f"): return literal("false", .bool(false))
            case UInt8(ascii: "n"): return literal("null", .null)
            default: return number()
            }
        }

        mutating func literal(_ word: String, _ v: JSON) -> JSON? {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { return nil }
            i += w.count
            return v
        }

        mutating func number() -> JSON? {
            let start = i
            while i < bytes.count {
                let c = bytes[i]
                if (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
                    i += 1
                } else { break }
            }
            guard i > start else { return nil }
            return .number(String(decoding: bytes[start..<i], as: UTF8.self))
        }

        mutating func hex4() -> UInt32? {
            guard i + 4 <= bytes.count else { return nil }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = bytes[i]
                i += 1
                v <<= 4
                switch c {
                case 0x30...0x39: v |= UInt32(c - 0x30)
                case 0x41...0x46: v |= UInt32(c - 0x41 + 10)
                case 0x61...0x66: v |= UInt32(c - 0x61 + 10)
                default: return nil
                }
            }
            return v
        }

        mutating func string() -> String? {
            i += 1 // открывающая кавычка
            var out = [UInt8]()
            while i < bytes.count {
                let c = bytes[i]
                if c == UInt8(ascii: "\"") {
                    i += 1
                    return String(decoding: out, as: UTF8.self)
                }
                if c == UInt8(ascii: "\\") {
                    i += 1
                    guard i < bytes.count else { return nil }
                    let e = bytes[i]
                    i += 1
                    switch e {
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "u"):
                        guard var code = hex4() else { return nil }
                        if code >= 0xD800 && code < 0xDC00, i + 6 <= bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                            i += 2
                            if let low = hex4(), low >= 0xDC00 && low < 0xE000 {
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            }
                        }
                        let scalar = Unicode.Scalar(code) ?? "?"
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default: out.append(e)
                    }
                    continue
                }
                out.append(c)
                i += 1
            }
            return nil
        }

        mutating func array() -> JSON? {
            i += 1
            var list = [JSON]()
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(list) }
            while i < bytes.count {
                guard let v = value() else { return nil }
                list.append(v)
                skipSpace()
                guard i < bytes.count else { return nil }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(list) }
                return nil
            }
            return nil
        }

        mutating func object() -> JSON? {
            i += 1
            var fields = [(String, JSON)]()
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(fields) }
            while i < bytes.count {
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\""), let key = string() else { return nil }
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
                i += 1
                guard let v = value() else { return nil }
                fields.append((key, v))
                skipSpace()
                guard i < bytes.count else { return nil }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(fields) }
                return nil
            }
            return nil
        }
    }

    // MARK: Доступ

    var isNull: Bool { if case .null = self { return true }; return false }

    var fields: [(String, JSON)]? { if case .object(let f) = self { return f }; return nil }
    var items: [JSON]? { if case .array(let a) = self { return a }; return nil }
    var isObject: Bool { fields != nil }
    var isArray: Bool { items != nil }

    var keys: [String] { fields?.map { $0.0 } ?? [] }

    subscript(key: String) -> JSON? {
        guard let f = fields else { return nil }
        return f.first { $0.0 == key }?.1
    }

    func has(_ key: String) -> Bool { self[key] != nil }

    /// Объекты внутри массива.
    var objects: [JSON] { items?.filter { $0.isObject } ?? [] }

    /// Значение-примитив как строка (как optString у org.json). null и вложенные — nil.
    var primitiveString: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// Поле-примитив как строка; отсутствует или null — nil (как `str()` в разборе расписания).
    func opt(_ key: String) -> String? {
        guard let v = self[key], !v.isNull else { return nil }
        return v.primitiveString ?? ""
    }

    func int(_ key: String, _ def: Int = 0) -> Int {
        guard let v = self[key] else { return def }
        switch v {
        case .number(let n): return Int(n) ?? Int(Double(n) ?? Double(def))
        case .string(let s): return Int(s) ?? def
        case .bool(let b): return b ? 1 : 0
        default: return def
        }
    }

    func bool(_ key: String) -> Bool {
        guard let v = self[key] else { return false }
        switch v {
        case .bool(let b): return b
        case .string(let s): return s.lowercased() == "true"
        case .number(let n): return n != "0"
        default: return false
        }
    }

    /// Первое непустое из полей (как `str(vararg)` в кабинете). Вложенный объект — его name/title/value/fio/number.
    func str(_ keys: String...) -> String { str(keys) }

    func str(_ keys: [String]) -> String {
        for k in keys {
            guard let v = self[k], !v.isNull else { continue }
            let s: String
            switch v {
            case .object: s = v.str("name", "title", "value", "fio", "number")
            case .array: s = v.description
            default: s = v.primitiveString ?? ""
            }
            if !s.trimmingCharacters(in: .whitespaces).isEmpty && s != "null" { return s }
        }
        return ""
    }

    /// Компактная запись JSON — для «скопировать данные для отладки».
    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s):
            let esc = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(esc)\""
        case .array(let a): return "[" + a.map { $0.description }.joined(separator: ",") + "]"
        case .object(let f): return "{" + f.map { "\"\($0.0)\":\($0.1.description)" }.joined(separator: ",") + "}"
        }
    }
}

/// Первый массив объектов в ответе (сам ответ, если это массив); сначала — по предпочтительным ключам.
func listIn(_ v: JSON?, _ prefer: String...) -> [JSON] { listIn(v, prefer) }

func listIn(_ v: JSON?, _ prefer: [String]) -> [JSON] {
    guard let v = v else { return [] }
    if let a = v.items { return a.filter { $0.isObject } }
    guard let fields = v.fields else { return [] }
    for k in prefer {
        if let list = v[k]?.objects, !list.isEmpty { return list }
    }
    for (_, child) in fields {
        if let a = child.items {
            let objs = a.filter { $0.isObject }
            if !objs.isEmpty { return objs }
        }
    }
    return []
}
