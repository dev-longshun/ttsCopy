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
    private let asrService = ASRService()
    private let streamingASRService = StreamingASRService()

    // MARK: - ASR State

    @Published var asrReady = false
    @Published var asrDownloading = false
    @Published var asrDownloadProgress: Double = 0
    @Published var asrDownloadDesc: String = ""
    @Published var asrError: String?

    var asrModelDownloaded: Bool { ASRService.isModelDownloaded }

    // MARK: - Streaming ASR State

    @Published var streamingAsrReady = false
    @Published var streamingAsrDownloading = false
    @Published var streamingAsrDownloadProgress: Double = 0
    @Published var streamingAsrDownloadDesc: String = ""
    @Published var streamingAsrError: String?

    var streamingAsrModelDownloaded: Bool { StreamingASRService.isModelDownloaded }

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
        self.autoSaveImages = UserDefaults.standard.object(forKey: "autoSaveImages") as? Bool ?? false
        self.imageSavePath = UserDefaults.standard.string(forKey: "imageSavePath")
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? ""

        processor.showNotification = showNotification
        processor.autoSaveImages = autoSaveImages
        processor.imageSavePath = imageSavePath
        processor.onMessageProcessed = { [weak self] item in
            Task { @MainActor in
                self?.addMessage(item)
            }
        }

        localIPAddress = LANService.getLocalIPAddress() ?? "未知"

        // 初始化 ASR 模型
        initASR()
        initStreamingASR()
    }

    // MARK: - ASR

    private func initASR() {
        guard ASRService.isModelDownloaded else {
            print("⚠️ [ASR] 模型未下载，请在设置中下载。")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.asrService.initialize(modelsDir: ASRService.modelsDir) ?? false
            DispatchQueue.main.async {
                self?.asrReady = success
                if !success {
                    self?.asrError = "模型加载失败"
                }
            }
        }
    }

    func downloadASRModel() {
        asrDownloading = true
        asrDownloadProgress = 0
        asrDownloadDesc = "准备下载..."
        asrError = nil

        asrService.onDownloadProgress = { [weak self] progress, desc in
            self?.asrDownloadProgress = progress
            self?.asrDownloadDesc = desc
        }
        asrService.onDownloadComplete = { [weak self] success, error in
            self?.asrDownloading = false
            if success {
                self?.asrDownloadDesc = "下载完成，正在加载模型..."
                self?.initASR()
            } else {
                self?.asrError = error ?? "下载失败"
                self?.asrDownloadDesc = ""
            }
        }
        asrService.downloadModel()
    }

    func cancelASRDownload() {
        asrService.cancelDownload()
        asrDownloading = false
        asrDownloadProgress = 0
        asrDownloadDesc = ""
    }

    // MARK: - Streaming ASR

    private func initStreamingASR() {
        guard StreamingASRService.isModelDownloaded else {
            print("⚠️ [StreamingASR] 流式模型未下载")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.streamingASRService.initialize(modelsDir: StreamingASRService.modelsDir) ?? false
            DispatchQueue.main.async {
                self?.streamingAsrReady = success
                if !success {
                    self?.streamingAsrError = "流式模型加载失败"
                }
            }
        }
    }

    func downloadStreamingASRModel() {
        streamingAsrDownloading = true
        streamingAsrDownloadProgress = 0
        streamingAsrDownloadDesc = "准备下载..."
        streamingAsrError = nil

        streamingASRService.onDownloadProgress = { [weak self] progress, desc in
            DispatchQueue.main.async {
                self?.streamingAsrDownloadProgress = progress
                self?.streamingAsrDownloadDesc = desc
            }
        }
        streamingASRService.onDownloadComplete = { [weak self] success, error in
            DispatchQueue.main.async {
                self?.streamingAsrDownloading = false
                if success {
                    self?.streamingAsrDownloadDesc = "下载完成，正在加载模型..."
                    self?.initStreamingASR()
                } else {
                    self?.streamingAsrError = error ?? "下载失败"
                    self?.streamingAsrDownloadDesc = ""
                }
            }
        }
        streamingASRService.downloadModel()
    }

    func cancelStreamingASRDownload() {
        streamingASRService.cancelDownload()
        streamingAsrDownloading = false
        streamingAsrDownloadProgress = 0
        streamingAsrDownloadDesc = ""
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

        // ASR：收到完整音频后在后台线程识别，结果回传手机（非流式后备路径）
        service.onAudioReceived = { [weak self] pcmData, sampleRate, connection in
            guard let self = self else { return }
            guard self.asrService.isReady else {
                service.sendASRError(to: connection, message: "ASR 模型未就绪")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let text = self.asrService.transcribe(pcmData: pcmData, sampleRate: sampleRate)
                DispatchQueue.main.async {
                    if text.isEmpty {
                        service.sendASRError(to: connection, message: "识别结果为空")
                    } else {
                        service.sendASRFinal(to: connection, text: text)
                    }
                }
            }
        }

        // 流式 ASR 回调
        service.onAudioSessionStart = { [weak self] sampleRate, connection, key in
            guard let self = self, self.streamingASRService.isReady else { return false }
            self.streamingASRService.startSession()
            return true
        }

        service.onAudioChunkReceived = { [weak self] pcmData, sampleRate, connection, key in
            guard let self = self, self.streamingASRService.isReady else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if let partialText = self.streamingASRService.feedSamples(pcmData: pcmData, sampleRate: sampleRate) {
                    DispatchQueue.main.async {
                        service.sendASRPartial(to: connection, text: partialText)
                    }
                }
            }
        }

        service.onAudioSessionEnd = { [weak self] connection, key in
            guard let self = self, self.streamingASRService.isReady else {
                service.sendASRError(to: connection, message: "流式 ASR 模型未就绪")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let text = self.streamingASRService.endSession()
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

    // MARK: - Telegram Helpers

    func addChatId(_ id: Int64) { allowedChatIds.insert(id) }
    func removeChatId(_ id: Int64) { allowedChatIds.remove(id) }

    func testConnection() async -> (success: Bool, message: String, botName: String?) {
        let service = TelegramService()
        service.botToken = botToken
        return await service.testConnection()
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
