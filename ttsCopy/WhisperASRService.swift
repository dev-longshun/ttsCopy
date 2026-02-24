//
//  WhisperASRService.swift
//  ttsCopy
//
//  Whisper ASR 服务：多模型管理、下载、加载、识别
//  支持 Whisper Large V3 Turbo 和 Belle-whisper V3 Turbo
//

import Foundation

// MARK: - ASR 模型枚举

enum ASRModel: String, CaseIterable, Identifiable {
    case whisperTurbo = "whisper-turbo"
    case belleTurbo = "belle-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperTurbo: return "Whisper Large V3 Turbo"
        case .belleTurbo: return "Belle-whisper V3 Turbo (中文增强)"
        }
    }

    var shortName: String {
        switch self {
        case .whisperTurbo: return "Whisper Turbo"
        case .belleTurbo: return "Belle Turbo"
        }
    }

    var fileName: String {
        switch self {
        case .whisperTurbo: return "ggml-large-v3-turbo-q5_0.bin"
        case .belleTurbo: return "ggml-model.bin"
        }
    }

    var downloadURL: String {
        switch self {
        case .whisperTurbo:
            return "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
        case .belleTurbo:
            return "https://hf-mirror.com/BELLE-2/Belle-whisper-large-v3-turbo-zh-ggml/resolve/main/ggml-model.bin"
        }
    }

    var sizeMB: Int {
        switch self {
        case .whisperTurbo: return 574
        case .belleTurbo: return 1620
        }
    }

    var precision: String {
        switch self {
        case .whisperTurbo: return "q5_0"
        case .belleTurbo: return "f16"
        }
    }

    var description: String {
        switch self {
        case .whisperTurbo: return "OpenAI 原版，多语言通用"
        case .belleTurbo: return "中文专项微调，编程术语更准"
        }
    }
}

class WhisperASRService: NSObject, URLSessionDownloadDelegate {

    private var whisperContext: WhisperContext?
    private(set) var isReady = false
    private(set) var currentModel: ASRModel?
    private let processingQueue = DispatchQueue(label: "com.ttscopy.whisper-asr", qos: .userInitiated)

    // MARK: - 下载状态

    private var downloadSession: URLSession?
    private var downloadingModel: ASRModel?
    var onDownloadProgress: ((Double, String) -> Void)?
    var onDownloadComplete: ((Bool, String?) -> Void)?

    private var downloadStartTime: Date?
    private var lastReportedBytes: Int64 = 0
    private var lastReportTime: Date?
    private var lastSpeedStr: String = ""

    // MARK: - 模型目录

    static var modelsDir: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ttsCopy/models").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    static func modelPath(for model: ASRModel) -> String {
        modelsDir + "/\(model.fileName)"
    }

    static func isModelDownloaded(_ model: ASRModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model))
    }

    // MARK: - 模型下载

    func downloadModel(_ model: ASRModel) {
        downloadingModel = model
        downloadStartTime = Date()
        lastReportTime = Date()
        lastReportedBytes = 0
        lastSpeedStr = "计算中..."

        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let url = URL(string: model.downloadURL)!
        print("📥 [Whisper] 开始下载: \(model.displayName) (\(model.fileName))")
        downloadSession?.downloadTask(with: url).resume()
    }

    func cancelDownload() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        if let model = downloadingModel {
            let path = Self.modelPath(for: model)
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        downloadingModel = nil
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0

        let now = Date()
        let elapsed = now.timeIntervalSince(lastReportTime ?? now)
        if elapsed >= 0.5 {
            let bytesDelta = totalBytesWritten - lastReportedBytes
            let speed = Double(bytesDelta) / elapsed
            lastSpeedStr = formatSpeed(speed)
            lastReportedBytes = totalBytesWritten
            lastReportTime = now
        }

        let downloaded = formatBytes(totalBytesWritten)
        let total = formatBytes(totalBytesExpectedToWrite)
        let desc = "\(downloaded) / \(total)  \(lastSpeedStr)"

        DispatchQueue.main.async {
            self.onDownloadProgress?(progress, desc)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let model = downloadingModel else { return }
        let targetPath = Self.modelPath(for: model)
        do {
            if FileManager.default.fileExists(atPath: targetPath) {
                try FileManager.default.removeItem(atPath: targetPath)
            }
            try FileManager.default.moveItem(atPath: location.path, toPath: targetPath)
            print("✅ [Whisper] 模型下载完成: \(model.displayName)")
            DispatchQueue.main.async {
                self.downloadingModel = nil
                self.onDownloadComplete?(true, nil)
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadingModel = nil
                self.onDownloadComplete?(false, "文件保存失败: \(error.localizedDescription)")
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        if let error = error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                self.onDownloadComplete?(false, "下载失败: \(error.localizedDescription)")
            }
        }
    }
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 * 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.1f MB/s", bytesPerSec / 1024 / 1024)
        }
    }

    // MARK: - 初始化

    func initialize(model: ASRModel) -> Bool {
        guard Self.isModelDownloaded(model) else {
            print("❌ [Whisper] 模型文件不存在: \(model.displayName)")
            return false
        }

        let path = Self.modelPath(for: model)
        guard let ctx = WhisperContext.createContext(path: path) else {
            return false
        }

        whisperContext = ctx
        currentModel = model
        isReady = true
        print("✅ [Whisper] ASR 服务就绪: \(model.displayName)")
        return true
    }

    // MARK: - 模型信息

    struct ModelInfo {
        let name: String
        let precision: String
        let sizeMB: Int

        var summary: String {
            "\(name) · \(precision) · \(sizeMB) MB"
        }
    }

    var modelInfo: ModelInfo? {
        guard isReady, let model = currentModel else { return nil }
        return ModelInfo(
            name: model.displayName,
            precision: model.precision,
            sizeMB: model.sizeMB
        )
    }

    // MARK: - 识别

    /// 接收 Int16 PCM 数据，转 Float32 后调用 Whisper 识别
    func transcribe(pcmData: Data, sampleRate: Int = 16000) -> String {
        guard let whisperContext = whisperContext, let model = currentModel, isReady else { return "" }

        return processingQueue.sync {
            let samples = pcmToFloat(pcmData)
            guard !samples.isEmpty else { return "" }

            let rawText = whisperContext.transcribe(samples: samples, model: model)
            return processCodeText(rawText)
        }
    }

    /// 释放模型
    func release() {
        whisperContext = nil
        isReady = false
        print("🔄 [Whisper] 模型已释放")
    }

    // MARK: - Private

    private func pcmToFloat(_ data: Data) -> [Float] {
        let count = data.count / 2
        guard count > 0 else { return [] }

        var floats = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<count {
                floats[i] = Float(ptr[i]) / 32768.0
            }
        }
        return floats
    }

    /// 编程术语后处理
    private let codeDictionary: [(pattern: String, replacement: String)] = {
        let dict: [String: String] = [
            "函数": "function", "常量": "const", "变量": "let",
            "如果": "if", "否则如果": "else if", "否则": "else",
            "返回": "return", "等待": "await", "异步": "async",
            "导入": "import", "导出": "export", "类型": "type",
            "接口": "interface", "类": "class", "空": "null",
            "未定义": "undefined", "真": "true", "假": "false",
            "等于等于等于": "===", "等于等于": "==", "不等于": "!==",
            "箭头函数": "=>", "展开": "...",
            "优斯状态": "useState", "优斯一飞科特": "useEffect",
            "优斯麦莫": "useMemo", "优斯瑞夫": "useRef", "优斯回调": "useCallback",
            "瑞克特": "React", "泰普斯克瑞普特": "TypeScript",
            "伊克斯波": "Expo", "诺德": "Node",
            "克劳德": "Claude", "克劳德科德": "Claude Code",
            "吉特": "Git", "吉特哈布": "GitHub",
            "皮爱屁": "API", "杰森": "JSON",
        ]
        return dict.map { (pattern: $0.key, replacement: $0.value) }
            .sorted { $0.pattern.count > $1.pattern.count }
    }()

    private func processCodeText(_ text: String) -> String {
        var result = text
        for entry in codeDictionary {
            result = result.replacingOccurrences(
                of: entry.pattern, with: entry.replacement, options: [.caseInsensitive]
            )
        }
        return result
    }
}
