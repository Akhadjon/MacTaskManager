import AppKit
import SwiftUI
import Carbon

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let store = MonitorStore()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?
    private let hotkeyManager = HotkeyManager()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure menu-bar app: hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Apply saved appearance
        NSApp.appearance = store.appearance.nsAppearance

        setupStatusItem()
        setupPopover()
        registerHotkey()

        // Begin sampling
        store.startSampling()

    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        store.stopSampling()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "MacTaskManager")
        button.image?.isTemplate = true
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize    = NSSize(width: 320, height: 440)
        pop.behavior       = .transient
        pop.animates       = true
        let appearance     = store.appearance
        pop.contentViewController = NSHostingController(
            rootView: MenuBarDashboardView(openDashboard: { [weak self] in
                self?.openDashboard()
            })
            .environmentObject(store)
            .preferredColorScheme(appearance == .system ? nil :
                                  appearance == .dark   ? .dark : .light)
        )
        self.popover = pop
    }

    // MARK: - Main window / dashboard

    func openDashboard() {
        popover?.performClose(nil)

        if mainWindow == nil || mainWindow?.isVisible == false {
            createMainWindow()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func createMainWindow() {
        let content = ContentView()
            .environmentObject(store)

        let hosting = NSHostingController(rootView: content)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title                        = "MacTaskManager"
        win.contentViewController        = hosting
        win.isReleasedWhenClosed         = false
        win.center()
        win.setFrameAutosaveName("MacTaskManagerMain")
        win.delegate                     = self
        win.minSize                      = NSSize(width: 800, height: 520)
        self.mainWindow = win
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        // Return to accessory mode when the window is closed
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Hotkey (Option + Command + M)

    private func registerHotkey() {
        hotkeyManager.register { [weak self] in
            DispatchQueue.main.async { self?.togglePopover(nil) }
        }
    }
}

// MARK: - HotkeyManager (Carbon)

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    // We need to keep the callback alive
    private var callbackBox: CallbackBox?

    func register(callback: @escaping () -> Void) {
        let box = CallbackBox(callback)
        self.callbackBox = box
        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let ud = userData else { return noErr }
                Unmanaged<CallbackBox>.fromOpaque(ud).takeUnretainedValue().invoke()
                return noErr
            },
            1, &spec, ptr, &eventHandler
        )

        var hkID = EventHotKeyID()
        hkID.signature = fourCharCode("MTMK")
        hkID.id        = 1
        // Option (⌥) + Command (⌘) + M  — kVK_ANSI_M = 0x2E
        let mods = UInt32(cmdKey | optionKey)
        RegisterEventHotKey(0x2E, mods, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef  { UnregisterEventHotKey(ref); hotKeyRef   = nil }
        if let ref = eventHandler { RemoveEventHandler(ref);  eventHandler = nil }
        if let box = callbackBox {
            Unmanaged.passUnretained(box).release()   // balance the passRetained above
            callbackBox = nil
        }
    }

    private func fourCharCode(_ s: String) -> FourCharCode {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}

private final class CallbackBox {
    private let fn: () -> Void
    init(_ fn: @escaping () -> Void) { self.fn = fn }
    func invoke() { fn() }
}
