//
//  ServiceManager.swift
//  ttsCopy
//
//  统一服务管理，作为 UI 的 @EnvironmentObject
//  管理 Telegram 监听的生命周期与设置持久化
//

import Foundation
import SwiftUI

class ServiceManager: ObservableObject {

    // MARK: - Telegram 状态

    @Published var telegramActive = false
    @Published var telegramStatus: ConnectionStatus = .disconnected
    @Published var telegramError: String?
    /// 同一个 Bot 被另一台设备占用（Telegram 409），本机已停止监听
    @Published var telegramConflict = false

    @Published var recentMessages: [MessageItem] = []
    @Published var clipboardProcessingState: ClipboardProcessingState = .idle

    // MARK: - Shared Settings

    @Published var showNotification: Bool {
        didSet {
            UserDefaults.standard.set(showNotification, forKey: "showNotification")
            processor.showNotification = showNotification
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

    // MARK: - Internal

    let processor = MessageProcessor()
    private var telegramService: TelegramService?
    private var clipboardStateResetTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        self.botToken = UserDefaults.standard.string(forKey: "botToken") ?? ""
        let savedIds = UserDefaults.standard.array(forKey: "allowedChatIds") as? [Int64] ?? []
        self.allowedChatIds = Set(savedIds)
        self.copyAllMessages = UserDefaults.standard.bool(forKey: "copyAllMessages")
        self.showNotification = UserDefaults.standard.object(forKey: "showNotification") as? Bool ?? true
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
        processor.onClipboardStateChange = { [weak self] state in
            Task { @MainActor in
                self?.updateClipboardProcessingState(state)
            }
        }
    }

    // MARK: - Telegram 启停

    func stopTelegram() {
        telegramService?.stopPolling()
        telegramService = nil
        telegramActive = false
        telegramStatus = .disconnected
        telegramError = nil
        telegramConflict = false
    }

    /// 另一台设备占用了 Bot 后，在本机重新开始监听（会把对方挤掉）
    func takeOverTelegram() {
        startTelegram()
    }

    func startTelegram() {
        // 如果已在运行，先停止
        if telegramActive { stopTelegram() }
        telegramConflict = false

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
        service.onConflict = { [weak self, weak service] in
            DispatchQueue.main.async {
                guard let self = self, let service = service,
                      self.telegramService === service else { return }
                self.handleTelegramConflict()
            }
        }
        service.onMessage = { [weak self] content, source, sourceDetail, senderName, messageId in
            guard let self = self else { return }
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

    private func handleTelegramConflict() {
        let message = "另一台设备正在使用这个 Bot，本机已停止监听"
        // 轮询循环已自行退出；不调 stopPolling，避免它回调的「未连接」盖掉错误状态
        telegramService = nil
        telegramActive = false
        telegramStatus = .error
        telegramError = message
        telegramConflict = true
        // 冲突提醒不受「收到消息时显示通知」开关影响
        processor.sendNotification(title: "Telegram 冲突", body: message)
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

        guard state == .completed else { return }
        clipboardStateResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // 2 秒内又来了新消息时旧任务被取消，不能把新消息的绿勾提前清掉
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self, self.clipboardProcessingState == state else { return }
                self.clipboardProcessingState = .idle
            }
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
}
