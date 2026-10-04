import CopyShelfCore
import SwiftUI

@main
struct CopyShelfApp: App {
    @State private var store: ShelfStore
    @State private var trigger: MouseTrigger
    private let popup: PopupController

    init() {
        let store = ShelfStore()
        let trigger = MouseTrigger()
        let popup = PopupController(store: store, trigger: trigger)
        trigger.onTrigger = { popup.toggle() }
        _store = State(initialValue: store)
        _trigger = State(initialValue: trigger)
        self.popup = popup
    }

    var body: some Scene {
        MenuBarExtra("CopyShelf", systemImage: "list.clipboard") {
            ShelfView(store: store, trigger: trigger)
        }
        .menuBarExtraStyle(.window)
    }
}
