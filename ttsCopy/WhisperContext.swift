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
    /// - Parameters:
    ///   - samples: 16kHz mono Float32 音频数据
    ///   - model: 当前使用的 ASR 模型，用于选择合适的 prompt
    func transcribe(samples: [Float], model: ASRModel) -> String {
        guard let context = context else { return "" }

        let langCStr = strdup("zh")
        // 编程专用 prompt：列出的词汇会显著提高 Whisper 对这些术语的识别率
        let prompt: String
        switch model {
        case .whisperTurbo:
            prompt = """
            以下是程序员的语音指令，包含中英文混合的编程术语和标点符号。\
            React、Vue、Svelte、Angular、Next.js、Nuxt、TypeScript、JavaScript、Python、Rust、Go、Swift、Java、Kotlin、\
            Node.js、Deno、Bun、Docker、Kubernetes、Nginx、Redis、PostgreSQL、MongoDB、SQLite、\
            GitHub、GitLab、npm、Vercel、Netlify、Cloudflare、AWS、Supabase、\
            API、JSON、CSS、HTML、SDK、CLI、URL、HTTP、WebSocket。
            """
        case .belleTurbo:
            prompt = """
            以下是程序员在编写代码时的语音指令，包含中英文混合的编程术语和标点符号。\
            React、Vue、Svelte、Angular、Next.js、Nuxt、Vite、Webpack、Tailwind CSS、\
            TypeScript、JavaScript、Python、Rust、Go、Swift、Java、Kotlin、C++、\
            Node.js、Deno、Bun、Express、FastAPI、Django、Spring Boot、\
            Docker、Kubernetes、Nginx、Redis、PostgreSQL、MongoDB、MySQL、SQLite、\
            GitHub、GitLab、npm、PyPI、Homebrew、Vercel、Netlify、Cloudflare、AWS、Supabase、\
            Claude、Cursor、Copilot、ChatGPT、OpenAI、LLM、RAG、\
            useState、useEffect、useMemo、useRef、useCallback、className、onClick、onChange、\
            async、await、const、let、var、interface、component、props、state、\
            function、return、import、export、default、Promise、\
            API、JSON、CSS、HTML、SDK、CLI、URL、HTTP、HTTPS、WebSocket、REST、GraphQL、\
            git commit、git push、pull request、code review、merge、rebase、deploy、debug、refactor、\
            middleware、webhook、endpoint、callback、payload、token、schema、migration。
            """
        }
        let promptCStr = strdup(prompt)
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
