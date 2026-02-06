//
//  SettingsView.swift
//  ttsCopy
//
//  设置界面
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var telegramService: TelegramService
    @Environment(\.dismiss) var dismiss
    
    @State private var botToken: String = ""
    @State private var newChatId: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var testResult: String = ""
    @State private var testSuccess: Bool? = nil
    @State private var isTesting: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("设置")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Bot Token 设置
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Bot Token", systemImage: "key.fill")
                                .font(.headline)
                            
                            // 改用普通 TextField 方便调试
                            TextField("输入你的 Bot Token", text: $botToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            Text("从 @BotFather 获取的 Token，格式如: 123456789:ABCdefGHI...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Token 长度显示
                            Text("Token 长度: \(botToken.count) 字符")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // 测试连接按钮
                            HStack {
                                Button(action: testConnection) {
                                    HStack {
                                        if isTesting {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "network")
                                        }
                                        Text(isTesting ? "测试中..." : "测试连接")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(botToken.isEmpty || isTesting)
                                
                                Spacer()
                                
                                // 测试结果
                                if let success = testSuccess {
                                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(success ? .green : .red)
                                }
                            }
                            
                            // 测试结果详情
                            if !testResult.isEmpty {
                                Text(testResult)
                                    .font(.caption)
                                    .foregroundColor(testSuccess == true ? .green : .red)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Chat ID 设置
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("允许的群组/聊天", systemImage: "person.2.fill")
                                .font(.headline)
                            
                            Toggle("接收所有消息（不过滤）", isOn: $telegramService.copyAllMessages)
                                .toggleStyle(.switch)
                            
                            if !telegramService.copyAllMessages {
                                Divider()
                                
                                HStack {
                                    TextField("输入 Chat ID", text: $newChatId)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Button("添加") {
                                        if let chatId = Int64(newChatId.trimmingCharacters(in: .whitespaces)) {
                                            telegramService.addChatId(chatId)
                                            newChatId = ""
                                        }
                                    }
                                    .disabled(Int64(newChatId.trimmingCharacters(in: .whitespaces)) == nil)
                                }
                                
                                if telegramService.allowedChatIds.isEmpty {
                                    Text("暂未添加任何 Chat ID")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 8)
                                } else {
                                    VStack(spacing: 4) {
                                        ForEach(Array(telegramService.allowedChatIds).sorted(), id: \.self) { chatId in
                                            HStack {
                                                Text("\(chatId)")
                                                    .font(.system(.body, design: .monospaced))
                                                Spacer()
                                                Button(action: {
                                                    telegramService.removeChatId(chatId)
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(4)
                                        }
                                    }
                                }
                                
                                Text("提示：发送消息到群组后，在「最近消息」中可以看到 Chat ID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 其他设置
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("其他", systemImage: "gear")
                                .font(.headline)
                            
                            Toggle("开机自动启动", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .onChange(of: launchAtLogin) { newValue in
                                    setLaunchAtLogin(enabled: newValue)
                                }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 使用说明
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("使用说明", systemImage: "questionmark.circle")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                BulletPoint("配置 Bot Token 后点击「开始监听」")
                                BulletPoint("在手机上给 Bot 或群组发送消息")
                                BulletPoint("消息会自动复制到 Mac 剪贴板")
                                BulletPoint("在「最近消息」中可以找到 Chat ID")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // 保存按钮
            HStack {
                Spacer()
                Button("保存") {
                    telegramService.botToken = botToken
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 550)
        .onAppear {
            botToken = telegramService.botToken
        }
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("设置开机启动失败: \(error)")
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = ""
        testSuccess = nil
        
        // 先保存 token
        telegramService.botToken = botToken
        
        Task {
            let result = await telegramService.testConnection()
            await MainActor.run {
                isTesting = false
                testSuccess = result.success
                testResult = result.message
            }
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(TelegramService())
}
