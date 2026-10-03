import Foundation
import Observation

/// Owns the shelf: an in-memory copy of the items plus the JSON file on disk.
///
/// Performance notes: the file is read once at launch and then only re-read when its
/// modification date changes (checked when the panel opens and before each edit), so
/// hand edits to the JSON are picked up without polling or file watchers.
@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []
    /// Set when the storage file is malformed. While set, all writes are blocked so the
    /// user's file is never silently overwritten.
    public private(set) var loadError: String?

    public let fileURL: URL
    @ObservationIgnored private var loadedModificationDate: Date?

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CopyShelf", isDirectory: true)
            .appendingPathComponent("copyshelf.json")
    }

    public init(fileURL: URL = ShelfStore.defaultFileURL) {
        self.fileURL = fileURL
        reload()
    }

    // MARK: Loading

    /// Re-reads the file only if it changed on disk since we last read or wrote it.
    public func reloadIfChanged() {
        if modificationDate() != loadedModificationDate || loadError != nil {
            reload()
        }
    }

    public func reload() {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: fileURL.path) {
                try write([]) // create an empty shelf, like the VS Code extension
                items = []
                loadError = nil
                return
            }
            let data = try Data(contentsOf: fileURL)
            items = try ShelfFormat.decode(data)
            loadError = nil
            loadedModificationDate = modificationDate()
        } catch {
            items = []
            loadError = error.localizedDescription
            loadedModificationDate = modificationDate()
        }
    }

    // MARK: Mutations

    @discardableResult
    public func add(title: String, text: String) throws -> ShelfItem {
        let item = ShelfItem(title: title, text: text)
        try mutate { $0.append(item) }
        return item
    }

    public func update(id: String, title: String, text: String) throws {
        try mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { throw ShelfError.itemNotFound }
            items[index].title = title
            items[index].text = text
        }
    }

    public func delete(id: String) throws {
        try mutate { $0.removeAll { $0.id == id } }
    }

    /// Replaces the whole shelf. Allowed even when the current file is malformed — this is
    /// the documented way to recover.
    public func replace(with newItems: [ShelfItem]) throws {
        try write(newItems)
        items = newItems
        loadError = nil
    }

    /// Appends imported items, assigning a fresh ID to any that collide. Returns the count added.
    @discardableResult
    public func merge(_ imported: [ShelfItem]) throws -> Int {
        try mutate { items in
            var ids = Set(items.map(\.id))
            for var item in imported {
                while ids.contains(item.id) { item.id = UUID().uuidString.lowercased() }
                ids.insert(item.id)
                items.append(item)
            }
        }
        return imported.count
    }

    // MARK: Import / export

    public static func read(from url: URL) throws -> [ShelfItem] {
        try ShelfFormat.decode(Data(contentsOf: url))
    }

    public func export(to url: URL) throws {
        reloadIfChanged()
        if let loadError { throw ExportError(message: loadError) }
        try ShelfFormat.encode(items).write(to: url, options: .atomic)
    }

    // MARK: Private

    private func mutate(_ change: (inout [ShelfItem]) throws -> Void) throws {
        reloadIfChanged()
        guard loadError == nil else { throw ShelfError.storageLocked }
        var copy = items
        try change(&copy)
        try write(copy)
        items = copy
    }

    private func write(_ items: [ShelfItem]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ShelfFormat.encode(items).write(to: fileURL, options: .atomic) // temp file + rename
        loadedModificationDate = modificationDate()
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }
}

private struct ExportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
