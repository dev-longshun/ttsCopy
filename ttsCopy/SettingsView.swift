//
//  SettingsView.swift
//  ttsCopy
//
//  设置界面
//

import SwiftUI
import ServiceManagement
import Translation

struct SettingsView: View {
    @EnvironmentObject var service: ServiceManager
    @Environment(\.dismiss) var dismiss

    @State private var botToken: String = ""
    @State private var newChatId: String = ""
    @State private var launchAtLogin: Bool = false
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
                    // 模式选择
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("连接模式", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                            Picker("", selection: $service.activeMode) {
                                ForEach(ServiceMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 8)
                    }

                    // Telegram 设置
                    if service.activeMode == .telegram {
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
                    }

                    // LAN 设置
                    if service.activeMode == .lan {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("局域网模式", systemImage: "wifi")
                                    .font(.headline)
                                Text("Mac 会启动 WebSocket 服务器，手机端 App 通过 Bonjour 自动发现并连接。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if service.isActive {
                                    HStack {
                                        Text("服务器地址:")
                                        Text("\(service.localIPAddress):\(service.lanPort)")
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                    HStack {
                                        Text("已连接设备:")
                                        Text("\(service.lanConnectedDevices.count)")
                                    }
                                } else {
                                    Text("点击「启动服务」开始")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // 语音识别
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("语音识别 (ASR)", systemImage: "waveform")
                                    .font(.headline)

                                if service.asrReady {
                                    // 已就绪
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("SenseVoice 模型已就绪")
                                    }
                                    Text("手机端录音将通过 Mac 进行高精度离线识别")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if service.asrDownloading {
                                    // 下载中
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("正在下载 SenseVoice 模型...")
                                            Spacer()
                                            Text("\(Int(service.asrDownloadProgress * 100))%")
                                                .font(.system(.body, design: .monospaced))
                                        }
                                        ProgressView(value: service.asrDownloadProgress)
                                        if !service.asrDownloadDesc.isEmpty {
                                            Text(service.asrDownloadDesc)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Button("取消下载") {
                                            service.cancelASRDownload()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                } else if service.asrModelDownloaded {
                                    // 已下载但未加载（可能加载失败）
                                    if let error = service.asrError {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text(error)
                                        }
                                    } else {
                                        HStack(spacing: 6) {
                                            ProgressView().scaleEffect(0.7)
                                            Text("模型加载中...")
                                        }
                                    }
                                } else {
                                    // 未下载
                                    Text("需要下载 SenseVoice 语音识别模型才能使用 Mac 端高精度识别。")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let error = service.asrError {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    Button(action: { service.downloadASRModel() }) {
                                        HStack {
                                            Image(systemName: "arrow.down.circle")
                                            Text("下载模型 (~239 MB)")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                        }
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
                            Toggle(isOn: $service.enableTranslation) {
                                Label("自动翻译为英文", systemImage: "character.book.closed.fill")
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
                                if service.activeMode == .telegram {
                                    BulletPoint("配置 Bot Token 后点击「开始监听」")
                                    BulletPoint("在手机上给 Bot 或群组发送消息")
                                } else {
                                    BulletPoint("点击「启动服务」开启局域网服务器")
                                    BulletPoint("手机端 App 会自动发现并连接")
                                }
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
                    if service.activeMode == .telegram {
                        service.botToken = botToken
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 620)
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
            botToken = service.botToken
            if service.enableTranslation {
                service.prepareTranslation()
            }
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
}
