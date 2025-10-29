#!/bin/bash
set -euo pipefail

# CodeQL Database Builder - Boot JDK 管理器
# 支持检测、选择和管理多个Boot JDK版本

BOOTJDK_DIR="/app/bootjdk"
METADATA_FILE="/app/bootjdk/.jdk_metadata.json"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检测JDK版本
detect_jdk_version() {
    local jdk_path="$1"
    
    if [ ! -f "$jdk_path/bin/java" ]; then
        echo "unknown"
        return 1
    fi
    
    local version_output
    version_output=$("$jdk_path/bin/java" -version 2>&1 | head -n1)
    
    # 提取版本号
    if echo "$version_output" | grep -q '"1\.'; then
        # Java 8 style: java version "1.8.0_71"
        echo "$version_output" | sed -E 's/.*"1\.([0-9]+)\..*/\1/'
    else
        # Java 11+ style: openjdk version "11.0.23"
        echo "$version_output" | sed -E 's/.*"([0-9]+)\..*/\1/'
    fi
}

# 获取JDK详细信息
get_jdk_info() {
    local jdk_path="$1"
    
    if [ ! -f "$jdk_path/bin/java" ]; then
        return 1
    fi
    
    local version_output vendor_info
    version_output=$("$jdk_path/bin/java" -version 2>&1)
    
    local version=$(echo "$version_output" | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
    local vendor=$(echo "$version_output" | grep -i "openjdk\|oracle\|adoptium\|temurin" | head -n1 | awk '{print $1}' || echo "Unknown")
    local major_version=$(detect_jdk_version "$jdk_path")
    
    # 计算目录大小
    local size_mb
    size_mb=$(du -sm "$jdk_path" 2>/dev/null | cut -f1 || echo "0")
    
    cat << EOF
{
    "path": "$jdk_path",
    "version": "$version",
    "major_version": "$major_version",
    "vendor": "$vendor",
    "size_mb": $size_mb,
    "last_detected": "$(date -Iseconds)"
}
EOF
}

# 扫描所有Boot JDK
scan_boot_jdks() {
    log "扫描Boot JDK目录: $BOOTJDK_DIR"
    
    local jdks=()
    
    # 检查是否有压缩包需要解压
    for archive in "$BOOTJDK_DIR"/*.tar.gz "$BOOTJDK_DIR"/*.tgz; do
        if [ -f "$archive" ]; then
            local basename=$(basename "$archive" .tar.gz)
            basename=$(basename "$basename" .tgz)
            local extract_dir="$BOOTJDK_DIR/${basename}_extracted"
            
            if [ ! -d "$extract_dir" ]; then
                log "解压JDK压缩包: $archive"
                mkdir -p "$extract_dir"
                tar -xzf "$archive" -C "$extract_dir" --strip-components=1 2>/dev/null || {
                    tar -xzf "$archive" -C "$extract_dir"
                }
            fi
        fi
    done
    
    # 扫描所有JDK目录
    for jdk_dir in "$BOOTJDK_DIR"/*; do
        if [ -d "$jdk_dir" ] && [ -f "$jdk_dir/bin/java" ]; then
            local jdk_info
            if jdk_info=$(get_jdk_info "$jdk_dir"); then
                jdks+=("$jdk_info")
                log "发现JDK: $(echo "$jdk_info" | jq -r '.version') at $jdk_dir"
            fi
        fi
    done
    
    # 保存元数据
    if [ ${#jdks[@]} -gt 0 ]; then
        printf '%s\n' "${jdks[@]}" | jq -s '.' > "$METADATA_FILE"
        log "保存JDK元数据到: $METADATA_FILE"
    else
        echo '[]' > "$METADATA_FILE"
        log "未发现可用的Boot JDK"
    fi
}

# 获取所有可用的JDK
list_available_jdks() {
    if [ ! -f "$METADATA_FILE" ]; then
        scan_boot_jdks
    fi
    
    cat "$METADATA_FILE"
}

# 选择JDK
select_jdk() {
    local major_version="$1"
    local preferred_vendor="${2:-}"
    
    local selected_jdk
    selected_jdk=$(jq -r --arg major "$major_version" --arg vendor "$preferred_vendor" '
        map(select(.major_version == $major)) |
        if length == 0 then
            empty
        elif $vendor != "" then
            (map(select(.vendor | test($vendor; "i"))) | .[0]) // .[0]
        else
            .[0]
        end |
        .path
    ' "$METADATA_FILE" 2>/dev/null || echo "")
    
    if [ -n "$selected_jdk" ] && [ -d "$selected_jdk" ]; then
        echo "$selected_jdk"
        return 0
    else
        return 1
    fi
}

# 获取JDK统计信息
get_jdk_stats() {
    if [ ! -f "$METADATA_FILE" ]; then
        scan_boot_jdks
    fi
    
    local total_count total_size_mb
    total_count=$(jq 'length' "$METADATA_FILE")
    total_size_mb=$(jq 'map(.size_mb) | add // 0' "$METADATA_FILE")
    
    cat << EOF
{
    "total_jdks": $total_count,
    "total_size_mb": $total_size_mb,
    "available_versions": $(jq '[.[].major_version] | unique | sort_by(tonumber)' "$METADATA_FILE"),
    "vendors": $(jq '[.[].vendor] | unique | sort' "$METADATA_FILE")
}
EOF
}

# 删除JDK
remove_jdk() {
    local jdk_path="$1"
    
    if [ ! -d "$jdk_path" ]; then
        log "JDK目录不存在: $jdk_path"
        return 1
    fi
    
    log "删除JDK: $jdk_path"
    rm -rf "$jdk_path"
    
    # 更新元数据
    scan_boot_jdks
}

# 清理无效的JDK条目
cleanup_invalid_jdks() {
    log "清理无效的JDK条目"
    
    if [ ! -f "$METADATA_FILE" ]; then
        return 0
    fi
    
    local valid_jdks=()
    
    while IFS= read -r jdk_info; do
        local jdk_path
        jdk_path=$(echo "$jdk_info" | jq -r '.path')
        
        if [ -d "$jdk_path" ] && [ -f "$jdk_path/bin/java" ]; then
            valid_jdks+=("$jdk_info")
        else
            log "移除无效JDK条目: $jdk_path"
        fi
    done < <(jq -c '.[]' "$METADATA_FILE")
    
    if [ ${#valid_jdks[@]} -gt 0 ]; then
        printf '%s\n' "${valid_jdks[@]}" | jq -s '.' > "$METADATA_FILE"
    else
        echo '[]' > "$METADATA_FILE"
    fi
}

# 主函数
main() {
    case "${1:-help}" in
        "scan")
            scan_boot_jdks
            ;;
        "list")
            list_available_jdks
            ;;
        "select")
            select_jdk "${2:-17}" "${3:-}"
            ;;
        "stats")
            get_jdk_stats
            ;;
        "remove")
            remove_jdk "$2"
            ;;
        "cleanup")
            cleanup_invalid_jdks
            ;;
        "help"|*)
            cat << EOF
用法: $0 <命令> [参数...]

命令:
  scan
    扫描并检测所有Boot JDK
    
  list
    列出所有可用的Boot JDK
    
  select <major_version> [vendor]
    选择指定版本的JDK
    
  stats
    显示JDK统计信息
    
  remove <jdk_path>
    删除指定的JDK
    
  cleanup
    清理无效的JDK条目
    
  help
    显示此帮助信息

示例:
  $0 scan
  $0 list
  $0 select 17
  $0 select 8 adoptium
  $0 stats
EOF
            ;;
    esac
}

# 如果直接执行脚本，调用主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi