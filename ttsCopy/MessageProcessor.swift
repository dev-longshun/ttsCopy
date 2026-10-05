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
    var enablePromptOptimization: Bool = false
    var autoSaveImages: Bool = false
    var imageSavePath: String = ""
    var openAIAPIKey: String = ""
    var openAIBaseURL: String = "https://api.openai.com/v1"
    var openAIModel: String = "gpt-4.1-mini"

    var translationSession: TranslationSession?

    var onMessageProcessed: ((MessageItem) -> Void)?
    var onClipboardStateChange: ((ClipboardProcessingState) -> Void)?

    private var latestClipboardMessageId: Int64?

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
        latestClipboardMessageId = messageId

        switch content {
        case .text(let text):
            let item = MessageItem(
                id: messageId, content: .text(text),
                source: source, sourceDetail: sourceDetail,
                senderName: senderName, timestamp: Date()
            )
            onMessageProcessed?(item)

            copyToClipboard(text)
            let requiresAsyncUpdate = shouldProcessTextAsync(text)
            if requiresAsyncUpdate {
                onClipboardStateChange?(.processing)
                let finalText = await processTextForClipboard(text)
                guard latestClipboardMessageId == messageId else { return }
                if finalText != text {
                    copyToClipboard(finalText)
                }
                onClipboardStateChange?(.completed)
            } else {
                onClipboardStateChange?(.completed)
            }

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

            let requiresAsyncUpdate = shouldProcessCaptionAsync(caption)
            if requiresAsyncUpdate {
                onClipboardStateChange?(.processing)
                let processedCaption = await processCaptionForClipboard(caption)
                guard latestClipboardMessageId == messageId else { return }
                if processedCaption != caption {
                    copyImageToClipboard(data, caption: processedCaption)
                    if autoSaveImages {
                        saveImageToFile(data, caption: processedCaption)
                    }
                }
                onClipboardStateChange?(.completed)
            } else {
                onClipboardStateChange?(.completed)
            }

            if showNotification {
                sendNotification(title: sourceDetail ?? source, body: caption ?? "[图片]")
            }
        }
    }

    func translateText(_ text: String) async -> String {
        guard let session = translationSession else { return text }
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            print("⚠️ 翻译失败: \(error.localizedDescription)")
            return text
        }
    }

    func optimizePrompt(_ text: String) async -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enablePromptOptimization, !trimmedText.isEmpty else { return text }

        let apiKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            print("⚠️ 提示词优化已开启，但未配置 OpenAI API Key")
            return text
        }

        do {
            return try await requestPromptOptimization(text: trimmedText, apiKey: apiKey)
        } catch {
            print("⚠️ 提示词优化失败: \(error.localizedDescription)")
            return text
        }
    }

    func fetchAvailableModels() async throws -> [String] {
        let apiKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }
        guard let endpoint = openAIModelsURL() else {
            throw OpenAIServiceError.invalidBaseURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    func testPromptOptimization(_ text: String) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw OpenAIServiceError.emptyInput
        }

        let apiKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        return try await requestPromptOptimization(text: trimmedText, apiKey: apiKey)
    }

    private func processTextForClipboard(_ text: String) async -> String {
        var result = text
        if enablePromptOptimization {
            result = await optimizePrompt(result)
        }
        if enableTranslation {
            result = await translateText(result)
        }
        return result
    }

    private func shouldProcessTextAsync(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }
        return enablePromptOptimization || enableTranslation
    }

    private func shouldProcessCaptionAsync(_ caption: String?) -> Bool {
        guard let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return enablePromptOptimization || enableTranslation
    }

    private func processCaptionForClipboard(_ caption: String?) async -> String? {
        guard let caption, !caption.isEmpty else { return caption }
        return await processTextForClipboard(caption)
    }

    private func requestPromptOptimization(text: String, apiKey: String) async throws -> String {
        let requestBody = OpenAIChatRequest(
            model: normalizedOpenAIModel,
            messages: [
                .init(role: "system", content: promptOptimizerSystemPrompt),
                .init(role: "user", content: text)
            ],
            temperature: 0.3
        )

        guard let endpoint = openAIChatCompletionsURL() else {
            throw OpenAIServiceError.invalidBaseURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIServiceError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw OpenAIServiceError.emptyResponse
        }
        return content
    }

    private var normalizedOpenAIModel: String {
        let trimmed = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "gpt-4.1-mini" : trimmed
    }

    private func openAIChatCompletionsURL() -> URL? {
        openAIEndpointURL(path: "chat/completions")
    }

    private func openAIModelsURL() -> URL? {
        openAIEndpointURL(path: "models")
    }

    private func openAIEndpointURL(path endpointPath: String) -> URL? {
        let trimmed = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let baseString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: baseString) else { return nil }

        let currentPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch currentPath {
        case "":
            components.path = "/v1/\(endpointPath)"
        case "v1":
            components.path = "/v1/\(endpointPath)"
        case endpointPath, "v1/\(endpointPath)":
            components.path = "/\(currentPath)"
        default:
            if currentPath.hasSuffix("/\(endpointPath)") {
                components.path = "/\(currentPath)"
            } else if currentPath.hasSuffix("/v1") {
                components.path = "/\(currentPath)/\(endpointPath)"
            } else {
                components.path = "/\(currentPath)/\(endpointPath)"
            }
        }

        return components.url
    }

    private var promptOptimizerSystemPrompt: String {
        loadPromptOptimizerSystemPrompt()
    }

    private func loadPromptOptimizerSystemPrompt() -> String {
        let bundleURL = Bundle.main.url(forResource: "PromptOptimizerSystemPrompt", withExtension: "md")
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("PromptOptimizerSystemPrompt.md")

        for candidate in [bundleURL, sourceURL] {
            guard let candidate else { continue }
            if let content = try? String(contentsOf: candidate, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                return content
            }
        }

        return fallbackPromptOptimizerSystemPrompt
    }

    private var fallbackPromptOptimizerSystemPrompt: String {
        """
        You are an expert prompt optimizer based on a prompt-optimization workflow.
        Your task is to rewrite the user's input into a clearer, more specific, better-structured prompt for an AI model.

        Requirements:
        - Preserve the user's core intent and important constraints.
        - Improve clarity, structure, context, specificity, and output requirements.
        - Keep the optimized prompt in the same language as the user's input unless the input explicitly asks for another language.
        - If the original prompt is already strong, lightly polish it instead of over-expanding it.
        - Do not answer the user's prompt.
        - Do not explain your changes.
        - Return only the final optimized prompt text.
        - Do not use markdown code fences.
        - Encourage the downstream model to state uncertainty instead of hallucinating when appropriate.
        """
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

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
}

private struct OpenAIChatMessage: Encodable, Decodable {
    let role: String
    let content: String?
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIChatMessage
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Decodable {
    let message: String
}

private struct OpenAIModelListResponse: Decodable {
    let data: [OpenAIModelItem]
}

private struct OpenAIModelItem: Decodable {
    let id: String
}

private enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case emptyInput
    case emptyResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先填写 OpenAI API Key"
        case .invalidBaseURL:
            return "OpenAI Base URL 无效"
        case .invalidResponse:
            return "OpenAI 返回了无效响应"
        case .emptyInput:
            return "请先输入要测试的提示词"
        case .emptyResponse:
            return "OpenAI 未返回优化结果"
        case .apiError(let message):
            return message
        }
    }
}
