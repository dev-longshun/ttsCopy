//
//  WhisperASRService.swift
//  ttsCopy
//
//  Whisper ASR 服务：模型下载、加载、识别
//  使用 whisper.cpp + Whisper Large V3 Turbo 量化模型
//

import Foundation

class WhisperASRService: NSObject, URLSessionDownloadDelegate {

    private var whisperContext: WhisperContext?
    private(set) var isReady = false
    private let processingQueue = DispatchQueue(label: "com.ttscopy.whisper-asr", qos: .userInitiated)

    // MARK: - 模型信息

    static let modelFileName = "ggml-large-v3-turbo-q5_0.bin"
    static let modelDisplayName = "Whisper Large V3 Turbo"
    static let modelPrecision = "q5_0"
    static let modelSizeMB = 574
    private static let downloadURL = "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(modelFileName)"

    // MARK: - 下载状态

    private var downloadSession: URLSession?
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

    static var modelPath: String {
        modelsDir + "/\(modelFileName)"
    }

    static var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelPath)
    }

    // MARK: - 模型下载

    func downloadModel() {
        downloadStartTime = Date()
        lastReportTime = Date()
        lastReportedBytes = 0
        lastSpeedStr = "计算中..."

        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let url = URL(string: Self.downloadURL)!
        print("📥 [Whisper] 开始下载: \(Self.modelFileName)")
        downloadSession?.downloadTask(with: url).resume()
    }

    func cancelDownload() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        try? FileManager.default.removeItem(atPath: Self.modelPath)
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
        do {
            if FileManager.default.fileExists(atPath: Self.modelPath) {
                try FileManager.default.removeItem(atPath: Self.modelPath)
            }
            try FileManager.default.moveItem(atPath: location.path, toPath: Self.modelPath)
            print("✅ [Whisper] 模型下载完成")
            DispatchQueue.main.async {
                self.onDownloadComplete?(true, nil)
            }
        } catch {
            DispatchQueue.main.async {
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

    func initialize() -> Bool {
        guard Self.isModelDownloaded else {
            print("❌ [Whisper] 模型文件不存在")
            return false
        }

        guard let ctx = WhisperContext.createContext(path: Self.modelPath) else {
            return false
        }

        whisperContext = ctx
        isReady = true
        print("✅ [Whisper] ASR 服务就绪")
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
        guard isReady else { return nil }
        return ModelInfo(
            name: Self.modelDisplayName,
            precision: Self.modelPrecision,
            sizeMB: Self.modelSizeMB
        )
    }

    // MARK: - 识别

    /// 接收 Int16 PCM 数据，转 Float32 后调用 Whisper 识别
    func transcribe(pcmData: Data, sampleRate: Int = 16000) -> String {
        guard let whisperContext = whisperContext, isReady else { return "" }

        return processingQueue.sync {
            let samples = pcmToFloat(pcmData)
            guard !samples.isEmpty else { return "" }

            let rawText = whisperContext.transcribe(samples: samples)
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
