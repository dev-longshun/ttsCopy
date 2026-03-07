//
//  ttsCopyApp.swift
//  ttsCopy
//
//  TTS Copy - 自动复制消息到剪贴板（支持 Telegram / 局域网模式）
//

import SwiftUI
import Combine

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

// MARK: - 可成为 Key Window 的面板（修复控件颜色渲染）

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var panel: NSPanel?
    var eventMonitor: Any?
    let serviceManager = ServiceManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        bindStatusItemAppearance()

        // Auto-start：根据上次的面板模式启动对应服务
        // 两个服务独立运行，这里只自动启动用户上次使用的模式
        switch serviceManager.activeMode {
        case .telegram:
            if !serviceManager.botToken.isEmpty {
                serviceManager.startCurrentMode()
            }
        case .lan:
            serviceManager.startCurrentMode()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.imagePosition = .imageOnly
        }
        updateStatusItemAppearance(for: .idle)

        let hostingView = NSHostingView(
            rootView: MenuBarView()
                .environmentObject(serviceManager)
        )
        hostingView.setFrameSize(NSSize(width: 320, height: 480))

        let panel = KeyablePanel(
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

    private func bindStatusItemAppearance() {
        serviceManager.$clipboardProcessingState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusItemAppearance(for: state)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemAppearance(for state: ClipboardProcessingState) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let tintColor: NSColor
        switch state {
        case .idle:
            symbolName = "message.circle"
            tintColor = .systemBlue
        case .processing:
            symbolName = "arrow.triangle.2.circlepath.circle.fill"
            tintColor = .systemOrange
        case .completed:
            symbolName = "checkmark.circle.fill"
            tintColor = .systemGreen
        case .failed:
            symbolName = "exclamationmark.circle.fill"
            tintColor = .systemRed
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TTS Copy")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tintColor
    }

    func applicationWillTerminate(_ notification: Notification) {
        serviceManager.stopTelegram()
        serviceManager.stopLAN()
    }
}
