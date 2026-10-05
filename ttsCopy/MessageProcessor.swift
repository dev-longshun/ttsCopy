//
//  MessageProcessor.swift
//  ttsCopy
//
//  消息处理逻辑：剪贴板、通知、图片保存
//

import Foundation
import AppKit
import UserNotifications

class MessageProcessor {

    var showNotification: Bool = true
    var autoSaveImages: Bool = false
    var imageSavePath: String = ""

    var onMessageProcessed: ((MessageItem) -> Void)?
    var onClipboardStateChange: ((ClipboardProcessingState) -> Void)?

    init() {
        requestNotificationPermission()
    }

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
            let item = MessageItem(
                id: messageId, content: .text(text),
                source: source, sourceDetail: sourceDetail,
                senderName: senderName, timestamp: Date()
            )
            onMessageProcessed?(item)

            copyToClipboard(text)
            onClipboardStateChange?(.completed)

            if showNotification {
                sendNotification(title: sourceDetail ?? source, body: text)
            }

        case .photo(let data, let caption):
            let item = MessageItem(
                id: messageId, content: .photo(data, caption: caption),
                source: source, sourceDetail: sourceDetail,
                senderName: senderName, timestamp: Date()
            )
            onMessageProcessed?(item)

            copyImageToClipboard(data, caption: caption)
            if autoSaveImages {
                saveImageToFile(data, caption: caption)
            }
            onClipboardStateChange?(.completed)

            if showNotification {
                sendNotification(title: sourceDetail ?? source, body: caption ?? "[图片]")
            }
        }
    }

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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error { print("通知权限请求失败: \(error)") }
        }
    }

    func sendNotification(title: String, body: String) {
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
