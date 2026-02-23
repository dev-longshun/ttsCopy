#!/bin/bash
# 下载 SenseVoice ASR 模型（sherpa-onnx 格式）
# 模型：SenseVoice-Small (阿里 FunAudioLLM)
# 支持语言：中文、英文、日文、韩文、粤语

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODEL_DIR="$PROJECT_DIR/models"
MODEL_NAME="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
TARGET_DIR="$MODEL_DIR/$MODEL_NAME"

# HuggingFace 镜像源（国内快）和原始源
HF_MIRROR="https://hf-mirror.com/csukuangfj/$MODEL_NAME/resolve/main"
HF_ORIGIN="https://huggingface.co/csukuangfj/$MODEL_NAME/resolve/main"

# 优先用镜像，可通过环境变量 USE_ORIGIN=1 切换到原始源
if [ "${USE_ORIGIN:-0}" = "1" ]; then
    BASE_URL="$HF_ORIGIN"
    echo "📡 使用 HuggingFace 原始源"
else
    BASE_URL="$HF_MIRROR"
    echo "📡 使用 HuggingFace 镜像源 (hf-mirror.com)"
fi

# 检查是否已下载
if [ -f "$TARGET_DIR/model.int8.onnx" ] && [ -f "$TARGET_DIR/tokens.txt" ]; then
    echo "✅ 模型已存在: $TARGET_DIR"
    ls -lh "$TARGET_DIR/model.int8.onnx" "$TARGET_DIR/tokens.txt"
    exit 0
fi

mkdir -p "$TARGET_DIR"

# 下载函数：显示进度条、百分比、速度
download_file() {
    local url="$1"
    local output="$2"
    local desc="$3"
    echo ""
    echo "⬇️  下载 $desc"
    echo "   $url"
    curl -L --progress-bar -o "$output" "$url"
    echo "   ✅ 完成: $(ls -lh "$output" | awk '{print $5}')"
}

# 下载模型文件（239MB）
download_file "$BASE_URL/model.int8.onnx" "$TARGET_DIR/model.int8.onnx" "model.int8.onnx (~239MB)"

# 下载词表文件（316KB）
download_file "$BASE_URL/tokens.txt" "$TARGET_DIR/tokens.txt" "tokens.txt (~316KB)"

echo ""
echo "✅ SenseVoice 模型下载完成"
ls -lh "$TARGET_DIR/"
