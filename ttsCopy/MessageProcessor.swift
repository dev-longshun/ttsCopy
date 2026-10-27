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
        let baseName = "ttscopy_\(formatter.string(from: Date()))"
        let ext = Self.imageFileExtension(for: imageData)
        var fileURL = dirURL.appendingPathComponent("\(baseName).\(ext)")
        // 同一秒连发多张时文件名相同，追加序号避免互相覆盖
        var index = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = dirURL.appendingPathComponent("\(baseName)_\(index).\(ext)")
            index += 1
        }
        do {
            try imageData.write(to: fileURL)
            print("   ✅ 图片已保存到: \(fileURL.path)")
        } catch {
            print("   ❌ 保存图片失败: \(error)")
        }
    }

    /// 按文件头判断图片格式；Telegram 压缩过的图片都是 JPEG，按文件发送的保留原格式
    private static func imageFileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        guard bytes.count == 12 else { return "jpg" }
        // RIFF....WEBP
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]), bytes[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50]) {
            return "webp"
        }
        // ....ftyp + HEIF 品牌
        if bytes[4..<8].elementsEqual([0x66, 0x74, 0x79, 0x70]),
           let brand = String(bytes: bytes[8..<12], encoding: .ascii),
           ["heic", "heix", "hevc", "mif1"].contains(brand) {
            return "heic"
        }
        return "jpg"
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
