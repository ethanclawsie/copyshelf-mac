import CopyShelfCore
import SwiftUI

@main
struct CopyShelfApp: App {
    @State private var store = ShelfStore()

    var body: some Scene {
        MenuBarExtra("CopyShelf", systemImage: "list.clipboard") {
            ShelfView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
