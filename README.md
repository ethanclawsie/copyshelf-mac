# CopyShelf for macOS

A tiny menu bar app for keeping reusable text close at hand. Click the icon, click an item, and it's on your clipboard — ready to paste into any app.

Native SwiftUI, zero external dependencies, no Dock icon, no background polling. Requires an Apple Silicon Mac on macOS 14+.

## Zero Bloat by Design

Most modern clipboard and snippet utilities bundle an entire browser engine just to show a list of strings. CopyShelf is built from scratch in native Swift:

- **528 KB Total Bundle Size**: The executable itself is **304 KB** (fits on a floppy disk).
- **0.0% Idle CPU**: Pure event-driven architecture. Zero background polling, zero timers, zero disk watchers. It only executes code when you click or press your shortcut.
- **100% Offline & Private**: Zero network permissions, zero telemetry, zero analytics. Your snippets are stored locally in a plain `copyshelf.json` file you own and control.
- **Zero External Dependencies**: Pure Apple Silicon (`arm64`), built strictly against native macOS frameworks.

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
- **Search & Filter**: Type in the search bar to filter instantly. Press **Return** to copy the top match, or **Esc** to clear/dismiss.
- **Reorder**: Drag and drop items to reorder them, use the hover arrows, or right-click any item for Move Up / Move Down.
- **+** adds an item; the **pencil** edits it inline; the **trash** deletes it (with confirmation).
- The **chevron** expands a preview of the full text.
- **Mouse Button Popup**: Choose **Set Popup Mouse Button…** in the **⋯** menu to bind any mouse button (e.g. middle-click or side buttons) to summon the shelf right at your cursor.
- The **⋯** menu has: Launch at Login, Close After Copying, Set Popup Mouse Button…, Open Storage File, Reveal in Finder, Import…, Export…, Quit.

## Storage

Items are saved to:

```
~/Library/Application Support/CopyShelf/copyshelf.json
```

It's a plain, readable JSON file:

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
