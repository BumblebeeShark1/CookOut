import SwiftUI

struct CookOutPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(2.4).foregroundStyle(.secondary)
            Text(title).font(CookOutTypography.display(40, relativeTo: .largeTitle))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.body).foregroundStyle(.secondary).frame(maxWidth: 620, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CookOutPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var subtitle: String = ""
    var symbol: String = ""
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !title.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if !symbol.isEmpty {
                        Image(systemName: symbol).font(.title3.weight(.light)).foregroundStyle(.secondary)
                            .frame(width: 28, height: 30)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(CookOutTypography.display(24, relativeTo: .title2))
                        if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .background(CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(CookOutTheme.border(for: colorScheme)) }
    }
}

struct CookOutScreen<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(28).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }.cookOutCanvas()
    }
}

struct CookOutEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(title).font(CookOutTypography.display(30, relativeTo: .title)).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
        }.frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 20)
    }
}

struct CookOutFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(CookOutTheme.border(for: colorScheme)) }
    }
}

extension View {
    func cookOutField() -> some View { modifier(CookOutFieldStyle()) }

    @ViewBuilder func cookOutSheetFrame(width: CGFloat = 720, height: CGFloat = 740) -> some View {
#if os(macOS)
        frame(minWidth: width, minHeight: height)
#else
        self
#endif
    }
}
