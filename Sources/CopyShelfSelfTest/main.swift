import CopyShelfCore
import Foundation

// Minimal test harness. Run with: swift run CopyShelfSelfTest

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passed = 0

func check(_ condition: @autoclosure () throws -> Bool, _ message: String, line: Int = #line) {
    do {
        if try condition() { passed += 1; return }
        print("  ✗ line \(line): \(message)")
    } catch {
        print("  ✗ line \(line): \(message) — threw \(error)")
    }
    failures += 1
}

func expectError(_ expected: ShelfError, _ message: String, line: Int = #line, _ body: () throws -> Void) {
    do {
        try body()
        print("  ✗ line \(line): \(message) — did not throw")
        failures += 1
    } catch let error as ShelfError where error == expected {
        passed += 1
    } catch {
        print("  ✗ line \(line): \(message) — threw \(error), expected \(expected)")
        failures += 1
    }
}

func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("copyshelf-test-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("copyshelf.json")
}

@MainActor func run() throws {
    print("• Creates an empty file on first launch")
    do {
        let url = tempFile()
        let store = ShelfStore(fileURL: url)
        check(store.items.isEmpty, "starts empty")
        check(store.loadError == nil, "no error")
        check(FileManager.default.fileExists(atPath: url.path), "file created")
        check(try ShelfStore.read(from: url).isEmpty, "file is a valid empty shelf")
    }

    print("• Add / edit / delete persist across relaunch")
    do {
        let url = tempFile()
        let store = ShelfStore(fileURL: url)
        let a = try store.add(title: "SSH", text: "ssh user@example.com")
        let b = try store.add(title: "Email", text: "me@example.com")
        try store.update(id: a.id, title: "SSH Server", text: "ssh root@example.com")
        try store.delete(id: b.id)

        let relaunched = ShelfStore(fileURL: url)
        check(relaunched.items.count == 1, "one item remains")
        check(relaunched.items.first?.title == "SSH Server", "title updated")
        check(relaunched.items.first?.text == "ssh root@example.com", "text updated")
        expectError(.itemNotFound, "editing a deleted item fails") {
            try relaunched.update(id: b.id, title: "x", text: "y")
        }
    }

    print("• Reads the JSON storage format")
    do {
        let json = """
        {
          "version": 1,
          "items": [
            { "id": "a-unique-id", "title": "SSH Server", "text": "ssh user@example.com" },
            { "id": "b", "title": "With desc", "text": "t", "description": "d" }
          ]
        }
        """
        let items = try ShelfFormat.decode(Data(json.utf8))
        check(items.count == 2, "two items")
        check(items[0] == ShelfItem(id: "a-unique-id", title: "SSH Server", text: "ssh user@example.com"), "fields")
        check(items[1].description == "d", "optional description kept")
    }

    print("• Writes the same format back (key order, no description when absent)")
    do {
        let out = String(decoding: try ShelfFormat.encode([ShelfItem(id: "x", title: "T", text: "a/b")]), as: UTF8.self)
        let id = out.range(of: "\"id\"")!.lowerBound
        let title = out.range(of: "\"title\"")!.lowerBound
        let text = out.range(of: "\"text\"")!.lowerBound
        check(id < title && title < text, "keys ordered id, title, text")
        check(!out.contains("description"), "no description key")
        check(out.contains("a/b"), "slashes not escaped")
        check(out.hasSuffix("\n"), "trailing newline")
        check(out.contains("\"version\" : 1") || out.contains("\"version\": 1"), "version 1")

        let exact = String(decoding: try ShelfFormat.encode([
            ShelfItem(id: "a-unique-id", title: "SSH Server", text: "ssh user@example.com"),
            ShelfItem(id: "b", title: "Quote \"q\"", text: "line1\nline2\ttab é", description: "d"),
        ]), as: UTF8.self)
        let expected = #"""
        {
          "version": 1,
          "items": [
            {
              "id": "a-unique-id",
              "title": "SSH Server",
              "text": "ssh user@example.com"
            },
            {
              "id": "b",
              "title": "Quote \"q\"",
              "text": "line1\nline2\ttab é",
              "description": "d"
            }
          ]
        }

        """#
        check(exact == expected, "byte-identical to JSON.stringify(data, null, 2)")
        check(String(decoding: try ShelfFormat.encode([]), as: UTF8.self) == "{\n  \"version\": 1,\n  \"items\": []\n}\n", "empty shelf matches")
    }

    print("• Rejects malformed data with standard error cases")
    expectError(.invalidJSON, "not JSON") { _ = try ShelfFormat.decode(Data("{nope".utf8)) }
    expectError(.invalidFormat, "wrong version") { _ = try ShelfFormat.decode(Data(#"{"version":2,"items":[]}"#.utf8)) }
    expectError(.invalidFormat, "missing items") { _ = try ShelfFormat.decode(Data(#"{"version":1}"#.utf8)) }
    expectError(.invalidFormat, "boolean version") { _ = try ShelfFormat.decode(Data(#"{"version":true,"items":[]}"#.utf8)) }
    expectError(.invalidItem(2), "blank title on item 2") {
        _ = try ShelfFormat.decode(Data(#"{"version":1,"items":[{"id":"a","title":"A","text":""},{"id":"b","title":"  ","text":""}]}"#.utf8))
    }
    expectError(.invalidItem(1), "empty id") {
        _ = try ShelfFormat.decode(Data(#"{"version":1,"items":[{"id":"","title":"A","text":""}]}"#.utf8))
    }
    expectError(.invalidItem(1), "non-string text") {
        _ = try ShelfFormat.decode(Data(#"{"version":1,"items":[{"id":"a","title":"A","text":5}]}"#.utf8))
    }
    expectError(.duplicateIDs, "duplicate ids") {
        _ = try ShelfFormat.decode(Data(#"{"version":1,"items":[{"id":"a","title":"A","text":""},{"id":"a","title":"B","text":""}]}"#.utf8))
    }

    print("• Never overwrites a malformed file")
    do {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("{ broken json".utf8)
        try broken.write(to: url)

        let store = ShelfStore(fileURL: url)
        check(store.loadError != nil, "reports the error")
        expectError(.storageLocked, "add is blocked") { try store.add(title: "x", text: "y") }
        check(try Data(contentsOf: url) == broken, "file bytes untouched")

        try store.replace(with: [ShelfItem(id: "r", title: "Recovered", text: "ok")])
        check(store.loadError == nil, "replace recovers")
        check(try ShelfStore.read(from: url).first?.title == "Recovered", "recovered file written")
    }

    print("• Merge keeps every item and re-IDs collisions")
    do {
        let store = ShelfStore(fileURL: tempFile())
        try store.replace(with: [ShelfItem(id: "a", title: "Mine", text: "1")])
        let added = try store.merge([
            ShelfItem(id: "a", title: "Theirs", text: "2"),
            ShelfItem(id: "b", title: "New", text: "3"),
        ])
        check(added == 2, "reports two imported")
        check(store.items.map(\.title) == ["Mine", "Theirs", "New"], "order preserved")
        check(Set(store.items.map(\.id)).count == 3, "ids unique")
        check(store.items[0].id == "a", "existing id kept")
        check(store.items[1].id != "a", "colliding id replaced")
        check(store.items[2].id == "b", "non-colliding id kept")
    }

    print("• Picks up hand edits to the JSON file")
    do {
        let url = tempFile()
        let store = ShelfStore(fileURL: url)
        try store.add(title: "Old", text: "")
        Thread.sleep(forTimeInterval: 1.1) // ensure a distinct modification time
        try ShelfFormat.encode([ShelfItem(id: "h", title: "Hand edited", text: "")]).write(to: url)
        store.reloadIfChanged()
        check(store.items.map(\.title) == ["Hand edited"], "external change loaded")
        try store.add(title: "After", text: "")
        check(try ShelfStore.read(from: url).map(\.title) == ["Hand edited", "After"], "edit not clobbered")
    }

    print("• Export writes a valid, importable file")
    do {
        let store = ShelfStore(fileURL: tempFile())
        try store.add(title: "One", text: "1")
        let dest = tempFile()
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try store.export(to: dest)
        check(try ShelfStore.read(from: dest) == store.items, "round-trips")
    }
}

do {
    try MainActor.assumeIsolated { try run() }
} catch {
    print("  ✗ unexpected error: \(error)")
    failures += 1
}

print(failures == 0 ? "\n✓ All \(passed) checks passed" : "\n✗ \(failures) failed, \(passed) passed")
exit(failures == 0 ? 0 : 1)
