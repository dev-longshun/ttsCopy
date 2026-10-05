//
//  SettingsView.swift
//  ttsCopy
//
//  设置界面
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var service: ServiceManager
    @EnvironmentObject var updater: UpdaterController
    @Environment(\.dismiss) var dismiss

    @State private var botToken: String = ""
    @State private var newChatId: String = ""
    // 读取系统里的真实状态，避免已开启时开关仍显示为关
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var testResult: String = ""
    @State private var testSuccess: Bool? = nil
    @State private var isTesting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
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
                    // Telegram 设置
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Bot Token", systemImage: "key.fill")
                                .font(.headline)
                            TextField("输入你的 Bot Token", text: $botToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Text("从 @BotFather 获取的 Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Button(action: testConnection) {
                                    HStack {
                                        if isTesting {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "network")
                                        }
                                        Text(isTesting ? "测试中..." : "测试连接")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(botToken.isEmpty || isTesting)
                                Spacer()
                                if let success = testSuccess {
                                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(success ? .green : .red)
                                }
                            }
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
                            Toggle("接收所有消息（不过滤）", isOn: $service.copyAllMessages)
                                .toggleStyle(.switch)
                            if !service.copyAllMessages {
                                Divider()
                                HStack {
                                    TextField("输入 Chat ID", text: $newChatId)
                                        .textFieldStyle(.roundedBorder)
                                    Button("添加") {
                                        if let chatId = Int64(newChatId.trimmingCharacters(in: .whitespaces)) {
                                            service.addChatId(chatId)
                                            newChatId = ""
                                        }
                                    }
                                    .disabled(Int64(newChatId.trimmingCharacters(in: .whitespaces)) == nil)
                                }
                                if service.allowedChatIds.isEmpty {
                                    Text("暂未添加任何 Chat ID")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 8)
                                } else {
                                    VStack(spacing: 4) {
                                        ForEach(Array(service.allowedChatIds).sorted(), id: \.self) { chatId in
                                            HStack {
                                                Text("\(chatId)")
                                                    .font(.system(.body, design: .monospaced))
                                                Spacer()
                                                Button(action: { service.removeChatId(chatId) }) {
                                                    Image(systemName: "trash").foregroundColor(.red)
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
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // 消息处理
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("消息处理", systemImage: "text.bubble")
                                .font(.headline)
                            Toggle(isOn: $service.showNotification) {
                                Label("收到消息时显示通知", systemImage: "bell.fill")
                            }
                            .toggleStyle(.switch)
                            Toggle(isOn: $service.autoSaveImages) {
                                Label("自动保存图片", systemImage: "square.and.arrow.down.fill")
                            }
                            .toggleStyle(.switch)
                            if service.autoSaveImages {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.secondary)
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
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // 软件更新
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("软件更新", systemImage: "arrow.down.circle")
                                .font(.headline)
                            HStack {
                                Text("当前版本")
                                Spacer()
                                Text("v\(UpdaterController.currentVersionString())")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Toggle("自动检查更新", isOn: $updater.automaticallyChecksForUpdates)
                                .toggleStyle(.switch)
                            HStack(spacing: 8) {
                                Button("检查更新") { updater.checkForUpdates() }
                                    .buttonStyle(.bordered)
                                    .disabled(!updater.canCheckForUpdates)
                                if updater.phase == .available || (updater.phase == .failed && updater.availableVersion != nil) {
                                    Button("更新并重启") { updater.installAndRelaunch() }
                                        .buttonStyle(.borderedProminent)
                                }
                                if updater.phase == .checking || updater.phase == .downloading || updater.phase == .installing {
                                    ProgressView().scaleEffect(0.7)
                                }
                                Spacer()
                            }
                            if !updater.statusMessage.isEmpty {
                                Text(updater.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(updater.phase == .failed ? .red : .secondary)
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
                                .onChange(of: launchAtLogin) {
                                    setLaunchAtLogin(enabled: launchAtLogin)
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

            HStack {
                Spacer()
                Button("保存") {
                    service.botToken = botToken
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 470, height: 820)
        .onAppear {
            botToken = service.botToken
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

    private func testConnection() {
        isTesting = true
        testResult = ""
        testSuccess = nil
        service.botToken = botToken
        Task {
            let result = await service.testConnection()
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
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ServiceManager())
        .environmentObject(UpdaterController())
}
