//
//  WhisperContext.swift
//  ttsCopy
//
//  whisper.cpp C API 的 Swift 封装
//

import Foundation
import whisper

class WhisperContext {

    private var context: OpaquePointer?

    /// 从模型文件加载 Whisper 上下文
    static func createContext(path: String) -> WhisperContext? {
        var params = whisper_context_default_params()
        params.use_gpu = true  // Metal GPU 加速

        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            print("❌ [Whisper] 无法加载模型: \(path)")
            return nil
        }

        let instance = WhisperContext()
        instance.context = ctx
        print("✅ [Whisper] 模型加载成功")
        return instance
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    /// 识别 PCM Float32 音频，返回识别文本
    /// - Parameter samples: 16kHz mono Float32 音频数据
    func transcribe(samples: [Float]) -> String {
        guard let context = context else { return "" }

        let langCStr = strdup("zh")
        let promptCStr = strdup("以下是普通话的句子，包含标点符号。")
        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.language = UnsafePointer(langCStr)
        params.initial_prompt = UnsafePointer(promptCStr)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(samples.count))
        }

        free(langCStr)
        free(promptCStr)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard result == 0 else {
            print("❌ [Whisper] 识别失败, code=\(result)")
            return ""
        }

        let text = getTranscription()
        print("✅ [Whisper] 识别完成, 耗时=\(String(format: "%.1f", elapsed))s, text=\"\(text)\"")
        return text
    }

    /// 获取识别结果文本
    private func getTranscription() -> String {
        guard let context = context else { return "" }

        let segmentCount = whisper_full_n_segments(context)
        var text = ""

        for i in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(context, i) {
                text += String(cString: cStr)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
