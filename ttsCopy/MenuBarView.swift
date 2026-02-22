//
//  MenuBarView.swift
//  ttsCopy
//
//  菜单栏弹出视图
//

import SwiftUI
import Translation

struct MenuBarView: View {
    @EnvironmentObject var service: ServiceManager
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "message.circle.fill")
                    .foregroundColor(.blue)
                Text("TTS Copy")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(service.connectionStatus.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 模式切换
            Picker("", selection: $service.activeMode) {
                ForEach(ServiceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 控制按钮
            HStack(spacing: 12) {
                Button(action: {
                    if service.isActive {
                        service.stop()
                    } else {
                        service.start()
                    }
                }) {
                    HStack {
                        Image(systemName: service.isActive ? "stop.fill" : "play.fill")
                        Text(buttonLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(service.isActive ? .red : .green)

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.bordered)
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

            // 通知开关
            Toggle(isOn: $service.showNotification) {
                Label("收到消息时显示通知", systemImage: "bell.fill")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 翻译开关
            Toggle(isOn: $service.enableTranslation) {
                Label("自动翻译为英文", systemImage: "character.book.closed.fill")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 自动保存图片开关
            Toggle(isOn: $service.autoSaveImages) {
                Label("自动保存图片", systemImage: "square.and.arrow.down.fill")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if service.autoSaveImages {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(service.imageSavePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("更改") { chooseImageSavePath() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

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
        .translationTask(service.translationConfig) { session in
            service.translationSession = session
        }
        .onChange(of: service.enableTranslation) {
            if service.enableTranslation {
                service.prepareTranslation()
            } else {
                service.translationSession = nil
                service.translationConfig = nil
            }
        }
        .onAppear {
            if service.enableTranslation {
                service.prepareTranslation()
            }
        }
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

    private func chooseImageSavePath() {
        let panel = NSOpenPanel()
        panel.title = "选择图片保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: service.imageSavePath)
        if panel.runModal() == .OK, let url = panel.url {
            service.imageSavePath = url.path
        }
    }

    var statusColor: Color {
        switch service.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
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
