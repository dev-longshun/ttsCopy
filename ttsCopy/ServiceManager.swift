//
//  ServiceManager.swift
//  ttsCopy
//
//  统一服务管理，作为 UI 的 @EnvironmentObject
//

import Foundation
import SwiftUI
import Translation

class ServiceManager: ObservableObject {

    // MARK: - Published State

    @Published var activeMode: ServiceMode {
        didSet {
            UserDefaults.standard.set(activeMode.rawValue, forKey: "serviceMode")
            stop()
        }
    }
    @Published var isActive = false
    @Published var lastError: String?
    @Published var recentMessages: [MessageItem] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // Shared settings
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

    // Telegram-specific
    @Published var botToken: String {
        didSet { UserDefaults.standard.set(botToken, forKey: "botToken") }
    }
    @Published var allowedChatIds: Set<Int64> {
        didSet { UserDefaults.standard.set(Array(allowedChatIds), forKey: "allowedChatIds") }
    }
    @Published var copyAllMessages: Bool {
        didSet { UserDefaults.standard.set(copyAllMessages, forKey: "copyAllMessages") }
    }

    // LAN-specific
    @Published var lanPort: UInt16 = 0
    @Published var lanConnectedDevices: [String] = []
    @Published var localIPAddress: String = ""

    // Translation
    var translationSession: TranslationSession? {
        get { processor.translationSession }
        set { processor.translationSession = newValue }
    }
    @Published var translationConfig: TranslationSession.Configuration?

    // MARK: - Internal

    let processor = MessageProcessor()
    private var telegramService: TelegramService?
    private var lanService: LANService?

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
    }

    // MARK: - Start / Stop

    func start() {
        stop()
        switch activeMode {
        case .telegram:
            startTelegram()
        case .lan:
            startLAN()
        }
    }

    func stop() {
        telegramService?.stopPolling()
        telegramService = nil
        lanService?.stop()
        lanService = nil
        isActive = false
        connectionStatus = .disconnected
        lastError = nil
        lanConnectedDevices = []
        lanPort = 0
    }

    private func startTelegram() {
        let service = TelegramService()
        service.botToken = botToken
        service.allowedChatIds = allowedChatIds
        service.copyAllMessages = copyAllMessages

        service.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.connectionStatus = status }
        }
        service.onError = { [weak self] error in
            DispatchQueue.main.async { self?.lastError = error }
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
        isActive = true
        connectionStatus = .connecting
        service.startPolling()
    }

    private func startLAN() {
        let service = LANService()

        service.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.connectionStatus = status }
        }
        service.onError = { [weak self] error in
            DispatchQueue.main.async { self?.lastError = error }
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

        lanService = service
        isActive = true
        do {
            try service.start()
        } catch {
            lastError = "启动服务器失败: \(error.localizedDescription)"
            isActive = false
            connectionStatus = .error
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
