import SwiftUI

extension Font {
    /// Dynamically scaled system font respecting user preference (Cmd+ / Cmd-)
    @MainActor
    public static func scaled(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        let scale = SecAppStore.shared.fontScale
        let scaledSize = max(8, round(size * scale * 10) / 10)
        return .system(size: scaledSize, weight: weight, design: design)
    }
}
