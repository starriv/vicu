import SwiftUI

struct SymbolLogoView: View {
    let symbol: String
    let size: CGFloat

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if shouldUseLogoDev {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        logoContainer {
                            image
                                .resizable()
                                .scaledToFill()
                        }
                    default:
                        generatedBadge
                    }
                }
            } else {
                generatedBadge
            }
        }
        .frame(width: size, height: size)
    }

    private func logoContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: size, height: size)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(logoShape)
    }

    @ViewBuilder
    private var generatedBadge: some View {
        if #available(iOS 26.0, *) {
            generatedBadgeContent
                .glassEffect(.regular.tint(glassTint), in: .rect(cornerRadius: size * 0.28))
        } else {
            generatedBadgeContent
                .background(.regularMaterial, in: logoShape)
        }
    }

    private var generatedBadgeContent: some View {
        ZStack {
            logoShape
                .fill(materialBacking)

            Text(symbolMark)
                .font(.system(size: symbolMarkFontSize, weight: .black, design: .rounded))
                .foregroundStyle(.primary.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, symbolMarkHorizontalPadding)
        }
        .frame(width: size, height: size)
        .overlay {
            logoShape
                .strokeBorder(Color(.separator).opacity(borderOpacity), lineWidth: max(0.7, size * 0.014))
        }
    }

    private var logoShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    private var glassTint: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }

    private var materialBacking: Color {
        colorScheme == .light ? Color(.systemFill).opacity(0.46) : Color(.secondarySystemFill).opacity(0.70)
    }

    private var borderOpacity: Double {
        colorScheme == .light ? 0.22 : 0.16
    }

    private var normalizedSymbol: String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var symbolMark: String {
        let primarySymbol = normalizedSymbol
            .split { character in
                character == "." || character == "/" || character == "-"
            }
            .first
            .map(String.init) ?? normalizedSymbol
        let compactSymbol = primarySymbol.filter { character in
            character.isLetter || character.isNumber
        }
        let fallbackSymbol = normalizedSymbol.filter { character in
            character.isLetter || character.isNumber
        }
        let mark = compactSymbol.isEmpty ? fallbackSymbol : compactSymbol

        guard !mark.isEmpty else {
            return "?"
        }

        return mark.count <= 4 ? mark : String(mark.prefix(4))
    }

    private var symbolMarkFontSize: CGFloat {
        switch symbolMark.count {
        case 0...2:
            max(10, size * 0.34)
        case 3:
            max(9, size * 0.29)
        default:
            max(8, size * 0.26)
        }
    }

    private var symbolMarkHorizontalPadding: CGFloat {
        switch symbolMark.count {
        case 0...2:
            max(3, size * 0.10)
        case 3:
            max(3, size * 0.08)
        default:
            max(2, size * 0.06)
        }
    }

    private var logoURL: URL? {
        guard !normalizedSymbol.isEmpty, !logoDevAPIKey.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.logo.dev"
        components.path = "/ticker/\(normalizedSymbol)"
        components.queryItems = [
            URLQueryItem(name: "token", value: logoDevAPIKey),
            URLQueryItem(name: "size", value: String(Int(ceil(size * 2)))),
            URLQueryItem(name: "format", value: "png"),
            URLQueryItem(name: "retina", value: "true"),
            URLQueryItem(name: "theme", value: "dark"),
            URLQueryItem(name: "fallback", value: "404")
        ]
        return components.url
    }

    private var shouldUseLogoDev: Bool {
        app.isLogoDevEnabled && !logoDevAPIKey.isEmpty
    }

    private var logoDevAPIKey: String {
        app.trimmedLogoDevAPIKey
    }

}
