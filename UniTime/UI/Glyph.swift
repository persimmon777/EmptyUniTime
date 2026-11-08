import SwiftUI

/// Линейные иконки 24×24 — те же, что в Android-версии (Icons.kt), координата в координату.
enum GlyphKind {
    case clock, calendar, doc, search, back, bell, star, starFilled, chevron, cap, gear, plus, check, people, pin, eyeOff, flag, trash, user, arrowUp
}

struct GlyphShape: Shape {
    let kind: GlyphKind

    func path(in rect: CGRect) -> Path {
        let k = rect.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var p = Path()
        func line(_ pts: CGFloat..., close: Bool = false) {
            p.move(to: pt(pts[0], pts[1]))
            var i = 2
            while i < pts.count { p.addLine(to: pt(pts[i], pts[i + 1])); i += 2 }
            if close { p.closeSubpath() }
        }
        func circle(_ r: CGFloat, _ cx: CGFloat, _ cy: CGFloat) {
            p.addEllipse(in: CGRect(x: rect.minX + (cx - r) * k, y: rect.minY + (cy - r) * k, width: 2 * r * k, height: 2 * r * k))
        }
        func curve(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            p.addCurve(to: pt(x, y), control1: pt(x1, y1), control2: pt(x2, y2))
        }
        switch kind {
        case .clock:
            circle(9, 12, 12)
            line(12, 7, 12, 12, 15, 14)
        case .calendar:
            p.addRoundedRect(in: CGRect(x: rect.minX + 3 * k, y: rect.minY + 5 * k, width: 18 * k, height: 16 * k), cornerSize: CGSize(width: 3 * k, height: 3 * k))
            line(3, 10, 21, 10); line(8, 3, 8, 7); line(16, 3, 16, 7)
        case .doc:
            line(4, 4, 16, 4, 20, 8, 20, 20, 4, 20, close: true)
            line(8, 12, 16, 12); line(8, 16, 13, 16)
        case .search:
            circle(7, 11, 11)
            line(20, 20, 16, 16)
        case .back: line(15, 5, 8, 12, 15, 19)
        case .chevron: line(9, 5, 16, 12, 9, 19)
        case .bell:
            p.move(to: pt(6, 16)); p.addLine(to: pt(6, 9))
            curve(6, 1, 18, 1, 18, 9)
            p.addLine(to: pt(18, 16)); p.addLine(to: pt(20, 18)); p.addLine(to: pt(4, 18)); p.closeSubpath()
            line(10, 21, 14, 21)
        case .star, .starFilled:
            line(12, 3, 14.8, 8.8, 21, 9.3, 16.3, 13.5, 17.7, 19.8, 12, 16.5, 6.3, 19.8, 7.7, 13.5, 3, 9.3, 9.2, 8.8, close: true)
        case .gear:
            circle(3, 12, 12)
            circle(8, 12, 12)
            for a in 0..<8 {
                let r = Double(a) * .pi / 4
                let c = CGFloat(cos(r)), s = CGFloat(sin(r))
                line(12 + 8 * c, 12 + 8 * s, 12 + 10.5 * c, 12 + 10.5 * s)
            }
        case .plus: line(12, 5, 12, 19); line(5, 12, 19, 12)
        case .check: line(5, 12.5, 10, 17.5, 19, 7)
        case .people:
            circle(3.5, 9, 8)
            p.move(to: pt(2.5, 20)); curve(2.5, 13, 15.5, 13, 15.5, 20)
            circle(3, 17, 9)
            p.move(to: pt(17, 14.5)); curve(20, 14.5, 22, 16.5, 22, 20)
        case .pin:
            p.move(to: pt(12, 21))
            curve(5, 14, 5, 10, 5, 9.5)
            curve(5, 0.5, 19, 0.5, 19, 9.5)
            curve(19, 10, 19, 14, 12, 21)
            p.closeSubpath()
            circle(2.5, 12, 9.5)
        case .eyeOff:
            p.move(to: pt(2, 12)); curve(6, 5, 18, 5, 22, 12); curve(18, 19, 6, 19, 2, 12); p.closeSubpath()
            circle(3, 12, 12)
            line(4, 4, 20, 20)
        case .flag: line(5, 21, 5, 4); line(5, 4, 18, 4, 15, 8.5, 18, 13, 5, 13)
        case .trash:
            line(4, 7, 20, 7); line(9, 7, 9, 4, 15, 4, 15, 7)
            line(6, 7, 7, 20, 17, 20, 18, 7)
        case .user:
            circle(4, 12, 8)
            p.move(to: pt(4, 21)); curve(4, 13, 20, 13, 20, 21)
        case .arrowUp: line(12, 19, 12, 5); line(6, 11, 12, 5, 18, 11)
        case .cap:
            line(12, 4, 2, 9, 12, 14, 22, 9, close: true)
            line(6, 11.5, 6, 16, 12, 19, 18, 16, 18, 11.5)
        }
        return p
    }
}

struct Glyph: View {
    let kind: GlyphKind
    let color: Color
    var size: CGFloat = 24

    init(_ kind: GlyphKind, _ color: Color, _ size: CGFloat = 24) {
        self.kind = kind
        self.color = color
        self.size = size
    }

    var body: some View {
        let shape = GlyphShape(kind: kind)
        ZStack {
            if kind == .starFilled { shape.fill(color) }
            shape.stroke(color, style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
