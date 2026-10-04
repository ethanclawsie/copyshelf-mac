import AppKit
import CopyShelfCore
import SwiftUI
import UniformTypeIdentifiers

/// The shelf UI, shown from the menu bar icon and in the cursor popup.
struct ShelfView: View {
    let store: ShelfStore
    let trigger: MouseTrigger
    /// Set in the cursor popup: called once an action completes (copy, add, edit) to close it.
    var onFinish: (() -> Void)?

    @AppStorage("closeAfterCopy") private var closeAfterCopy = true
    @State private var editing: Editing?
    @State private var expanded: Set<String> = []
    @State private var copiedID: String?
    @State private var confirmingDeleteID: String?
    @State private var inlineError: String?
    @State private var listHeight: CGFloat = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showPermissionHint = false

    private enum Editing: Equatable {
        case new
        case item(String)
    }

    private let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let loadError = store.loadError {
                loadErrorBanner(loadError)
            }

            if trigger.isRecording {
                notice("Press the mouse button to use for the popup…", systemImage: "computermouse") {
                    Button("Cancel") { trigger.cancelRecording() }
                }
            } else if showPermissionHint || trigger.needsPermission {
                notice("Allow CopyShelf in Accessibility settings to use a popup mouse button, then try again.",
                       systemImage: "lock") {
                    Button("Open Settings") { MouseTrigger.openAccessibilitySettings() }
                }
            }

            if editing == .new {
                EditorForm(title: "", text: "", saveLabel: "Add") { title, text in
                    if perform({ try store.add(title: title, text: text) }) { onFinish?() }
                } onCancel: {
                    editing = nil
                }
                Divider()
            }

            if store.items.isEmpty {
                if editing == nil && store.loadError == nil { emptyState }
            } else {
                itemList
            }

            if let inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("CopyShelf").font(.headline)
            Spacer()
            Button {
                inlineError = nil
                editing = .new
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(IconButtonStyle())
            .help("Add Item")
            .disabled(store.loadError != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.items) { item in
                    if editing == .item(item.id) {
                        EditorForm(title: item.title, text: item.text, saveLabel: "Save") { title, text in
                            if perform({ try store.update(id: item.id, title: title, text: text) }) { onFinish?() }
                        } onCancel: {
                            editing = nil
                        }
                    } else {
                        ItemRow(
                            item: item,
                            isExpanded: expanded.contains(item.id),
                            isCopied: copiedID == item.id,
                            isConfirmingDelete: confirmingDeleteID == item.id,
                            onCopy: { copy(item) },
                            onToggle: { toggle(item.id) },
                            onEdit: {
                                inlineError = nil
                                confirmingDeleteID = nil
                                editing = .item(item.id)
                            },
                            onDelete: { confirmingDeleteID = item.id },
                            onConfirmDelete: {
                                confirmingDeleteID = nil
                                perform { try store.delete(id: item.id) }
                            },
                            onCancelDelete: { confirmingDeleteID = nil }
                        )
                    }
                    if item.id != store.items.last?.id { Divider().padding(.horizontal, 10) }
                }
            }
            .padding(.vertical, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .frame(height: min(max(listHeight, 1), maxListHeight))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Your shelf is empty").font(.callout.weight(.medium))
            Text("Save text you use often, then click it to copy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Item") { editing = .new }
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
    }

    private func loadErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open File") { NSWorkspace.shared.open(store.fileURL) }
                Button("Reveal in Finder") { revealStorage() }
                Spacer()
                Button("Retry") { store.reload() }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private func notice<Actions: View>(
        _ message: String, systemImage: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 8) {
            Label(message, systemImage: systemImage)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            actions().controlSize(.small)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.1))
    }

    private var footer: some View {
        HStack {
            Text(store.items.count == 1 ? "1 item" : "\(store.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                Toggle("Close After Copying", isOn: $closeAfterCopy)
                Divider()
                if let button = trigger.button {
                    Text("Popup Button: \(MouseTrigger.name(of: button))")
                    Button("Change Popup Button…", action: recordButton)
                    Button("Remove Popup Button") { trigger.clear() }
                } else {
                    Button("Set Popup Mouse Button…", action: recordButton)
                }
                Divider()
                Button("Open Storage File") { NSWorkspace.shared.open(store.fileURL) }
                Button("Reveal in Finder") { revealStorage() }
                Divider()
                Button("Import…", action: importShelf)
                Button("Export…", action: exportShelf)
                Divider()
                Button("Quit CopyShelf") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: Actions

    private func refresh() {
        store.reloadIfChanged()
        launchAtLogin = LaunchAtLogin.isEnabled
        trigger.refresh()
        if AXIsProcessTrusted() { showPermissionHint = false }
    }

    private func recordButton() {
        showPermissionHint = !trigger.startRecording()
    }

    private func copy(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)

        if let onFinish { return onFinish() } // popup: close right away

        copiedID = item.id
        Task {
            // Brief ✓ flash, then optionally close so ⌘V goes straight to the previous app.
            try? await Task.sleep(for: .milliseconds(closeAfterCopy ? 350 : 1200))
            if copiedID == item.id { copiedID = nil }
            if closeAfterCopy { NSApp.keyWindow?.close() }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Runs a store mutation; on success leaves edit mode, on failure shows the error inline.
    @discardableResult
    private func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            editing = nil
            inlineError = nil
            return true
        } catch {
            inlineError = error.localizedDescription
            return false
        }
    }

    private func revealStorage() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            presentAlert("Couldn't change Launch at Login", error.localizedDescription)
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func importShelf() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Import CopyShelf"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let imported = try ShelfStore.read(from: url)
            let alert = NSAlert()
            alert.messageText = "Import \(imported.count) item\(imported.count == 1 ? "" : "s")?"
            alert.informativeText = "Merge adds them to your shelf. Replace Existing discards your current items."
            alert.addButton(withTitle: "Merge")
            alert.addButton(withTitle: "Replace Existing")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: try store.merge(imported)
            case .alertSecondButtonReturn: try store.replace(with: imported)
            default: return
            }
        } catch {
            presentAlert("Import failed", error.localizedDescription)
        }
    }

    private func exportShelf() {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.title = "Export CopyShelf"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "copyshelf.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.export(to: url)
        } catch {
            presentAlert("Export failed", error.localizedDescription)
        }
    }

    private func presentAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: ShelfItem
    let isExpanded: Bool
    let isCopied: Bool
    let isConfirmingDelete: Bool
    let onCopy: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Collapse" : "Preview")

                // The whole title area copies on click — the fast path.
                Button(action: onCopy) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .lineLimit(1)
                        if !isExpanded {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to copy")

                Group {
                    Button(action: onCopy) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(isCopied ? Color.green : Color.primary)
                    }
                    .help("Copy")
                    Button(action: onEdit) { Image(systemName: "pencil") }
                        .help("Edit")
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help("Delete")
                }
                .buttonStyle(IconButtonStyle())
                .opacity(isHovering || isCopied ? 1 : 0.55)
            }

            if isExpanded {
                Text(item.text.isEmpty ? "(empty)" : item.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(item.text.isEmpty ? .secondary : .primary)
                    .lineLimit(14)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .padding(.leading, 20)
            }

            if isConfirmingDelete {
                HStack {
                    Text("Delete “\(item.title)”?")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Cancel", action: onCancelDelete)
                    Button("Delete", role: .destructive, action: onConfirmDelete)
                        .tint(.red)
                }
                .controlSize(.small)
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }

    private var preview: String {
        let collapsed = item.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? "(empty)" : String(collapsed.prefix(80))
    }
}

// MARK: - Inline editor

private struct EditorForm: View {
    @State private var title: String
    @State private var text: String
    @FocusState private var focusedField: Field?
    let saveLabel: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    private enum Field { case title, text }

    init(
        title: String, text: String, saveLabel: String,
        onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void
    ) {
        _title = State(initialValue: title)
        _text = State(initialValue: text)
        self.saveLabel = saveLabel
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
                .onSubmit { focusedField = .text }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .text)
                if text.isEmpty {
                    Text("Text to copy")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
            .frame(height: 110)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))

            HStack {
                Text("⌘↩ to save")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: onCancel)
                Button(saveLabel) {
                    onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), text)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .controlSize(.small)
        }
        .padding(12)
        .onAppear { focusedField = .title }
    }
}

// MARK: - Styles

private struct IconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12))
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.15 : (isHovering && isEnabled ? 0.08 : 0)))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { isHovering = $0 }
    }
}

private struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}
