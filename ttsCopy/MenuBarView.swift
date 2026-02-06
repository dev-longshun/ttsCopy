//
//  MenuBarView.swift
//  ttsCopy
//
//  菜单栏弹出视图
//

import SwiftUI

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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(telegramService)
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
            
            Text(message.text)
                .font(.body)
                .lineLimit(2)
            
            HStack {
                Text("Chat ID: \(message.chatId)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if isHovering {
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
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
