#!/bin/bash
set -euo pipefail

# CodeQL自动下载器
# 检查CodeQL目录是否为空，如果为空则自动下载CodeQL CLI

CODEQL_DIR="/app/codeql"
DOWNLOAD_URL="https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip"
FILE_NAME="codeql-linux64.zip"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查CodeQL是否已安装
check_codeql_installation() {
    if [ ! -d "$CODEQL_DIR" ]; then
        log "CodeQL目录不存在: $CODEQL_DIR"
        return 1
    fi
    
    # 检查目录是否为空
    if [ -z "$(ls -A "$CODEQL_DIR" 2>/dev/null)" ]; then
        log "CodeQL目录为空: $CODEQL_DIR"
        return 1
    fi
    
    # 检查是否存在CodeQL可执行文件
    if [ -f "$CODEQL_DIR/codeql" ] && [ -x "$CODEQL_DIR/codeql" ]; then
        log "CodeQL已安装并可执行"
        return 0
    fi
    
    log "CodeQL目录存在但缺少可执行文件"
    return 1
}

# 下载CodeQL
download_codeql() {
    log "开始下载CodeQL..."
    log "下载地址: $DOWNLOAD_URL"
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE="$TEMP_DIR/$FILE_NAME"
    
    # 下载文件
    log "正在下载到临时文件: $TEMP_FILE"
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O "$TEMP_FILE"; then
        log "错误: 下载失败"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # 验证下载的文件
    if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
        log "错误: 下载的文件无效或为空"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    log "下载完成，文件大小: $(du -h "$TEMP_FILE" | cut -f1)"
    
    # 确保CodeQL目录存在
    mkdir -p "$CODEQL_DIR"
    
    # 解压文件
    log "正在解压到: $CODEQL_DIR"
    if ! unzip -q "$TEMP_FILE" -d "$CODEQL_DIR"; then
        log "错误: 解压失败"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # 移动文件到正确位置（如果解压后在子目录中）
    if [ -d "$CODEQL_DIR/codeql" ]; then
        log "移动CodeQL文件到根目录"
        mv "$CODEQL_DIR/codeql"/* "$CODEQL_DIR/"
        rmdir "$CODEQL_DIR/codeql"
    fi
    
    # 设置执行权限
    if [ -f "$CODEQL_DIR/codeql" ]; then
        chmod +x "$CODEQL_DIR/codeql"
        log "设置CodeQL可执行权限"
    fi
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    log "CodeQL下载和安装完成"
    return 0
}

# 验证CodeQL安装
verify_codeql_installation() {
    if [ ! -f "$CODEQL_DIR/codeql" ]; then
        log "错误: CodeQL可执行文件不存在"
        return 1
    fi
    
    if [ ! -x "$CODEQL_DIR/codeql" ]; then
        log "错误: CodeQL文件不可执行"
        return 1
    fi
    
    # 尝试运行CodeQL版本命令
    log "验证CodeQL安装..."
    if "$CODEQL_DIR/codeql" version >/dev/null 2>&1; then
        CODEQL_VERSION=$("$CODEQL_DIR/codeql" version | head -n1)
        log "CodeQL安装验证成功: $CODEQL_VERSION"
        return 0
    else
        log "错误: CodeQL安装验证失败"
        return 1
    fi
}

# 主函数
main() {
    log "=== CodeQL自动下载器启动 ==="
    
    # 检查当前安装状态
    if check_codeql_installation; then
        log "CodeQL已正确安装，无需下载"
        return 0
    fi
    
    log "CodeQL未安装或安装不完整，开始自动下载..."
    
    # 下载CodeQL
    if ! download_codeql; then
        log "错误: CodeQL下载失败"
        return 1
    fi
    
    # 验证安装
    if ! verify_codeql_installation; then
        log "错误: CodeQL安装验证失败"
        return 1
    fi
    
    log "=== CodeQL自动下载完成 ==="
    return 0
}

# 如果脚本被直接执行，运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi