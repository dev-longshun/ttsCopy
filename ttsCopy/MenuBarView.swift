//
//  MenuBarView.swift
//  ttsCopy
//
//  菜单栏弹出视图
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var service: ServiceManager
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: clipboardStatusIconName)
                    .foregroundColor(clipboardStatusColor)
                Text("TTS Copy")
                    .font(.headline)
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 双服务状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(telegramStatusColor)
                        .frame(width: 7, height: 7)
                    Text("Telegram")
                        .font(.caption)
                    Text(telegramStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(lanStatusColor)
                        .frame(width: 7, height: 7)
                    Text("LAN")
                        .font(.caption)
                    Text(lanStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(clipboardStatusColor)
                    .frame(width: 8, height: 8)
                Text(clipboardStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // 模式切换
            Picker("", selection: $service.activeMode) {
                ForEach(ServiceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 控制按钮
            HStack(spacing: 12) {
                Button(action: {
                    if service.isActive {
                        service.stopCurrentMode()
                    } else {
                        service.startCurrentMode()
                    }
                }) {
                    HStack {
                        Image(systemName: service.isActive ? "stop.fill" : "play.fill")
                        Text(buttonLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(service.isActive ? .red : .green)
            }
            .padding()

            // LAN 状态信息
            if service.activeMode == .lan && service.isActive {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("IP 地址")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(service.localIPAddress)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("端口号")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(service.lanPort))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("已连接设备")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(service.lanConnectedDevices.count)")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // 错误信息
            if let error = service.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // 最近消息列表
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近消息")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !service.recentMessages.isEmpty {
                        Button("清空") { service.recentMessages.removeAll() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if service.recentMessages.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无消息")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(service.recentMessages) { message in
                                MessageRow(message: message)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            Divider()

            // 底部
            HStack {
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                Spacer()
                Text("v1.1")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(width: 320)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(service)
        }
    }

    private var buttonLabel: String {
        if service.isActive {
            return service.activeMode == .telegram ? "停止监听" : "停止服务"
        } else {
            return service.activeMode == .telegram ? "开始监听" : "启动服务"
        }
    }

    // MARK: - 双服务状态

    private var telegramStatusColor: Color {
        switch service.telegramStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var telegramStatusText: String {
        switch service.telegramStatus {
        case .connected: return "监听中"
        case .connecting: return "连接中"
        case .error: return "错误"
        case .disconnected: return "未启动"
        }
    }

    private var lanStatusColor: Color {
        switch service.lanStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var lanStatusText: String {
        switch service.lanStatus {
        case .connected: return "运行中"
        case .connecting: return "启动中"
        case .error: return "错误"
        case .disconnected: return "未启动"
        }
    }

    private var clipboardStatusColor: Color {
        switch service.clipboardProcessingState {
        case .idle: return .blue
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var clipboardStatusText: String {
        switch service.clipboardProcessingState {
        case .idle: return "剪贴板就绪"
        case .processing: return "原文已复制，正在优化..."
        case .completed: return "优化完成，已覆盖剪贴板"
        case .failed: return "处理失败，已保留原文"
        }
    }

    private var clipboardStatusIconName: String {
        switch service.clipboardProcessingState {
        case .idle: return "message.circle.fill"
        case .processing: return "arrow.triangle.2.circlepath.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

}

struct MessageRow: View {
    let message: MessageItem
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.sourceDetail ?? message.source)
                    .font(.caption)
                    .foregroundColor(.blue)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            switch message.content {
            case .text(let str):
                Text(str)
                    .font(.body)
                    .lineLimit(2)
            case .photo(let data, let caption):
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 80)
                        .cornerRadius(6)
                }
                if let caption = caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            HStack {
                Text(message.source)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if isHovering {
                    Button("复制") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        switch message.content {
                        case .text(let str):
                            pasteboard.setString(str, forType: .string)
                        case .photo(let data, let caption):
                            if let image = NSImage(data: data) {
                                pasteboard.writeObjects([image])
                                if let caption = caption, !caption.isEmpty {
                                    pasteboard.setString(caption, forType: .string)
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { hovering in isHovering = hovering }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ServiceManager())
}
