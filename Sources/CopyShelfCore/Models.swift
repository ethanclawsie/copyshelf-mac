import Foundation

/// A single saved snippet. Field names and order match the VS Code extension's `copyshelf.json`.
public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var description: String?

    public init(id: String = UUID().uuidString.lowercased(), title: String, text: String, description: String? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.description = description
    }
}

public enum ShelfError: LocalizedError, Equatable {
    case invalidJSON
    case invalidFormat
    case invalidItem(Int)
    case duplicateIDs
    case itemNotFound
    case storageLocked

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: "The CopyShelf file is not valid JSON. Your file was left unchanged."
        case .invalidFormat: "The CopyShelf file must contain version 1 and an items array."
        case .invalidItem(let n): "CopyShelf item \(n) is invalid."
        case .duplicateIDs: "The CopyShelf file contains duplicate item IDs."
        case .itemNotFound: "That item no longer exists."
        case .storageLocked: "The storage file has errors. Fix it or import a valid file before making changes."
        }
    }
}

/// Reading and writing the on-disk format: `{ "version": 1, "items": [...] }`.
public enum ShelfFormat {
    public static func decode(_ data: Data) throws -> [ShelfItem] {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch DecodingError.dataCorrupted {
            throw ShelfError.invalidJSON
        } catch {
            throw ShelfError.invalidFormat
        }
        guard file.version == 1 else { throw ShelfError.invalidFormat }

        var items: [ShelfItem] = []
        items.reserveCapacity(file.items.count)
        for (index, raw) in file.items.enumerated() {
            guard let item = raw.item,
                  !item.id.isEmpty,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ShelfError.invalidItem(index + 1) }
            items.append(item)
        }

        guard Set(items.map(\.id)).count == items.count else { throw ShelfError.duplicateIDs }
        return items
    }

    /// Produces the same bytes as the extension's `JSON.stringify(data, null, 2) + "\n"`.
    /// (JSONEncoder doesn't guarantee key order, so the layout is written by hand.)
    public static func encode(_ items: [ShelfItem]) throws -> Data {
        guard !items.isEmpty else { return Data("{\n  \"version\": 1,\n  \"items\": []\n}\n".utf8) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        func quoted(_ s: String) throws -> String { String(decoding: try encoder.encode(s), as: UTF8.self) }

        var out = "{\n  \"version\": 1,\n  \"items\": [\n"
        for (index, item) in items.enumerated() {
            out += "    {\n"
            out += "      \"id\": \(try quoted(item.id)),\n"
            out += "      \"title\": \(try quoted(item.title)),\n"
            out += "      \"text\": \(try quoted(item.text))"
            if let description = item.description {
                out += ",\n      \"description\": \(try quoted(description))"
            }
            out += index == items.count - 1 ? "\n    }\n" : "\n    },\n"
        }
        out += "  ]\n}\n"
        return Data(out.utf8)
    }

    private struct RawFile: Decodable {
        let version: Int
        let items: [LenientItem]
    }

    /// Decodes an item without failing the whole array, so we can report which index is bad.
    private struct LenientItem: Decodable {
        let item: ShelfItem?
        init(from decoder: Decoder) throws {
            item = try? ShelfItem(from: decoder)
        }
    }
}
