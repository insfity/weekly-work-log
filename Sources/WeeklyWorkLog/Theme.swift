import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.25, green: 0.38, blue: 0.92)
    static let accentSoft = Color(red: 0.91, green: 0.93, blue: 1.0)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let card = Color(nsColor: .textBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static let secondaryText = Color.secondary
}

extension WorkStatus {
    var color: Color {
        switch self {
        case .completed: Color(red: 0.12, green: 0.64, blue: 0.38)
        case .inProgress: Color(red: 0.95, green: 0.57, blue: 0.13)
        case .blocked: Color(red: 0.91, green: 0.27, blue: 0.28)
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }
}

struct HoverHighlightModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(highlightColor)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: AppTheme.accent.opacity(isHovered && isEnabled ? 0.12 : 0),
                radius: 5,
                y: 1
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var highlightColor: Color {
        guard isHovered, isEnabled else { return .clear }
        return colorScheme == .dark
            ? Color.white.opacity(0.075)
            : Color.black.opacity(0.055)
    }
}

extension View {
    func appCard() -> some View {
        modifier(CardModifier())
    }

    func hoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius))
    }
}
