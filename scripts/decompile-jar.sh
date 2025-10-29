#!/bin/bash

# JAR反编译脚本
# 支持Procyon和Fernflower反编译器

set -e

# 参数检查
if [ $# -ne 3 ]; then
    echo "用法: $0 <jar_file> <output_dir> <decompiler>"
    echo "反编译器选项: procyon, fernflower"
    exit 1
fi

JAR_FILE="$1"
OUTPUT_DIR="$2"
DECOMPILER="$3"

# 检查JAR文件是否存在
if [ ! -f "$JAR_FILE" ]; then
    echo "错误: JAR文件不存在: $JAR_FILE"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 反编译器路径
PROCYON_JAR="/app/tools/procyon-decompiler.jar"
FERNFLOWER_JAR="/app/tools/fernflower.jar"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始反编译JAR文件: $(basename "$JAR_FILE")"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 使用反编译器: $DECOMPILER"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 输出目录: $OUTPUT_DIR"

case "$DECOMPILER" in
    "procyon")
        if [ ! -f "$PROCYON_JAR" ]; then
            echo "错误: Procyon反编译器不存在: $PROCYON_JAR"
            exit 1
        fi
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 使用Procyon反编译器..."
        java -jar "$PROCYON_JAR" \
            -jar "$JAR_FILE" \
            -o "$OUTPUT_DIR" \
            --unicode-output-enabled \
            --include-line-numbers-in-bytecode \
            2>&1 | while IFS= read -r line; do
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
            done
        ;;
        
    "fernflower")
        if [ ! -f "$FERNFLOWER_JAR" ] || [ "$(cat "$FERNFLOWER_JAR" 2>/dev/null)" = "Fernflower not available" ]; then
            echo "警告: Fernflower反编译器不可用，回退到Procyon"
            # 回退到Procyon
            if [ ! -f "$PROCYON_JAR" ]; then
                echo "错误: Procyon反编译器也不存在: $PROCYON_JAR"
                exit 1
            fi
            
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 使用Procyon反编译器（Fernflower不可用）..."
            java -jar "$PROCYON_JAR" \
                -jar "$JAR_FILE" \
                -o "$OUTPUT_DIR" \
                --unicode-output-enabled \
                --include-line-numbers-in-bytecode \
                2>&1 | while IFS= read -r line; do
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
                done
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 使用Fernflower反编译器..."
            java -jar "$FERNFLOWER_JAR" \
                -dgs=1 \
                -hdc=0 \
                -asc=1 \
                -udv=1 \
                "$JAR_FILE" \
                "$OUTPUT_DIR" \
                2>&1 | while IFS= read -r line; do
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
                done
        fi
        ;;
        
    *)
        echo "错误: 不支持的反编译器: $DECOMPILER"
        echo "支持的反编译器: procyon, fernflower"
        exit 1
        ;;
esac

# 检查反编译结果
if [ $? -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 反编译完成"
    
    # 统计反编译的文件数量
    JAVA_FILES=$(find "$OUTPUT_DIR" -name "*.java" | wc -l)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 反编译生成 $JAVA_FILES 个Java文件"
    
    # 创建源码结构信息
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 生成源码结构信息..."
    find "$OUTPUT_DIR" -name "*.java" > "$OUTPUT_DIR/.source_files.txt"
    
    # 如果是Fernflower，可能需要额外处理
    if [ "$DECOMPILER" = "fernflower" ]; then
        # Fernflower可能会创建额外的目录结构，需要整理
        if [ -d "$OUTPUT_DIR/$(basename "$JAR_FILE" .jar)" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 整理Fernflower输出结构..."
            mv "$OUTPUT_DIR/$(basename "$JAR_FILE" .jar)"/* "$OUTPUT_DIR/" 2>/dev/null || true
            rmdir "$OUTPUT_DIR/$(basename "$JAR_FILE" .jar)" 2>/dev/null || true
        fi
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] JAR反编译成功完成"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 反编译失败"
    exit 1
fi