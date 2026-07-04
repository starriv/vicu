import Foundation

struct AlpacaNewsResponse: Decodable, Sendable {
    let news: [AlpacaNewsArticle]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case news
        case nextPageToken = "next_page_token"
    }
}

struct AlpacaNewsPage: Sendable {
    let articles: [AlpacaNewsArticle]
    let nextPageToken: String?
}

struct AlpacaNewsArticle: Decodable, Identifiable, Equatable, Sendable {
    let articleID: String?
    let headline: String?
    let summary: String?
    let author: String?
    let createdAt: String?
    let updatedAt: String?
    let url: String?
    let symbols: [String]
    let source: String?

    var id: String {
        articleID ?? [
            headline ?? "",
            updatedAt ?? createdAt ?? "",
            url ?? ""
        ].joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case headline
        case summary
        case author
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case url
        case symbols
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleID = Self.decodeStringOrInteger(container, forKey: .id)
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        symbols = (try? container.decode([String].self, forKey: .symbols)) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    private static func decodeStringOrInteger(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let value = try? container.decode(String.self, forKey: key), !value.isEmpty {
            return value
        }

        if let value = try? container.decode(Int.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}
