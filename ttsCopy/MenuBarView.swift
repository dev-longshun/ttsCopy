//
//  MenuBarView.swift
//  ttsCopy
//
//  菜单栏弹出视图
//

import SwiftUI
import Translation

struct MenuBarView: View {
    @EnvironmentObject var telegramService: TelegramService
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
                
                // 连接状态指示灯
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(telegramService.connectionStatus.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 控制按钮
            HStack(spacing: 12) {
                Button(action: {
                    if telegramService.isPolling {
                        telegramService.stopPolling()
                    } else {
                        telegramService.startPolling()
                    }
                }) {
                    HStack {
                        Image(systemName: telegramService.isPolling ? "stop.fill" : "play.fill")
                        Text(telegramService.isPolling ? "停止监听" : "开始监听")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(telegramService.isPolling ? .red : .green)
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            // 通知开关
            Toggle(isOn: $telegramService.showNotification) {
                Label("收到消息时显示通知", systemImage: "bell.fill")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // 翻译开关（中文→英文）
            Toggle(isOn: $telegramService.enableTranslation) {
                Label("自动翻译为英文", systemImage: "character.book.closed.fill")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 自动保存图片开关
            Toggle(isOn: $telegramService.autoSaveImages) {
                Label("自动保存图片", systemImage: "square.and.arrow.down.fill")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if telegramService.autoSaveImages {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(telegramService.imageSavePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("更改") {
                        chooseImageSavePath()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // 错误信息
            if let error = telegramService.lastError {
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
                    if !telegramService.recentMessages.isEmpty {
                        Button("清空") {
                            telegramService.recentMessages.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                if telegramService.recentMessages.isEmpty {
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
                            ForEach(telegramService.recentMessages) { message in
                                MessageRow(message: message)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                
                Spacer()
                
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(width: 320)
        .translationTask(telegramService.translationConfig) { session in
            telegramService.translationSession = session
        }
        .onChange(of: telegramService.enableTranslation) { newValue in
            if newValue {
                telegramService.prepareTranslation()
            } else {
                telegramService.translationSession = nil
                telegramService.translationConfig = nil
            }
        }
        .onAppear {
            if telegramService.enableTranslation {
                telegramService.prepareTranslation()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(telegramService)
        }
    }
    
    private func chooseImageSavePath() {
        let panel = NSOpenPanel()
        panel.title = "选择图片保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: telegramService.imageSavePath)

        if panel.runModal() == .OK, let url = panel.url {
            telegramService.imageSavePath = url.path
        }
    }

    var statusColor: Color {
        switch telegramService.connectionStatus {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }
}

struct MessageRow: View {
    let message: TelegramService.MessageItem
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.chatTitle ?? "私聊")
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
                Text("Chat ID: \(message.chatId)")
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
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(TelegramService())
}
