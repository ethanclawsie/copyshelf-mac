import AppKit
import CopyShelfCore
import SwiftUI

/// Shows the shelf in a floating panel at the mouse cursor.
///
/// The panel is non-activating: it takes keyboard focus for typing, but the app you were
/// using stays frontmost — so after copying, ⌘V pastes straight into it.
@MainActor
final class PopupController {
    private let store: ShelfStore
    private let trigger: MouseTrigger
    private var panel: PopupPanel?

    init(store: ShelfStore, trigger: MouseTrigger) {
        self.store = store
        self.trigger = trigger
    }

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    private func show() {
        let view = ShelfView(store: store, trigger: trigger) { [weak self] in
            self?.close()
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )

        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize

        let panel = PopupPanel()
        panel.contentViewController = host
        panel.onDismiss = { [weak self] in self?.close() }

        // Open with the top-left corner at the cursor, kept fully on screen.
        let mouse = NSEvent.mouseLocation
        let size = host.view.fittingSize
        var frame = NSRect(x: mouse.x, y: mouse.y - size.height, width: size.width, height: size.height)
        if let visible = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.visibleFrame {
            frame = panel.clamped(frame, to: visible)
        }
        panel.setFrame(frame, display: false)
        panel.invalidateShadow()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil // release UI memory between uses
        panel.onDismiss = nil
        panel.orderOut(nil)
        panel.contentViewController = nil
    }
}

private final class PopupPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    /// Clicking anywhere else dismisses the popup.
    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }

    /// Esc dismisses the popup.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Keep the top edge fixed when the content grows/shrinks (e.g. opening the add form),
    /// and never let it run off screen.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if isVisible {
            rect.origin.x = frame.minX
            rect.origin.y = frame.maxY - rect.height
        }
        if let visible = screen?.visibleFrame { rect = clamped(rect, to: visible) }
        super.setFrame(rect, display: flag)
    }

    func clamped(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        var r = rect
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
