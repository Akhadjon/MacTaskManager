import SwiftUI
import AppKit

@main
struct MacTaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a hidden Settings scene so SwiftUI doesn't try to manage windows.
        // All window and menu-bar management is handled by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
