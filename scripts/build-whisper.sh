#!/bin/bash
#
# 编译 whisper.cpp 静态库（macOS arm64 + Metal GPU 加速）
# 编译产物输出到项目根目录 whisper/ 下
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="/tmp/whisper-cpp-build"
OUTPUT_DIR="$PROJECT_DIR/whisper"

echo "🔨 编译 whisper.cpp 静态库..."

# 检查 cmake
if ! command -v cmake &> /dev/null; then
    echo "❌ 需要安装 cmake: brew install cmake"
    exit 1
fi

# 克隆 whisper.cpp
if [ -d "$TMP_DIR" ]; then
    echo "♻️  清理旧的构建目录..."
    rm -rf "$TMP_DIR"
fi

echo "📥 克隆 whisper.cpp..."
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$TMP_DIR"

# 编译
echo "⚙️  配置 cmake..."
cd "$TMP_DIR"
cmake -B build \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DWHISPER_METAL=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON

echo "🔨 编译中..."
cmake --build build --config Release -j$(sysctl -n hw.ncpu)

# 输出到项目目录
echo "📦 复制编译产物..."
mkdir -p "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"

# 合并所有静态库
libtool -static -o "$OUTPUT_DIR/lib/libwhisper.a" \
    build/src/libwhisper.a \
    build/ggml/src/libggml.a \
    build/ggml/src/libggml-base.a \
    build/ggml/src/libggml-cpu.a \
    build/ggml/src/ggml-metal/libggml-metal.a \
    build/ggml/src/ggml-blas/libggml-blas.a 2>/dev/null || \
libtool -static -o "$OUTPUT_DIR/lib/libwhisper.a" \
    build/src/libwhisper.a \
    build/ggml/src/libggml.a \
    build/ggml/src/libggml-base.a \
    build/ggml/src/libggml-cpu.a \
    build/ggml/src/ggml-metal/libggml-metal.a

# 复制头文件
cp include/whisper.h "$OUTPUT_DIR/include/"
cp ggml/include/ggml*.h "$OUTPUT_DIR/include/" 2>/dev/null || true

# 创建 module map
cat > "$OUTPUT_DIR/include/module.modulemap" << 'EOF'
module whisper {
    header "whisper.h"
    export *
}
EOF

# 清理
echo "🧹 清理临时文件..."
rm -rf "$TMP_DIR"

LIB_SIZE=$(du -h "$OUTPUT_DIR/lib/libwhisper.a" | cut -f1)
echo ""
echo "✅ 编译完成！"
echo "   静态库: whisper/lib/libwhisper.a ($LIB_SIZE)"
echo "   头文件: whisper/include/"
echo ""
echo "   现在可以用 Xcode 打开项目编译了。"
