//
//  ASRService.swift
//  ttsCopy
//
//  Mac 端离线语音识别服务
//  使用 sherpa-onnx + SenseVoice 模型
//

import Foundation

class ASRService: NSObject, URLSessionDownloadDelegate {

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private(set) var isReady = false

    // MARK: - 模型下载

    static let modelName = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    static let mirrorURL = "https://hf-mirror.com/csukuangfj/\(modelName)/resolve/main"

    private var downloadSession: URLSession?
    private var currentDownloadFile: String = ""
    private var downloadedModelBytes: Int64 = 0  // model.int8.onnx 已下载的字节

    /// 下载回调
    var onDownloadProgress: ((Double, String) -> Void)?  // (进度0~1, 速度描述)
    var onDownloadComplete: ((Bool, String?) -> Void)?   // (成功, 错误信息)

    private var downloadStartTime: Date?
    private var lastReportedBytes: Int64 = 0
    private var lastReportTime: Date?
    private var lastSpeedStr: String = ""

    /// 模型目录
    static var modelsDir: String {
        // Application Support 目录，持久化存储
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ttsCopy/models").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 检查模型是否已下载
    static var isModelDownloaded: Bool {
        let dir = modelsDir + "/\(modelName)"
        return FileManager.default.fileExists(atPath: dir + "/model.int8.onnx")
            && FileManager.default.fileExists(atPath: dir + "/tokens.txt")
    }

    /// 编程术语后处理词典
    private let codeDictionary: [(pattern: String, replacement: String)] = {
        let dict: [String: String] = [
            // JavaScript / TypeScript
            "函数": "function",
            "常量": "const",
            "变量": "let",
            "如果": "if",
            "否则如果": "else if",
            "否则": "else",
            "返回": "return",
            "等待": "await",
            "异步": "async",
            "导入": "import",
            "导出": "export",
            "类型": "type",
            "接口": "interface",
            "类": "class",
            "空": "null",
            "未定义": "undefined",
            "真": "true",
            "假": "false",
            // 操作符
            "等于等于等于": "===",
            "等于等于": "==",
            "不等于": "!==",
            "箭头函数": "=>",
            "展开": "...",
            // React
            "优斯状态": "useState",
            "优斯一飞科特": "useEffect",
            "优斯麦莫": "useMemo",
            "优斯瑞夫": "useRef",
            "优斯回调": "useCallback",
            // 框架 / 工具
            "瑞克特": "React",
            "泰普斯克瑞普特": "TypeScript",
            "伊克斯波": "Expo",
            "诺德": "Node",
            "克劳德": "Claude",
            "克劳德科德": "Claude Code",
            "吉特": "Git",
            "吉特哈布": "GitHub",
            "皮爱屁": "API",
            "杰森": "JSON",
        ]
        // 按 key 长度降序排列，优先匹配长词
        return dict.map { (pattern: $0.key, replacement: $0.value) }
            .sorted { $0.pattern.count > $1.pattern.count }
    }()

    // MARK: - 初始化

    /// 初始化 ASR 模型
    /// - Parameter modelsDir: 模型文件所在目录
    /// - Returns: 是否初始化成功
    func initialize(modelsDir: String) -> Bool {
        let modelDir = modelsDir + "/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
        let modelPath = modelDir + "/model.int8.onnx"
        let tokensPath = modelDir + "/tokens.txt"

        // 检查模型文件是否存在
        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            print("❌ [ASR] 模型文件不存在: \(modelDir)")
            return false
        }

        let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(
            model: modelPath,
            language: "auto",
            useInverseTextNormalization: true
        )

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensPath,
            numThreads: 4,
            debug: 0,
            senseVoice: senseVoiceConfig
        )

        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80
        )

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )

        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        isReady = true
        print("✅ [ASR] SenseVoice 模型加载成功")
        return true
    }

    // MARK: - 识别

    /// 识别 PCM 音频数据
    /// - Parameters:
    ///   - pcmData: 16-bit signed little-endian PCM 数据
    ///   - sampleRate: 采样率（默认 16000）
    /// - Returns: 识别结果文本
    func transcribe(pcmData: Data, sampleRate: Int = 16000) -> String {
        guard let recognizer = recognizer, isReady else {
            print("❌ [ASR] 模型未初始化")
            return ""
        }

        // 将 Int16 PCM 转换为 Float32（归一化到 [-1, 1]）
        let samples = pcmToFloat(pcmData)

        if samples.isEmpty {
            print("⚠️ [ASR] 音频数据为空")
            return ""
        }

        let durationSec = Double(samples.count) / Double(sampleRate)
        print("🎤 [ASR] 开始识别, 音频时长=\(String(format: "%.2f", durationSec))s, samples=\(samples.count)")

        let startTime = Date()
        let result = recognizer.decode(samples: samples, sampleRate: sampleRate)
        let elapsed = Date().timeIntervalSince(startTime)

        let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ [ASR] 识别完成, 耗时=\(String(format: "%.0f", elapsed * 1000))ms, text=\"\(rawText)\"")

        // 编程术语后处理
        let processed = processCodeText(rawText)
        if processed != rawText {
            print("📝 [ASR] 后处理: \"\(rawText)\" → \"\(processed)\"")
        }

        return processed
    }

    // MARK: - 释放

    func release() {
        recognizer = nil
        isReady = false
        print("🔄 [ASR] 模型已释放")
    }

    // MARK: - 模型下载

    func downloadModel() {
        let targetDir = ASRService.modelsDir + "/\(ASRService.modelName)"
        try? FileManager.default.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

        downloadStartTime = Date()
        lastReportTime = Date()
        lastReportedBytes = 0
        downloadedModelBytes = 0

        // 先下载 tokens.txt（小文件），再下载 model.int8.onnx（大文件）
        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        currentDownloadFile = "tokens.txt"
        lastSpeedStr = "计算中..."
        let tokensURL = URL(string: "\(ASRService.mirrorURL)/tokens.txt")!
        downloadSession?.downloadTask(with: tokensURL).resume()
    }

    func cancelDownload() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        // 清理不完整的文件
        let targetDir = ASRService.modelsDir + "/\(ASRService.modelName)"
        try? FileManager.default.removeItem(atPath: targetDir + "/tokens.txt")
        try? FileManager.default.removeItem(atPath: targetDir + "/model.int8.onnx")
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // 只对大文件 (model.int8.onnx) 报告进度
        guard currentDownloadFile == "model.int8.onnx" else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        // 计算速度（每 0.5 秒更新一次，但始终显示上次的值）
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

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let targetDir = ASRService.modelsDir + "/\(ASRService.modelName)"
        let destPath = targetDir + "/\(currentDownloadFile)"

        do {
            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(atPath: destPath)
            }
            try FileManager.default.moveItem(atPath: location.path, toPath: destPath)
            print("✅ [ASR] 下载完成: \(currentDownloadFile)")
        } catch {
            DispatchQueue.main.async {
                self.onDownloadComplete?(false, "文件保存失败: \(error.localizedDescription)")
            }
            return
        }

        // tokens.txt 下载完后，继续下载 model.int8.onnx
        if currentDownloadFile == "tokens.txt" {
            currentDownloadFile = "model.int8.onnx"
            let modelURL = URL(string: "\(ASRService.mirrorURL)/model.int8.onnx")!
            downloadStartTime = Date()
            lastReportTime = Date()
            lastReportedBytes = 0
            downloadSession?.downloadTask(with: modelURL).resume()
        } else {
            // 全部下载完成
            DispatchQueue.main.async {
                self.onDownloadComplete?(true, nil)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            let nsError = error as NSError
            // 用户取消不算错误
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

    // MARK: - Private

    /// Int16 PCM → Float32 归一化
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
    private func processCodeText(_ text: String) -> String {
        var result = text
        for entry in codeDictionary {
            result = result.replacingOccurrences(
                of: entry.pattern,
                with: entry.replacement,
                options: [.caseInsensitive]
            )
        }
        return result
    }
}
