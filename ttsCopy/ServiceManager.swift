//
//  ServiceManager.swift
//  ttsCopy
//
//  统一服务管理，作为 UI 的 @EnvironmentObject
//  支持 Telegram 和 LAN 双服务独立并行运行
//

import Foundation
import SwiftUI
import Translation

class ServiceManager: ObservableObject {

    // MARK: - 当前查看的面板（不影响服务运行状态）

    @Published var activeMode: ServiceMode {
        didSet {
            UserDefaults.standard.set(activeMode.rawValue, forKey: "serviceMode")
        }
    }

    // MARK: - 双服务独立状态

    @Published var telegramActive = false
    @Published var telegramStatus: ConnectionStatus = .disconnected
    @Published var telegramError: String?

    @Published var lanActive = false
    @Published var lanStatus: ConnectionStatus = .disconnected
    @Published var lanError: String?

    // 兼容 UI：根据当前面板返回对应服务的状态
    var isActive: Bool {
        switch activeMode {
        case .telegram: return telegramActive
        case .lan: return lanActive
        }
    }

    var connectionStatus: ConnectionStatus {
        switch activeMode {
        case .telegram: return telegramStatus
        case .lan: return lanStatus
        }
    }

    var lastError: String? {
        switch activeMode {
        case .telegram: return telegramError
        case .lan: return lanError
        }
    }

    @Published var recentMessages: [MessageItem] = []
    @Published var clipboardProcessingState: ClipboardProcessingState = .idle

    // MARK: - Shared Settings

    @Published var showNotification: Bool {
        didSet {
            UserDefaults.standard.set(showNotification, forKey: "showNotification")
            processor.showNotification = showNotification
        }
    }
    @Published var enableTranslation: Bool {
        didSet { UserDefaults.standard.set(enableTranslation, forKey: "enableTranslation") }
    }
    @Published var enablePromptOptimization: Bool {
        didSet {
            UserDefaults.standard.set(enablePromptOptimization, forKey: "enablePromptOptimization")
            processor.enablePromptOptimization = enablePromptOptimization
        }
    }
    @Published var autoSaveImages: Bool {
        didSet {
            UserDefaults.standard.set(autoSaveImages, forKey: "autoSaveImages")
            processor.autoSaveImages = autoSaveImages
        }
    }
    @Published var imageSavePath: String {
        didSet {
            UserDefaults.standard.set(imageSavePath, forKey: "imageSavePath")
            processor.imageSavePath = imageSavePath
        }
    }
    @Published var openAIAPIKey: String {
        didSet {
            UserDefaults.standard.set(openAIAPIKey, forKey: "openAIAPIKey")
            processor.openAIAPIKey = openAIAPIKey
        }
    }
    @Published var openAIBaseURL: String {
        didSet {
            UserDefaults.standard.set(openAIBaseURL, forKey: "openAIBaseURL")
            processor.openAIBaseURL = openAIBaseURL
        }
    }
    @Published var openAIModel: String {
        didSet {
            UserDefaults.standard.set(openAIModel, forKey: "openAIModel")
            processor.openAIModel = openAIModel
        }
    }
    @Published var availableOpenAIModels: [String] = []
    @Published var isFetchingOpenAIModels = false
    @Published var openAIModelFetchError: String?
    @Published var isTestingPromptOptimization = false
    @Published var promptOptimizationTestOutput: String = ""
    @Published var promptOptimizationTestError: String?

    // MARK: - Telegram Settings

    @Published var botToken: String {
        didSet { UserDefaults.standard.set(botToken, forKey: "botToken") }
    }
    @Published var allowedChatIds: Set<Int64> {
        didSet { UserDefaults.standard.set(Array(allowedChatIds), forKey: "allowedChatIds") }
    }
    @Published var copyAllMessages: Bool {
        didSet { UserDefaults.standard.set(copyAllMessages, forKey: "copyAllMessages") }
    }

    // MARK: - LAN Settings

    @Published var lanPort: UInt16 = 0
    @Published var lanConnectedDevices: [String] = []
    @Published var localIPAddress: String = ""

    // MARK: - Translation

    var translationSession: TranslationSession? {
        get { processor.translationSession }
        set { processor.translationSession = newValue }
    }
    @Published var translationConfig: TranslationSession.Configuration?

    // MARK: - Internal

    let processor = MessageProcessor()
    private var telegramService: TelegramService?
    private var lanService: LANService?
    private let whisperASRService = WhisperASRService()
    private var clipboardStateResetTask: Task<Void, Never>?

    // MARK: - ASR State

    @Published var selectedASRModel: ASRModel {
        didSet {
            UserDefaults.standard.set(selectedASRModel.rawValue, forKey: "selectedASRModel")
        }
    }
    @Published var asrReady = false
    @Published var asrDownloading = false
    @Published var asrDownloadProgress: Double = 0
    @Published var asrDownloadDesc: String = ""
    @Published var asrError: String?

    func isASRModelDownloaded(_ model: ASRModel) -> Bool {
        WhisperASRService.isModelDownloaded(model)
    }
    var asrModelInfo: WhisperASRService.ModelInfo? { whisperASRService.modelInfo }

    // MARK: - Init

    init() {
        let modeString = UserDefaults.standard.string(forKey: "serviceMode") ?? ServiceMode.telegram.rawValue
        self.activeMode = ServiceMode(rawValue: modeString) ?? .telegram
        self.botToken = UserDefaults.standard.string(forKey: "botToken") ?? ""
        let savedIds = UserDefaults.standard.array(forKey: "allowedChatIds") as? [Int64] ?? []
        self.allowedChatIds = Set(savedIds)
        self.copyAllMessages = UserDefaults.standard.bool(forKey: "copyAllMessages")
        self.showNotification = UserDefaults.standard.object(forKey: "showNotification") as? Bool ?? true
        self.enableTranslation = UserDefaults.standard.object(forKey: "enableTranslation") as? Bool ?? false
        self.enablePromptOptimization = UserDefaults.standard.object(forKey: "enablePromptOptimization") as? Bool ?? false
        self.autoSaveImages = UserDefaults.standard.object(forKey: "autoSaveImages") as? Bool ?? false
        self.imageSavePath = UserDefaults.standard.string(forKey: "imageSavePath")
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? ""
        self.openAIAPIKey = UserDefaults.standard.string(forKey: "openAIAPIKey") ?? ""
        self.openAIBaseURL = UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1"
        self.openAIModel = UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4.1-mini"

        let savedModel = UserDefaults.standard.string(forKey: "selectedASRModel") ?? ASRModel.whisperTurbo.rawValue
        self.selectedASRModel = ASRModel(rawValue: savedModel) ?? .whisperTurbo

        processor.showNotification = showNotification
        processor.enableTranslation = enableTranslation
        processor.enablePromptOptimization = enablePromptOptimization
        processor.autoSaveImages = autoSaveImages
        processor.imageSavePath = imageSavePath
        processor.openAIAPIKey = openAIAPIKey
        processor.openAIBaseURL = openAIBaseURL
        processor.openAIModel = openAIModel
        processor.onMessageProcessed = { [weak self] item in
            Task { @MainActor in
                self?.addMessage(item)
            }
        }
        processor.onClipboardStateChange = { [weak self] state in
            Task { @MainActor in
                self?.updateClipboardProcessingState(state)
            }
        }

        localIPAddress = LANService.getLocalIPAddress() ?? "未知"

        // 初始化 Whisper ASR 模型
        initASR()
    }

    // MARK: - Whisper ASR

    private func initASR() {
        let model = selectedASRModel
        guard WhisperASRService.isModelDownloaded(model) else {
            print("⚠️ [Whisper] 模型未下载: \(model.displayName)")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.whisperASRService.initialize(model: model) ?? false
            DispatchQueue.main.async {
                self?.asrReady = success
                if !success {
                    self?.asrError = "\(model.shortName) 模型加载失败"
                }
            }
        }
    }

    func downloadASRModel() {
        let model = selectedASRModel
        asrDownloading = true
        asrDownloadProgress = 0
        asrDownloadDesc = "准备下载..."
        asrError = nil

        whisperASRService.onDownloadProgress = { [weak self] progress, desc in
            DispatchQueue.main.async {
                self?.asrDownloadProgress = progress
                self?.asrDownloadDesc = desc
            }
        }
        whisperASRService.onDownloadComplete = { [weak self] success, error in
            DispatchQueue.main.async {
                self?.asrDownloading = false
                if success {
                    self?.asrDownloadDesc = "下载完成，正在加载模型..."
                    self?.initASR()
                } else {
                    self?.asrError = error ?? "下载失败"
                    self?.asrDownloadDesc = ""
                }
            }
        }
        whisperASRService.downloadModel(model)
    }

    func cancelASRDownload() {
        whisperASRService.cancelDownload()
        asrDownloading = false
        asrDownloadProgress = 0
        asrDownloadDesc = ""
    }

    /// 切换 ASR 模型：释放当前模型，加载新模型（如已下载）
    func switchASRModel(to model: ASRModel) {
        guard model != selectedASRModel || !asrReady else { return }
        selectedASRModel = model
        asrReady = false
        asrError = nil
        whisperASRService.release()

        if WhisperASRService.isModelDownloaded(model) {
            initASR()
        }
    }

    // MARK: - 当前面板的启停（UI 按钮调用）

    func startCurrentMode() {
        switch activeMode {
        case .telegram: startTelegram()
        case .lan: startLAN()
        }
    }

    func stopCurrentMode() {
        switch activeMode {
        case .telegram: stopTelegram()
        case .lan: stopLAN()
        }
    }

    /// 兼容旧接口：启动当前模式
    func start() { startCurrentMode() }

    /// 兼容旧接口：停止当前模式
    func stop() { stopCurrentMode() }

    // MARK: - Telegram 独立启停

    func stopTelegram() {
        telegramService?.stopPolling()
        telegramService = nil
        telegramActive = false
        telegramStatus = .disconnected
        telegramError = nil
    }

    private func startTelegram() {
        // 如果已在运行，先停止
        if telegramActive { stopTelegram() }

        let service = TelegramService()
        service.botToken = botToken
        service.allowedChatIds = allowedChatIds
        service.copyAllMessages = copyAllMessages

        service.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.telegramStatus = status }
        }
        service.onError = { [weak self] error in
            DispatchQueue.main.async { self?.telegramError = error }
        }
        service.onMessage = { [weak self] content, source, sourceDetail, senderName, messageId in
            guard let self = self else { return }
            self.processor.enableTranslation = self.enableTranslation
            self.processor.enablePromptOptimization = self.enablePromptOptimization
            await self.processor.process(
                content: content, source: source, sourceDetail: sourceDetail,
                senderName: senderName, messageId: messageId
            )
        }

        telegramService = service
        telegramActive = true
        telegramStatus = .connecting
        service.startPolling()
    }

    // MARK: - LAN 独立启停

    func stopLAN() {
        lanService?.stop()
        lanService = nil
        lanActive = false
        lanStatus = .disconnected
        lanError = nil
        lanConnectedDevices = []
        lanPort = 0
    }

    private func startLAN() {
        // 如果已在运行，先停止
        if lanActive { stopLAN() }

        let service = LANService()

        service.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.lanStatus = status }
        }
        service.onError = { [weak self] error in
            DispatchQueue.main.async { self?.lanError = error }
        }
        service.onMessage = { [weak self] content, source, sourceDetail, senderName, messageId in
            guard let self = self else { return }
            self.processor.enableTranslation = self.enableTranslation
            self.processor.enablePromptOptimization = self.enablePromptOptimization
            await self.processor.process(
                content: content, source: source, sourceDetail: sourceDetail,
                senderName: senderName, messageId: messageId
            )
        }
        service.onDevicesChanged = { [weak self] devices in
            DispatchQueue.main.async { self?.lanConnectedDevices = devices }
        }
        service.onPortAssigned = { [weak self] port in
            DispatchQueue.main.async { self?.lanPort = port }
        }

        // 非流式 ASR 回调：录完整段后一次性识别
        service.onAudioReceived = { [weak self] pcmData, sampleRate, connection, key in
            guard let self = self, self.whisperASRService.isReady else {
                service.sendASRError(to: connection, message: "Whisper 模型未就绪")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let text = self.whisperASRService.transcribe(pcmData: pcmData, sampleRate: sampleRate)
                DispatchQueue.main.async {
                    if text.isEmpty {
                        service.sendASRError(to: connection, message: "识别结果为空")
                    } else {
                        service.sendASRFinal(to: connection, text: text)
                    }
                }
            }
        }

        lanService = service
        lanActive = true
        do {
            try service.start()
        } catch {
            lanError = "启动服务器失败: \(error.localizedDescription)"
            lanActive = false
            lanStatus = .error
        }
    }

    @MainActor
    private func addMessage(_ item: MessageItem) {
        recentMessages.insert(item, at: 0)
        if recentMessages.count > 20 {
            recentMessages = Array(recentMessages.prefix(20))
        }
    }

    @MainActor
    private func updateClipboardProcessingState(_ state: ClipboardProcessingState) {
        clipboardStateResetTask?.cancel()
        clipboardStateResetTask = nil
        clipboardProcessingState = state

        switch state {
        case .completed, .failed:
            clipboardStateResetTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    guard let self = self, self.clipboardProcessingState == state else { return }
                    self.clipboardProcessingState = .idle
                }
            }
        case .idle, .processing:
            break
        }
    }

    // MARK: - Telegram Helpers

    func addChatId(_ id: Int64) { allowedChatIds.insert(id) }
    func removeChatId(_ id: Int64) { allowedChatIds.remove(id) }

    func testConnection() async -> (success: Bool, message: String, botName: String?) {
        let service = TelegramService()
        service.botToken = botToken
        return await service.testConnection()
    }

    @MainActor
    func refreshOpenAIModels() async {
        isFetchingOpenAIModels = true
        openAIModelFetchError = nil
        processor.openAIAPIKey = openAIAPIKey
        processor.openAIBaseURL = openAIBaseURL
        processor.openAIModel = openAIModel
        defer { isFetchingOpenAIModels = false }

        do {
            let models = try await processor.fetchAvailableModels()
            availableOpenAIModels = models
            let currentModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstModel = models.first,
               currentModel.isEmpty || currentModel == "gpt-4.1-mini" || !models.contains(currentModel) {
                openAIModel = firstModel
            }
        } catch {
            availableOpenAIModels = []
            openAIModelFetchError = error.localizedDescription
        }
    }

    @MainActor
    func runPromptOptimizationTest(input: String) async {
        isTestingPromptOptimization = true
        promptOptimizationTestError = nil
        promptOptimizationTestOutput = ""
        processor.openAIAPIKey = openAIAPIKey
        processor.openAIBaseURL = openAIBaseURL
        processor.openAIModel = openAIModel
        defer { isTestingPromptOptimization = false }

        do {
            let optimized = try await processor.testPromptOptimization(input)
            promptOptimizationTestOutput = optimized
        } catch {
            promptOptimizationTestError = error.localizedDescription
        }
    }

    // MARK: - Translation

    func prepareTranslation() {
        if translationConfig == nil {
            translationConfig = .init(
                source: Locale.Language(identifier: "zh-Hans"),
                target: Locale.Language(identifier: "en")
            )
        } else {
            translationConfig?.invalidate()
        }
    }
}
