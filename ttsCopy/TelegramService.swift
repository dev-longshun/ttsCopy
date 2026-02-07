//
//  TelegramService.swift
//  ttsCopy
//
//  Telegram Bot API 服务 - 长轮询获取消息
//

import Foundation
import AppKit
import UserNotifications

class TelegramService: ObservableObject {
    @Published var isPolling = false
    @Published var lastError: String?
    @Published var recentMessages: [MessageItem] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    // 配置项，保存到 UserDefaults
    @Published var botToken: String {
        didSet { UserDefaults.standard.set(botToken, forKey: "botToken") }
    }
    @Published var allowedChatIds: Set<Int64> {
        didSet { 
            let array = Array(allowedChatIds)
            UserDefaults.standard.set(array, forKey: "allowedChatIds") 
        }
    }
    @Published var copyAllMessages: Bool {
        didSet { UserDefaults.standard.set(copyAllMessages, forKey: "copyAllMessages") }
    }
    @Published var showNotification: Bool {
        didSet { UserDefaults.standard.set(showNotification, forKey: "showNotification") }
    }
    
    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64 = 0
    
    enum ConnectionStatus: String {
        case disconnected = "未连接"
        case connecting = "连接中..."
        case connected = "已连接"
        case error = "连接错误"
    }
    
    enum MessageContent: Equatable {
        case text(String)
        case photo(Data, caption: String?)
        
        var displayText: String {
            switch self {
            case .text(let str): return str
            case .photo(_, let caption): return caption ?? "[图片]"
            }
        }
    }
    
    struct MessageItem: Identifiable, Equatable {
        let id: Int64
        let content: MessageContent
        let chatId: Int64
        let chatTitle: String?
        let senderName: String
        let timestamp: Date
        
        var text: String { content.displayText }
    }
    
    init() {
        self.botToken = UserDefaults.standard.string(forKey: "botToken") ?? ""
        let savedIds = UserDefaults.standard.array(forKey: "allowedChatIds") as? [Int64] ?? []
        self.allowedChatIds = Set(savedIds)
        self.copyAllMessages = UserDefaults.standard.bool(forKey: "copyAllMessages")
        // 默认开启通知
        self.showNotification = UserDefaults.standard.object(forKey: "showNotification") as? Bool ?? true
        
        // 请求通知权限
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("通知权限请求失败: \(error)")
            }
        }
    }
    
    func startPolling() {
        // 调试：打印 Token 信息
        print("🔧 [DEBUG] 开始监听...")
        print("🔧 [DEBUG] Token 长度: \(botToken.count)")
        print("🔧 [DEBUG] Token 是否为空: \(botToken.isEmpty)")
        
        // 清理 Token（去除首尾空格和换行）
        let cleanedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedToken != botToken {
            print("🔧 [DEBUG] Token 包含多余空白字符，已清理")
            botToken = cleanedToken
        }
        
        // 验证 Token 格式
        let tokenPattern = #"^\d+:[A-Za-z0-9_-]+$"#
        let isValidFormat = cleanedToken.range(of: tokenPattern, options: .regularExpression) != nil
        print("🔧 [DEBUG] Token 格式验证: \(isValidFormat ? "✅ 有效" : "❌ 无效")")
        
        if !isValidFormat && !cleanedToken.isEmpty {
            print("🔧 [DEBUG] Token 前10字符: \(String(cleanedToken.prefix(10)))...")
            print("🔧 [DEBUG] Token 应该是类似: 123456789:ABCdefGHI... 的格式")
        }
        
        guard !cleanedToken.isEmpty else {
            lastError = "请先配置 Bot Token"
            return
        }
        
        isPolling = true
        connectionStatus = .connecting
        lastError = nil
        
        pollingTask = Task {
            await pollMessages()
        }
    }
    
    func stopPolling() {
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
        connectionStatus = .disconnected
    }
    
    private func pollMessages() async {
        while isPolling && !Task.isCancelled {
            do {
                let updates = try await getUpdates()
                
                await MainActor.run {
                    connectionStatus = .connected
                    lastError = nil
                }
                
                for update in updates {
                    if let message = update.message {
                        await processMessage(message)
                    }
                    lastUpdateId = max(lastUpdateId, update.updateId + 1)
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .error
                    lastError = error.localizedDescription
                }
                // 出错后等待几秒再重试
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    
    private func getUpdates() async throws -> [TelegramUpdate] {
        // 构建 URL
        var urlString = "https://api.telegram.org/bot\(botToken)/getUpdates?timeout=30"
        if lastUpdateId > 0 {
            urlString += "&offset=\(lastUpdateId)"
        }
        
        // 调试：打印请求信息（隐藏部分 Token）
        let maskedUrl = urlString.replacingOccurrences(
            of: botToken,
            with: String(botToken.prefix(10)) + "..." + String(botToken.suffix(5))
        )
        print("🌐 [DEBUG] 请求 URL: \(maskedUrl)")
        
        guard let url = URL(string: urlString) else {
            print("❌ [DEBUG] URL 格式错误!")
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 35 // 比长轮询超时稍长
        
        print("🌐 [DEBUG] 发送请求中...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [DEBUG] 响应格式错误!")
            throw URLError(.badServerResponse)
        }
        
        print("🌐 [DEBUG] HTTP 状态码: \(httpResponse.statusCode)")
        
        // 打印响应内容（限制长度）
        if let responseString = String(data: data, encoding: .utf8) {
            let truncated = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
            print("🌐 [DEBUG] 响应内容: \(truncated)")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            print("❌ [DEBUG] API 错误: \(errorMessage)")
            
            // 特殊处理 404 错误
            if httpResponse.statusCode == 404 {
                print("❌ [DEBUG] 404 错误通常表示 Bot Token 无效!")
                print("❌ [DEBUG] 请检查:")
                print("   1. Token 是否完整复制（包括冒号前后的部分）")
                print("   2. Token 是否有多余的空格或换行")
                print("   3. Bot 是否已被删除或禁用")
            }
            
            throw NSError(domain: "TelegramAPI", code: httpResponse.statusCode, 
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        let result = try JSONDecoder().decode(TelegramResponse.self, from: data)
        
        if !result.ok {
            print("❌ [DEBUG] API 返回失败: \(result.description ?? "未知")")
            throw NSError(domain: "TelegramAPI", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: result.description ?? "API 错误"])
        }
        
        print("✅ [DEBUG] 请求成功，获取到 \(result.result?.count ?? 0) 条更新")
        
        return result.result ?? []
    }
    
    @MainActor
    private func processMessage(_ message: TelegramMessage) async {
        let chatId = message.chat.id
        let chatTitle = message.chat.title ?? "私聊"
        let senderName = message.from?.firstName ?? "未知"
        let text = message.text ?? ""
        let caption = message.caption
        
        // 打印收到的消息信息，方便调试和获取 Chat ID
        print("📨 收到消息:")
        print("   Chat ID: \(chatId)")
        print("   Chat Title: \(chatTitle)")
        print("   Sender: \(senderName)")
        print("   Text: \(text)")
        
        // 检查是否应该处理这条消息
        let shouldProcess = copyAllMessages || allowedChatIds.contains(chatId)
        
        guard shouldProcess else {
            print("   ⚠️ Chat ID \(chatId) 不在允许列表中，已忽略")
            return
        }
        
        // 判断消息类型：图片 or 文字
        if let photos = message.photo, !photos.isEmpty {
            // 取最大尺寸的图片（数组最后一个）
            let largestPhoto = photos.last!
            print("   📷 收到图片，file_id: \(largestPhoto.fileId)")
            
            if let imageData = await downloadFile(fileId: largestPhoto.fileId) {
                let content = MessageContent.photo(imageData, caption: caption)
                let messageItem = MessageItem(
                    id: Int64(message.messageId),
                    content: content,
                    chatId: chatId,
                    chatTitle: chatTitle,
                    senderName: senderName,
                    timestamp: Date()
                )
                addMessageAndNotify(messageItem, chatTitle: chatTitle)
                copyImageToClipboard(imageData, caption: caption)
            } else {
                print("   ❌ 图片下载失败")
            }
        } else if !text.isEmpty {
            let content = MessageContent.text(text)
            let messageItem = MessageItem(
                id: Int64(message.messageId),
                content: content,
                chatId: chatId,
                chatTitle: chatTitle,
                senderName: senderName,
                timestamp: Date()
            )
            addMessageAndNotify(messageItem, chatTitle: chatTitle)
            copyToClipboard(text)
        }
    }
    
    @MainActor
    private func addMessageAndNotify(_ messageItem: MessageItem, chatTitle: String) {
        recentMessages.insert(messageItem, at: 0)
        if recentMessages.count > 20 {
            recentMessages = Array(recentMessages.prefix(20))
        }
        if showNotification {
            sendNotification(title: chatTitle, body: messageItem.text)
        }
    }
    
    /// 通过 file_id 获取文件路径并下载
    private func downloadFile(fileId: String) async -> Data? {
        // 1. 调用 getFile 获取 file_path
        let urlString = "https://api.telegram.org/bot\(botToken)/getFile?file_id=\(fileId)"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(TelegramFileResponse.self, from: data)
            guard let filePath = response.result?.filePath else {
                print("   ❌ getFile 未返回 file_path")
                return nil
            }
            
            // 2. 下载文件
            let downloadUrl = "https://api.telegram.org/file/bot\(botToken)/\(filePath)"
            guard let fileUrl = URL(string: downloadUrl) else { return nil }
            
            let (fileData, _) = try await URLSession.shared.data(from: fileUrl)
            print("   ✅ 图片下载成功，大小: \(fileData.count) bytes")
            return fileData
        } catch {
            print("   ❌ 下载文件失败: \(error)")
            return nil
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
            // 如果有 caption，同时写入文字
            if let caption = caption, !caption.isEmpty {
                pasteboard.setString(caption, forType: .string)
            }
            print("   ✅ 图片已复制到剪贴板")
        } else {
            print("   ❌ 无法解析图片数据")
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "TTS Copy - \(title)"
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("   ⚠️ 发送通知失败: \(error)")
            }
        }
    }
    
    // 添加/移除允许的 Chat ID
    func addChatId(_ chatId: Int64) {
        allowedChatIds.insert(chatId)
    }
    
    func removeChatId(_ chatId: Int64) {
        allowedChatIds.remove(chatId)
    }
    
    // 测试 Token 是否有效
    func testConnection() async -> (success: Bool, message: String, botName: String?) {
        let cleanedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanedToken.isEmpty else {
            return (false, "Token 为空", nil)
        }
        
        let urlString = "https://api.telegram.org/bot\(cleanedToken)/getMe"
        print("🧪 [TEST] 测试连接: \(urlString.replacingOccurrences(of: cleanedToken, with: "***"))")
        
        guard let url = URL(string: urlString) else {
            return (false, "URL 格式错误", nil)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "响应格式错误", nil)
            }
            
            print("🧪 [TEST] HTTP 状态码: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("🧪 [TEST] 响应: \(responseString)")
            }
            
            if httpResponse.statusCode == 200 {
                // 解析 Bot 信息
                struct GetMeResponse: Codable {
                    let ok: Bool
                    let result: BotInfo?
                }
                struct BotInfo: Codable {
                    let id: Int64
                    let first_name: String
                    let username: String?
                }
                
                if let getMeResponse = try? JSONDecoder().decode(GetMeResponse.self, from: data),
                   let botInfo = getMeResponse.result {
                    return (true, "连接成功！Bot: @\(botInfo.username ?? botInfo.first_name)", botInfo.username)
                }
                return (true, "连接成功！", nil)
            } else if httpResponse.statusCode == 404 {
                return (false, "Token 无效 (404)。请检查 Token 是否正确。", nil)
            } else if httpResponse.statusCode == 401 {
                return (false, "Token 未授权 (401)。Token 可能已过期。", nil)
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
                return (false, "错误 \(httpResponse.statusCode): \(errorMsg)", nil)
            }
        } catch {
            print("🧪 [TEST] 错误: \(error)")
            return (false, "网络错误: \(error.localizedDescription)", nil)
        }
    }
}

// MARK: - Telegram API 响应模型

struct TelegramResponse: Codable {
    let ok: Bool
    let description: String?
    let result: [TelegramUpdate]?
}

struct TelegramUpdate: Codable {
    let updateId: Int64
    let message: TelegramMessage?
    
    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

struct TelegramMessage: Codable {
    let messageId: Int
    let from: TelegramUser?
    let chat: TelegramChat
    let text: String?
    let caption: String?
    let photo: [TelegramPhotoSize]?
    let date: Int
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from
        case chat
        case text
        case caption
        case photo
        case date
    }
}

struct TelegramPhotoSize: Codable {
    let fileId: String
    let fileUniqueId: String
    let width: Int
    let height: Int
    let fileSize: Int?
    
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileUniqueId = "file_unique_id"
        case width
        case height
        case fileSize = "file_size"
    }
}

struct TelegramUser: Codable {
    let id: Int64
    let firstName: String
    let lastName: String?
    let username: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case username
    }
}

struct TelegramChat: Codable {
    let id: Int64
    let type: String
    let title: String?
}

struct TelegramFileResponse: Codable {
    let ok: Bool
    let result: TelegramFile?
}

struct TelegramFile: Codable {
    let fileId: String
    let filePath: String?
    
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case filePath = "file_path"
    }
}
