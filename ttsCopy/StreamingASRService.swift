//
//  StreamingASRService.swift
//  ttsCopy
//
//  Mac 端流式语音识别服务
//  使用 sherpa-onnx + Zipformer streaming 模型
//

import Foundation

class StreamingASRService: NSObject, URLSessionDownloadDelegate {

    private var recognizer: SherpaOnnxRecognizer?
    private(set) var isReady = false
    private let processingQueue = DispatchQueue(label: "com.ttscopy.streaming-asr", qos: .userInitiated)

    /// 上一次发送的 partial 文本，避免重复发送
    private var lastPartialText: String = ""

    // MARK: - 模型信息

    static let modelName = "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
    static let mirrorURL = "https://hf-mirror.com/csukuangfj/\(modelName)/resolve/main"

    /// 需要下载的文件列表（按顺序）
    private static let modelFiles = [
        "tokens.txt",
        "encoder-epoch-99-avg-1.int8.onnx",
        "decoder-epoch-99-avg-1.int8.onnx",
        "joiner-epoch-99-avg-1.int8.onnx"
    ]

    // MARK: - 下载状态

    private var downloadSession: URLSession?
    private var currentFileIndex = 0
    private var currentDownloadFile: String = ""

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

    static var isModelDownloaded: Bool {
        let dir = modelsDir + "/\(modelName)"
        return modelFiles.allSatisfy {
            FileManager.default.fileExists(atPath: dir + "/\($0)")
        }
    }

    // MARK: - 模型下载

    func downloadModel() {
        let targetDir = Self.modelsDir + "/\(Self.modelName)"
        try? FileManager.default.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        downloadStartTime = Date()
        lastReportTime = Date()
        lastReportedBytes = 0
        currentFileIndex = 0

        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        startNextFileDownload()
    }

    func cancelDownload() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        // 清理不完整的文件
        let targetDir = Self.modelsDir + "/\(Self.modelName)"
        for file in Self.modelFiles {
            try? FileManager.default.removeItem(atPath: targetDir + "/\(file)")
        }
    }

    private func startNextFileDownload() {
        guard currentFileIndex < Self.modelFiles.count else {
            // 全部下载完成
            DispatchQueue.main.async {
                self.onDownloadComplete?(true, nil)
            }
            return
        }

        currentDownloadFile = Self.modelFiles[currentFileIndex]
        lastSpeedStr = "计算中..."
        downloadStartTime = Date()
        lastReportTime = Date()
        lastReportedBytes = 0

        let url = URL(string: "\(Self.mirrorURL)/\(currentDownloadFile)")!
        print("📥 [StreamingASR] 开始下载: \(currentDownloadFile)")
        downloadSession?.downloadTask(with: url).resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // 只对 .onnx 文件报告进度
        guard currentDownloadFile.hasSuffix(".onnx") else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

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
        let fileLabel = "(\(currentFileIndex + 1)/\(Self.modelFiles.count))"
        let desc = "\(fileLabel) \(downloaded) / \(total)  \(lastSpeedStr)"

        DispatchQueue.main.async {
            self.onDownloadProgress?(progress, desc)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let targetDir = Self.modelsDir + "/\(Self.modelName)"
        let destPath = targetDir + "/\(currentDownloadFile)"

        do {
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(atPath: destPath)
            }
            try FileManager.default.moveItem(atPath: location.path, toPath: destPath)
            print("✅ [StreamingASR] 下载完成: \(currentDownloadFile)")
        } catch {
            DispatchQueue.main.async {
                self.onDownloadComplete?(false, "文件保存失败: \(error.localizedDescription)")
            }
            return
        }

        // 继续下载下一个文件
        currentFileIndex += 1
        startNextFileDownload()
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

    func initialize(modelsDir: String) -> Bool {
        let modelDir = modelsDir + "/\(Self.modelName)"
        let encoderPath = modelDir + "/encoder-epoch-99-avg-1.int8.onnx"
        let decoderPath = modelDir + "/decoder-epoch-99-avg-1.int8.onnx"
        let joinerPath = modelDir + "/joiner-epoch-99-avg-1.int8.onnx"
        let tokensPath = modelDir + "/tokens.txt"

        guard [encoderPath, decoderPath, joinerPath, tokensPath].allSatisfy({
            FileManager.default.fileExists(atPath: $0)
        }) else {
            print("❌ [StreamingASR] 模型文件不存在: \(modelDir)")
            return false
        }

        let transducerConfig = sherpaOnnxOnlineTransducerModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            joiner: joinerPath
        )

        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokensPath,
            transducer: transducerConfig,
            numThreads: 2,
            debug: 0
        )

        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)

        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            enableEndpoint: true,
            rule1MinTrailingSilence: 2.4,
            rule2MinTrailingSilence: 1.2,
            rule3MinUtteranceLength: 30,
            decodingMethod: "greedy_search"
        )

        recognizer = SherpaOnnxRecognizer(config: &config)
        isReady = true
        print("✅ [StreamingASR] Zipformer 流式模型加载成功")
        return true
    }

    // MARK: - 流式会话

    /// 开始新的流式识别会话
    func startSession() {
        processingQueue.sync {
            recognizer?.reset()
            lastPartialText = ""
        }
        print("🎙️ [StreamingASR] 会话开始")
    }

    /// 喂入音频数据，返回变化的 partial 文本（nil 表示无变化）
    func feedSamples(pcmData: Data, sampleRate: Int = 16000) -> String? {
        guard let recognizer = recognizer, isReady else { return nil }

        return processingQueue.sync {
            let samples = pcmToFloat(pcmData)
            guard !samples.isEmpty else { return nil }

            recognizer.acceptWaveform(samples: samples, sampleRate: sampleRate)

            while recognizer.isReady() {
                recognizer.decode()
            }

            let result = recognizer.getResult()
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text != lastPartialText && !text.isEmpty {
                lastPartialText = text
                return text
            }
            return nil
        }
    }

    /// 结束流式会话，返回最终文本
    func endSession() -> String {
        return processingQueue.sync {
            recognizer?.inputFinished()

            // 最终 decode
            while recognizer?.isReady() == true {
                recognizer?.decode()
            }

            let result = recognizer?.getResult()
            let text = (result?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let processed = processCodeText(text)

            lastPartialText = ""
            print("✅ [StreamingASR] 会话结束, text=\"\(processed)\"")
            return processed
        }
    }

    /// 释放模型
    func release() {
        recognizer = nil
        isReady = false
        print("🔄 [StreamingASR] 模型已释放")
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
