# CopyShelf for macOS

A tiny menu bar app for keeping reusable text close at hand. Click the icon, click an item, and it's on your clipboard — ready to paste into any app.

Native SwiftUI, no dependencies, no Dock icon, no background polling. Requires an Apple Silicon Mac on macOS 14+.

## Install

```sh
brew install --cask ethanclawsie/tap/copyshelf
```

Update with `brew upgrade --cask copyshelf`.

<details>
<summary>Manual install (zip)</summary>

Download `CopyShelf-x.y.z.zip` from [Releases](https://github.com/ethanclawsie/copyshelf-mac/releases), unzip, and move `CopyShelf.app` to `/Applications`.

The app isn't notarized, so macOS blocks the first launch. Either open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/CopyShelf.app
```
</details>

## Using CopyShelf

- **Click an item** (or its copy icon) to copy its text. By default the panel closes so you can paste right away with ⌘V.
- **+** adds an item; the **pencil** edits it inline; the **trash** deletes it (with confirmation).
- The **chevron** expands a preview of the full text.
- The **⋯** menu has: Launch at Login, Close After Copying, Open Storage File, Reveal in Finder, Import…, Export…, Quit.

## Storage

Items are saved to:

```
~/Library/Application Support/CopyShelf/copyshelf.json
```

It uses the same format as the CopyShelf VS Code extension, so files can be imported/exported between them (the two keep separate shelves):

```json
{
  "version": 1,
  "items": [
    {
      "id": "a-unique-id",
      "title": "SSH Server",
      "text": "ssh user@example.com"
    }
  ]
}
```

You can edit the file by hand; changes are picked up the next time you open the panel. A malformed file is **never silently overwritten** — the panel shows the error with shortcuts to fix it.

Import can **merge** (keeps every item; colliding IDs are reassigned) or **replace** the shelf.

## Development

Requires macOS 14+ and Swift 6 (Xcode Command Line Tools are enough).

```sh
swift run CopyShelfSelfTest     # tests
swift run CopyShelf             # run unbundled (Launch at Login won't work)
scripts/build-app.sh            # universal, ad-hoc signed dist/CopyShelf.app
open dist/CopyShelf.app
```

| Path | Purpose |
|---|---|
| `Sources/CopyShelfCore` | Model, JSON format, storage (no UI) |
| `Sources/CopyShelf` | Menu bar app (SwiftUI) |
| `Sources/CopyShelfSelfTest` | Dependency-free test runner |
| `scripts/make-icon.swift` | Regenerates `Resources/AppIcon.icns` |
| `scripts/release.sh` | Build → GitHub Release → update Homebrew tap |
| `packaging/copyshelf.rb` | Cask template |

### Releasing

```sh
scripts/release.sh 0.2.0
```
