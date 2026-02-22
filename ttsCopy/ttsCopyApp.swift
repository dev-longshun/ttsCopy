//
//  ttsCopyApp.swift
//  ttsCopy
//
//  TTS Copy - 自动复制消息到剪贴板（支持 Telegram / 局域网模式）
//

import SwiftUI

@main
struct ttsCopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.serviceManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var panel: NSPanel?
    var eventMonitor: Any?
    let serviceManager = ServiceManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()

        // Auto-start
        switch serviceManager.activeMode {
        case .telegram:
            if !serviceManager.botToken.isEmpty {
                serviceManager.start()
            }
        case .lan:
            serviceManager.start()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "message.circle", accessibilityDescription: "TTS Copy")
            button.action = #selector(togglePanel)
            button.target = self
        }

        let hostingView = NSHostingView(
            rootView: MenuBarView()
                .environmentObject(serviceManager)
        )
        hostingView.setFrameSize(NSSize(width: 320, height: 480))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.animationBehavior = .utilityWindow

        self.panel = panel
    }

    @objc func togglePanel() {
        guard let panel = panel, let button = statusItem?.button else { return }

        if panel.isVisible {
            closePanel()
        } else {
            let buttonRect = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
            let panelWidth = panel.frame.width
            let panelHeight = panel.frame.height

            let x = buttonRect.midX - panelWidth / 2
            let y = buttonRect.minY - panelHeight

            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePanel()
            }
        }
    }

    func closePanel() {
        panel?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        serviceManager.stop()
    }
}
