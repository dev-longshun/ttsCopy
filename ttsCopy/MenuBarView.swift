//
//  MenuBarView.swift
//  ttsCopy
//
//  菜单栏弹出视图
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var service: ServiceManager
    @EnvironmentObject var updater: UpdaterController
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

            // 新版本提示
            if updater.showsUpdateBadge {
                UpdateBanner()
                Divider()
            }

            // Telegram 状态栏
            HStack(spacing: 6) {
                Circle()
                    .fill(telegramStatusColor)
                    .frame(width: 7, height: 7)
                Text("Telegram")
                    .font(.caption)
                Text(telegramStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
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

            // 控制按钮
            HStack(spacing: 12) {
                Button(action: {
                    if service.telegramActive {
                        service.stopTelegram()
                    } else {
                        service.startTelegram()
                    }
                }) {
                    HStack {
                        Image(systemName: service.telegramActive ? "stop.fill" : "play.fill")
                        Text(service.telegramActive ? "停止监听" : "开始监听")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(service.telegramActive ? .red : .green)
            }
            .padding()

            // 错误信息
            if let error = service.telegramError {
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

            // Telegram 被另一台设备占用
            if service.telegramConflict {
                Button(action: { service.takeOverTelegram() }) {
                    Label("在本机接管", systemImage: "arrow.uturn.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .help("在本机重新开始监听，另一台设备会被挤掉")
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
                Text("v\(UpdaterController.currentVersionString())")
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
                .environmentObject(updater)
        }
    }

    // MARK: - Telegram 状态

    private var telegramStatusColor: Color {
        switch service.telegramStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var telegramStatusText: String {
        if service.telegramConflict { return "被占用" }
        switch service.telegramStatus {
        case .connected: return "监听中"
        case .connecting: return "连接中"
        case .error: return "错误"
        case .disconnected: return "未启动"
        }
    }

    private var clipboardStatusColor: Color {
        switch service.clipboardProcessingState {
        case .idle: return .blue
        case .completed: return .green
        }
    }

    private var clipboardStatusText: String {
        switch service.clipboardProcessingState {
        case .idle: return "剪贴板就绪"
        case .completed: return "已复制到剪贴板"
        }
    }

    private var clipboardStatusIconName: String {
        switch service.clipboardProcessingState {
        case .idle: return "message.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

}

// MARK: - 更新横幅

struct UpdateBanner: View {
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.callout)
                Spacer()
                actionButton
            }
            if updater.phase == .downloading {
                ProgressView(value: updater.downloadProgress)
                    .controlSize(.small)
            }
            if updater.phase == .failed, !updater.statusMessage.isEmpty {
                Text(updater.statusMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private var title: String {
        let version = updater.availableVersion.map { "v\($0)" } ?? ""
        switch updater.phase {
        case .downloading:
            return "正在下载 \(version)… \(Int(updater.downloadProgress * 100))%"
        case .installing:
            return updater.statusMessage
        case .readyToInstall:
            return "新版本已就绪"
        case .failed:
            return "更新失败"
        default:
            return "发现新版本 \(version)"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updater.phase {
        case .available:
            Button("更新并重启") { updater.installAndRelaunch() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .failed:
            Button("重试") { updater.installAndRelaunch() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .readyToInstall:
            Button("退出并安装") { updater.quitToFinishInstall() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .downloading, .installing:
            ProgressView()
                .controlSize(.small)
        default:
            EmptyView()
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
        .environmentObject(UpdaterController())
}
