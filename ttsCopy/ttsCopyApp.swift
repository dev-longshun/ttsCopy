//
//  ttsCopyApp.swift
//  ttsCopy
//
//  TTS Copy - 自动复制 Telegram 消息到剪贴板
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
                .environmentObject(appDelegate.updater)
        }
    }
}

// MARK: - 可成为 Key Window 的面板（修复控件颜色渲染）

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var panel: NSPanel?
    var eventMonitor: Any?
    let serviceManager = ServiceManager()
    lazy var updater = UpdaterController()
    private var cancellables = Set<AnyCancellable>()
    /// 菜单栏图标右上角的更新红点
    private var updateBadgeView: NSView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        bindStatusItemAppearance()
        bindUpdateBadge()
        updater.startDeferred()

        // Auto-start：已配置 Bot Token 时自动开始监听
        if !serviceManager.botToken.isEmpty {
            serviceManager.startTelegram()
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
                .environmentObject(updater)
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
            updater.panelDidOpen()

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

        let image: NSImage?
        switch state {
        case .idle:
            // 模板图：系统按菜单栏深浅自动画成白色或黑色
            image = NSImage(systemSymbolName: "message.circle", accessibilityDescription: "TTS Copy")
            image?.isTemplate = true
        case .completed:
            // 彩色图：不走模板着色，深浅菜单栏都显示绿色
            image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "TTS Copy")?
                .withSymbolConfiguration(.init(paletteColors: [.systemGreen]))
            image?.isTemplate = false
        }

        button.image = image
        // 模板图叠加着色在深色菜单栏上会被画成近乎黑色，统一不设 tint
        button.contentTintColor = nil
    }

    // MARK: - 更新红点

    private func bindUpdateBadge() {
        updater.$phase
            .combineLatest(updater.$availableVersion)
            .map { UpdaterController.badgeVisible(phase: $0, availableVersion: $1) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.setUpdateBadgeVisible(visible)
            }
            .store(in: &cancellables)
    }

    private func setUpdateBadgeVisible(_ visible: Bool) {
        guard let button = statusItem?.button else { return }
        if !visible {
            updateBadgeView?.removeFromSuperview()
            updateBadgeView = nil
            return
        }
        guard updateBadgeView == nil else { return }

        let size: CGFloat = 6
        let dot = NSView(frame: NSRect(
            x: button.bounds.maxX - size - 2,
            y: button.isFlipped ? 3 : button.bounds.maxY - size - 3,
            width: size,
            height: size
        ))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = size / 2
        dot.autoresizingMask = button.isFlipped ? [.minXMargin, .maxYMargin] : [.minXMargin, .minYMargin]
        button.addSubview(dot)
        updateBadgeView = dot
    }

    func applicationWillTerminate(_ notification: Notification) {
        serviceManager.stopTelegram()
    }
}
