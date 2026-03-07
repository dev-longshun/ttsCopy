//
//  MessageTypes.swift
//  ttsCopy
//
//  共享类型定义
//

import Foundation

// MARK: - Service Mode

enum ServiceMode: String, CaseIterable, Identifiable {
    case telegram = "Telegram"
    case lan = "LAN"

    var id: String { rawValue }
}

// MARK: - Connection Status

enum ConnectionStatus: String {
    case disconnected = "未连接"
    case connecting = "连接中..."
    case connected = "已连接"
    case error = "连接错误"
}

// MARK: - Clipboard Processing State

enum ClipboardProcessingState: Equatable {
    case idle
    case processing
    case completed
    case failed
}

// MARK: - Message Types

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
    let source: String
    let sourceDetail: String?
    let senderName: String
    let timestamp: Date

    var text: String { content.displayText }
}
