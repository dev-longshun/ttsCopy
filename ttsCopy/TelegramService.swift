//
//  TelegramService.swift
//  ttsCopy
//
//  Telegram Bot API 传输层 - 长轮询获取消息
//

import Foundation

class TelegramService {

    var botToken: String = ""
    var allowedChatIds: Set<Int64> = []
    var copyAllMessages: Bool = false

    // Callbacks
    var onStatusChange: ((ConnectionStatus) -> Void)?
    var onError: ((String?) -> Void)?
    var onMessage: ((MessageContent, String, String?, String, Int64) async -> Void)?
    /// 同一个 Bot 被另一处 getUpdates 抢占（如另一台 Mac 也在跑），轮询已停止
    var onConflict: (() -> Void)?

    private var pollingTask: Task<Void, Never>?
    private var lastUpdateId: Int64 = 0

    /// 最近收到 409 的时间。窗口内累计达到阈值才判定冲突，
    /// 偶发一次（如本机刚重启、旧的长轮询还没断）只短暂重试
    private var conflictTimestamps: [Date] = []
    private static let conflictWindow: TimeInterval = 120
    private static let conflictThreshold = 2

    var isPolling: Bool { pollingTask != nil && !(pollingTask?.isCancelled ?? true) }

    func startPolling() {
        let cleanedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedToken != botToken { botToken = cleanedToken }

        guard !cleanedToken.isEmpty else {
            onError?("请先配置 Bot Token")
            return
        }

        onStatusChange?(.connecting)
        onError?(nil)

        pollingTask = Task {
            await pollMessages()
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        onStatusChange?(.disconnected)
    }

    private func pollMessages() async {
        while !Task.isCancelled {
            do {
                let updates = try await getUpdates()
                onStatusChange?(.connected)
                onError?(nil)

                for update in updates {
                    if let message = update.message {
                        await processMessage(message)
                    }
                    lastUpdateId = max(lastUpdateId, update.updateId + 1)
                }
            } catch {
                if Task.isCancelled { break }
                if Self.isConflict(error) {
                    let now = Date()
                    conflictTimestamps = conflictTimestamps.filter {
                        now.timeIntervalSince($0) < Self.conflictWindow
                    } + [now]
                    if conflictTimestamps.count >= Self.conflictThreshold {
                        onStatusChange?(.error)
                        onError?("另一台设备正在使用这个 Bot，本机已停止监听")
                        onConflict?()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                onStatusChange?(.error)
                onError?(error.localizedDescription)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// Telegram 409：Conflict: terminated by other getUpdates request
    private static func isConflict(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "TelegramAPI" && nsError.code == 409
    }

    private func getUpdates() async throws -> [TelegramUpdate] {
        var urlString = "https://api.telegram.org/bot\(botToken)/getUpdates?timeout=30"
        if lastUpdateId > 0 {
            urlString += "&offset=\(lastUpdateId)"
        }

        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 35

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
            throw NSError(domain: "TelegramAPI", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        let result = try JSONDecoder().decode(TelegramResponse.self, from: data)
        if !result.ok {
            throw NSError(domain: "TelegramAPI", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: result.description ?? "API 错误"])
        }
        return result.result ?? []
    }

    private func processMessage(_ message: TelegramMessage) async {
        let chatId = message.chat.id
        let chatTitle = message.chat.title ?? "私聊"
        let senderName = message.from?.firstName ?? "未知"

        let shouldProcess = copyAllMessages || allowedChatIds.contains(chatId)
        guard shouldProcess else { return }

        if let photos = message.photo, !photos.isEmpty {
            let largestPhoto = photos.last!
            if let imageData = await downloadFile(fileId: largestPhoto.fileId) {
                await onMessage?(
                    .photo(imageData, caption: message.caption),
                    "Telegram", chatTitle, senderName, Int64(message.messageId)
                )
            }
        } else if let text = message.text, !text.isEmpty {
            await onMessage?(
                .text(text),
                "Telegram", chatTitle, senderName, Int64(message.messageId)
            )
        }
    }

    private func downloadFile(fileId: String) async -> Data? {
        let urlString = "https://api.telegram.org/bot\(botToken)/getFile?file_id=\(fileId)"
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(TelegramFileResponse.self, from: data)
            guard let filePath = response.result?.filePath else { return nil }
            let downloadUrl = "https://api.telegram.org/file/bot\(botToken)/\(filePath)"
            guard let fileUrl = URL(string: downloadUrl) else { return nil }
            let (fileData, _) = try await URLSession.shared.data(from: fileUrl)
            return fileData
        } catch {
            return nil
        }
    }

    func testConnection() async -> (success: Bool, message: String, botName: String?) {
        let cleanedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedToken.isEmpty else { return (false, "Token 为空", nil) }

        let urlString = "https://api.telegram.org/bot\(cleanedToken)/getMe"
        guard let url = URL(string: urlString) else { return (false, "URL 格式错误", nil) }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "响应格式错误", nil)
            }
            if httpResponse.statusCode == 200 {
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
                return (false, "Token 无效 (404)", nil)
            } else if httpResponse.statusCode == 401 {
                return (false, "Token 未授权 (401)", nil)
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
                return (false, "错误 \(httpResponse.statusCode): \(errorMsg)", nil)
            }
        } catch {
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
        case from, chat, text, caption, photo, date
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
        case width, height
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
