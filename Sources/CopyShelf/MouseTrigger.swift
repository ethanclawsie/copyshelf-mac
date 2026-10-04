import AppKit
import ApplicationServices
import Observation

/// Global mouse-button binding via a CGEventTap.
///
/// - The tap only exists while a button is bound or being recorded, and only receives
///   "other" mouse buttons (not left/right clicks or mouse movement), so idle cost is nil.
/// - The bound button is consumed (its normal action is blocked), which requires
///   Accessibility permission.
@MainActor
@Observable
final class MouseTrigger {
    /// CGEvent button number (2 = middle, 3/4 = side buttons, ...). nil = not bound.
    private(set) var button: Int?
    private(set) var isRecording = false
    /// Whether the event tap is installed (observed so the UI reflects permission state).
    private(set) var isListening = false

    @ObservationIgnored var onTrigger: () -> Void = {}
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?

    private static let defaultsKey = "popupMouseButton"

    init() {
        button = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Int
        updateTap()
    }

    /// True when a button is bound but the tap couldn't be installed (no permission).
    var needsPermission: Bool { button != nil && !isListening }

    static func name(of button: Int) -> String {
        button == 2 ? "Middle Button" : "Button \(button + 1)"
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Starts listening for the next mouse button press. Returns false if Accessibility
    /// permission is missing (the system prompt is shown in that case).
    @discardableResult
    func startRecording() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: kCFBooleanTrue] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        isRecording = true
        updateTap()
        return tap != nil
    }

    func cancelRecording() {
        isRecording = false
        updateTap()
    }

    func clear() {
        button = nil
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        updateTap()
    }

    /// Retries installing the tap (e.g. after the user grants permission).
    func refresh() {
        if tap == nil { updateTap() }
    }

    // MARK: Event tap

    /// Returns true to swallow the event.
    fileprivate func handle(_ type: CGEventType, buttonNumber: Int) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if isRecording, type == .otherMouseDown {
            isRecording = false
            button = buttonNumber
            UserDefaults.standard.set(buttonNumber, forKey: Self.defaultsKey)
            return true // its mouse-up is swallowed below since it now matches `button`
        }
        guard buttonNumber == button else { return false }
        if type == .otherMouseDown {
            // Don't build UI inside the tap callback (keeps it far below the tap timeout).
            DispatchQueue.main.async { [onTrigger] in onTrigger() }
        }
        return true
    }

    private func updateTap() {
        let wanted = button != nil || isRecording
        if wanted, tap == nil, AXIsProcessTrusted() {
            installTap()
        } else if !wanted, let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            self.tap = nil
            self.source = nil
            isListening = false
        }
    }

    private func installTap() {
        let mask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        activeTrigger = self
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: mouseTapCallback,
            userInfo: nil
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isListening = true
    }
}

private nonisolated(unsafe) weak var activeTrigger: MouseTrigger?

/// C callback; runs on the main run loop because that's where the source is added.
private func mouseTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    let swallow = MainActor.assumeIsolated {
        activeTrigger?.handle(type, buttonNumber: buttonNumber) ?? false
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

