//
//  LANService.swift
//  ttsCopy
//
//  局域网 WebSocket 服务器 + Bonjour 广播
//

import Foundation
import Network

class LANService {

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var messageIdCounter: Int64 = 0
    private var pendingImageMeta: [String: (caption: String?, sender: String)] = [:]

    // Callbacks
    var onStatusChange: ((ConnectionStatus) -> Void)?
    var onError: ((String?) -> Void)?
    var onMessage: ((MessageContent, String, String?, String, Int64) async -> Void)?
    var onDevicesChanged: (([String]) -> Void)?
    var onPortAssigned: ((UInt16) -> Void)?

    func start() throws {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        listener = try NWListener(using: parameters)
        listener?.service = NWListener.Service(name: "ttsCopy", type: "_ttscopy._tcp")

        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        pendingImageMeta.removeAll()
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                onPortAssigned?(port)
            }
            onStatusChange?(.connected)
            onError?(nil)
        case .failed(let error):
            onStatusChange?(.error)
            onError?("服务器错误: \(error.localizedDescription)")
        case .cancelled:
            onStatusChange?(.disconnected)
        default:
            break
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("📱 设备已连接: \(connection.endpoint)")
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: .main)
        receiveMessage(on: connection)
        notifyDevicesChanged()
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connection.cancel()
        let key = connection.endpoint.debugDescription
        pendingImageMeta.removeValue(forKey: key)
        notifyDevicesChanged()
    }

    private func notifyDevicesChanged() {
        let devices = connections.compactMap { conn -> String? in
            guard conn.state == .ready else { return nil }
            return conn.endpoint.debugDescription
        }
        onDevicesChanged?(devices)
    }

    // MARK: - Receive Messages

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ 接收消息错误: \(error)")
                self.removeConnection(connection)
                return
            }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .text:
                    self.handleTextFrame(content, from: connection)
                case .binary:
                    self.handleBinaryFrame(content, from: connection)
                default:
                    break
                }
            }

            // Continue receiving
            self.receiveMessage(on: connection)
        }
    }

    private func handleTextFrame(_ data: Data?, from connection: NWConnection) {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        let sender = json["sender"] as? String ?? "Unknown"

        switch type {
        case "text":
            guard let content = json["content"] as? String else { return }
            messageIdCounter += 1
            let id = messageIdCounter
            Task {
                await self.onMessage?(.text(content), "LAN", sender, sender, id)
            }
            sendStatus(to: connection, copied: true)

        case "image":
            let key = connection.endpoint.debugDescription
            pendingImageMeta[key] = (caption: json["caption"] as? String, sender: sender)

        default:
            break
        }
    }

    private func handleBinaryFrame(_ data: Data?, from connection: NWConnection) {
        guard let data = data else { return }
        let key = connection.endpoint.debugDescription
        let meta = pendingImageMeta.removeValue(forKey: key)

        messageIdCounter += 1
        let id = messageIdCounter
        Task {
            await self.onMessage?(
                .photo(data, caption: meta?.caption),
                "LAN", meta?.sender ?? "Unknown", meta?.sender ?? "Unknown", id
            )
        }
        sendStatus(to: connection, copied: true)
    }

    // MARK: - Send Response

    private func sendStatus(to connection: NWConnection, copied: Bool) {
        let response: [String: Any] = ["type": "status", "copied": copied]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "status", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .idempotent)
    }

    // MARK: - Local IP

    static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        // 优先查找 en 开头的接口（WiFi / 以太网），跳过回环和虚拟接口
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    // 跳过 198.18.x.x 等非局域网地址
                    if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                        return ip
                    }
                }
            }
        }
        return nil
    }
}
