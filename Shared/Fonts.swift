import SwiftUI

extension Font {
    /// Roboto нужного начертания (файлы в UniTime/Resources/Fonts) — шрифт Android-версии.
    /// Размер фиксированный, как sp в макете.
    static func roboto(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Roboto-Medium"
        case .semibold: name = "Roboto-SemiBold"
        case .bold: name = "Roboto-Bold"
        case .heavy: name = "Roboto-ExtraBold"
        case .black: name = "Roboto-Black"
        default: name = "Roboto-Regular"
        }
        return .custom(name, fixedSize: size)
    }
}
