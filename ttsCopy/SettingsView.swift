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
    @State private var promptOptimizationTestInput: String = "帮我写一个更好的提示词，用于让 AI 帮我重构一段 SwiftUI 代码。"

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

                                // 模型选择
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("识别模型")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Picker("", selection: Binding(
                                        get: { service.selectedASRModel },
                                        set: { service.switchASRModel(to: $0) }
                                    )) {
                                        ForEach(ASRModel.allCases) { model in
                                            Text(model.shortName).tag(model)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .disabled(service.asrDownloading)

                                    Text(service.selectedASRModel.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Divider()

                                // 当前选中模型的状态
                                let model = service.selectedASRModel
                                let downloaded = service.isASRModelDownloaded(model)

                                if service.asrReady {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("\(model.shortName) 已就绪")
                                    }
                                    if let info = service.asrModelInfo {
                                        Text(info.summary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else if service.asrDownloading {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("正在下载 \(model.shortName)...")
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
                                } else if downloaded {
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
                                    Text("需要下载 \(model.shortName) 语音识别模型。")
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
                                            Text("下载 \(model.shortName) (~\(model.sizeMB) MB)")
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
                            Toggle(isOn: $service.enablePromptOptimization) {
                                Label("提示词优化（OpenAI）", systemImage: "sparkles")
                            }
                            .toggleStyle(.switch)
                            if service.enablePromptOptimization {
                                VStack(alignment: .leading, spacing: 10) {
                                    SecureField("OpenAI API Key", text: $service.openAIAPIKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                    TextField("https://api.openai.com/v1", text: $service.openAIBaseURL)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                    TextField("gpt-4.1-mini", text: $service.openAIModel)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                    HStack(spacing: 8) {
                                        Button(action: refreshOpenAIModels) {
                                            HStack(spacing: 6) {
                                                if service.isFetchingOpenAIModels {
                                                    ProgressView().scaleEffect(0.7)
                                                } else {
                                                    Image(systemName: "list.bullet.rectangle")
                                                }
                                                Text(service.isFetchingOpenAIModels ? "检测中..." : "检测可用模型")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(
                                            service.isFetchingOpenAIModels ||
                                            service.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                            service.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        )

                                        if !service.availableOpenAIModels.isEmpty {
                                            Text("已发现 \(service.availableOpenAIModels.count) 个模型")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    if let error = service.openAIModelFetchError, !error.isEmpty {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    if !service.availableOpenAIModels.isEmpty {
                                        Picker("可用模型", selection: $service.openAIModel) {
                                            ForEach(service.availableOpenAIModels, id: \.self) { model in
                                                Text(model).tag(model)
                                            }
                                        }
                                        .pickerStyle(.menu)

                                        if !service.availableOpenAIModels.contains(service.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                            Text("当前模型不在服务返回的可用列表里，优化请求会失败。")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    Text("处理顺序：先做提示词优化，再按需翻译，最后写入剪贴板。")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Base URL 填到根地址也可以，应用会自动走 /v1/models 和 /v1/chat/completions。")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("提示词模板文件：ttsCopy/PromptOptimizerSystemPrompt.md")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                    if service.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("未填写 API Key 时，收到消息会直接跳过提示词优化。")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }

                                    Divider()

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("测试优化")
                                            .font(.subheadline)
                                            .bold()
                                        TextEditor(text: $promptOptimizationTestInput)
                                            .font(.system(.body, design: .default))
                                            .frame(minHeight: 100)
                                            .padding(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                                            )
                                        HStack(spacing: 8) {
                                            Button(action: runPromptOptimizationTest) {
                                                HStack(spacing: 6) {
                                                    if service.isTestingPromptOptimization {
                                                        ProgressView().scaleEffect(0.7)
                                                    } else {
                                                        Image(systemName: "wand.and.stars")
                                                    }
                                                    Text(service.isTestingPromptOptimization ? "优化中..." : "测试优化")
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(service.isTestingPromptOptimization)

                                            Button("复制结果") {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(service.promptOptimizationTestOutput, forType: .string)
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(service.promptOptimizationTestOutput.isEmpty)
                                        }

                                        if let error = service.promptOptimizationTestError, !error.isEmpty {
                                            Text(error)
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }

                                        if !service.promptOptimizationTestOutput.isEmpty {
                                            ScrollView {
                                                Text(service.promptOptimizationTestOutput)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .textSelection(.enabled)
                                                    .padding(10)
                                            }
                                            .frame(minHeight: 120, maxHeight: 220)
                                            .background(Color.gray.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                                .padding(.leading, 28)
                            }
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
        .frame(width: 470, height: 820)
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
            if service.enablePromptOptimization,
               !service.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !service.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               service.availableOpenAIModels.isEmpty {
                Task {
                    await service.refreshOpenAIModels()
                }
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

    private func refreshOpenAIModels() {
        Task {
            await service.refreshOpenAIModels()
        }
    }

    private func runPromptOptimizationTest() {
        Task {
            await service.runPromptOptimizationTest(input: promptOptimizationTestInput)
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
