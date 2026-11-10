import Cocoa
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as regular Dock application
        NSApp.setActivationPolicy(.regular)

        setupMainMenu()
        setupMainWindow()

        NSApp.activate(ignoringOtherApps: true)
        NSLog("%@ started successfully as a Dock application.", AppConfig.appName)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private var lastQuitAttempt: Date? = nil
    private var quitResetWorkItem: DispatchWorkItem? = nil

    /// Implements double ⌘Q to quit: first press displays a gentle prompt,
    /// a second press within 2 seconds cleanly exits the application.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let now = Date()
        if let last = lastQuitAttempt, now.timeIntervalSince(last) < 2.0 {
            lastQuitAttempt = nil
            quitResetWorkItem?.cancel()
            return .terminateNow
        }

        lastQuitAttempt = now
        quitResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.lastQuitAttempt = nil
        }
        quitResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)

        NotificationCenter.default.post(name: .confirmQuitRequested, object: nil)
        return .terminateCancel
    }

    private func setupMainWindow() {
        let rootView = MainAppView()
        let hostingController = NSHostingController(rootView: rootView)

        let initialSize = NSSize(width: 960, height: 680)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        win.minSize = NSSize(width: 400, height: 500)
        win.title = AppConfig.appName
        win.center()
        win.contentViewController = hostingController
        win.makeKeyAndOrderFront(nil)

        self.window = win
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(AppConfig.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: nil, keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(AppConfig.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(AppConfig.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit Menu (Crucial for Cut/Copy/Paste/Select All in TextFields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

extension Notification.Name {
    public static let confirmQuitRequested = Notification.Name("gistYT.confirmQuitRequested")
}
