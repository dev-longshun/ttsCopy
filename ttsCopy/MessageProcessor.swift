//
//  MessageProcessor.swift
//  ttsCopy
//
//  消息处理逻辑：剪贴板、通知、翻译、图片保存
//

import Foundation
import AppKit
import UserNotifications
import Translation

class MessageProcessor {

    var showNotification: Bool = true
    var enableTranslation: Bool = false
    var autoSaveImages: Bool = false
    var imageSavePath: String = ""

    /// 由 SwiftUI .translationTask 提供的翻译 session
    var translationSession: TranslationSession?

    /// 消息处理完成回调
    var onMessageProcessed: ((MessageItem) -> Void)?

    init() {
        requestNotificationPermission()
    }

    // MARK: - 处理入口

    @MainActor
    func process(
        content: MessageContent,
        source: String,
        sourceDetail: String?,
        senderName: String,
        messageId: Int64
    ) async {
        switch content {
        case .text(let text):
            let textToCopy = enableTranslation ? await translateText(text) : text
            let item = MessageItem(
                id: messageId, content: .text(text),
                source: source, sourceDetail: sourceDetail,
                senderName: senderName, timestamp: Date()
            )
            onMessageProcessed?(item)
            copyToClipboard(textToCopy)
            if showNotification {
                sendNotification(title: sourceDetail ?? source, body: text)
            }

        case .photo(let data, let caption):
            let translatedCaption: String?
            if enableTranslation, let cap = caption, !cap.isEmpty {
                translatedCaption = await translateText(cap)
            } else {
                translatedCaption = caption
            }
            let item = MessageItem(
                id: messageId, content: .photo(data, caption: caption),
                source: source, sourceDetail: sourceDetail,
                senderName: senderName, timestamp: Date()
            )
            onMessageProcessed?(item)
            copyImageToClipboard(data, caption: translatedCaption)
            if autoSaveImages {
                saveImageToFile(data, caption: translatedCaption)
            }
            if showNotification {
                sendNotification(title: sourceDetail ?? source, body: caption ?? "[图片]")
            }
        }
    }

    // MARK: - Translation

    func translateText(_ text: String) async -> String {
        guard let session = translationSession else { return text }
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            return text
        }
    }

    // MARK: - Clipboard

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("   ✅ 已复制到剪贴板")
    }

    private func copyImageToClipboard(_ imageData: Data, caption: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
            if let caption = caption, !caption.isEmpty {
                pasteboard.setString(caption, forType: .string)
            }
            print("   ✅ 图片已复制到剪贴板")
        }
    }

    // MARK: - Image Save

    private func saveImageToFile(_ imageData: Data, caption: String?) {
        guard !imageSavePath.isEmpty else { return }
        let dirURL = URL(fileURLWithPath: imageSavePath)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            print("   ❌ 创建目录失败: \(error)")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "ttscopy_\(formatter.string(from: Date())).jpg"
        let fileURL = dirURL.appendingPathComponent(fileName)
        do {
            try imageData.write(to: fileURL)
            print("   ✅ 图片已保存到: \(fileURL.path)")
        } catch {
            print("   ❌ 保存图片失败: \(error)")
        }
    }

    // MARK: - Notification

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error { print("通知权限请求失败: \(error)") }
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "TTS Copy - \(title)"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("   ⚠️ 发送通知失败: \(error)") }
        }
    }
}
