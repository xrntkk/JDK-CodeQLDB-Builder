#!/bin/bash
set -euo pipefail

# CodeQL Database Builder - 缓存管理器
# 实现JDK源码和编译结果的智能缓存机制

CACHE_DIR="/app/cache"
SOURCE_CACHE_DIR="$CACHE_DIR/sources"
BUILD_CACHE_DIR="$CACHE_DIR/builds"
METADATA_DIR="$CACHE_DIR/metadata"

# 创建缓存目录
mkdir -p "$SOURCE_CACHE_DIR" "$BUILD_CACHE_DIR" "$METADATA_DIR"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 计算文件/目录的哈希值
calculate_hash() {
    local path="$1"
    if [ -f "$path" ]; then
        sha256sum "$path" | cut -d' ' -f1
    elif [ -d "$path" ]; then
        find "$path" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1
    else
        echo "empty"
    fi
}

# 获取缓存键
get_cache_key() {
    local jdk_version="$1"
    local jdk_full_version="$2"
    local build_mode="$3"
    
    echo "${jdk_version}_${jdk_full_version}_${build_mode}"
}

# 检查源码缓存
check_source_cache() {
    local jdk_version="$1"
    local jdk_full_version="$2"
    local cache_key
    cache_key=$(get_cache_key "$jdk_version" "$jdk_full_version" "source")
    
    local cache_path="$SOURCE_CACHE_DIR/$cache_key"
    local metadata_file="$METADATA_DIR/${cache_key}.json"
    
    if [ -d "$cache_path" ] && [ -f "$metadata_file" ]; then
        log "找到源码缓存: $cache_key"
        echo "$cache_path"
        return 0
    else
        log "未找到源码缓存: $cache_key"
        return 1
    fi
}

# 保存源码到缓存
save_source_cache() {
    local jdk_version="$1"
    local jdk_full_version="$2"
    local source_path="$3"
    
    local cache_key
    cache_key=$(get_cache_key "$jdk_version" "$jdk_full_version" "source")
    
    local cache_path="$SOURCE_CACHE_DIR/$cache_key"
    local metadata_file="$METADATA_DIR/${cache_key}.json"
    
    log "保存源码缓存: $cache_key"
    
    # 复制源码
    rm -rf "$cache_path"
    cp -r "$source_path" "$cache_path"
    
    # 计算大小
    local size_mb
    size_mb=$(du -sm "$cache_path" | cut -f1)
    
    # 保存元数据
    cat > "$metadata_file" << EOF
{
    "cache_key": "$cache_key",
    "jdk_version": "$jdk_version",
    "jdk_full_version": "$jdk_full_version",
    "type": "source",
    "created_time": "$(date -Iseconds)",
    "size_mb": $size_mb,
    "hash": "$(calculate_hash "$cache_path")"
}
EOF
    
    log "源码缓存已保存: ${size_mb}MB"
}

# 恢复源码缓存
restore_source_cache() {
    local cache_path="$1"
    local target_path="$2"
    
    log "恢复源码缓存: $cache_path -> $target_path"
    
    rm -rf "$target_path"
    cp -r "$cache_path" "$target_path"
    
    log "源码缓存恢复完成"
}

# 检查构建缓存
check_build_cache() {
    local jdk_version="$1"
    local jdk_full_version="$2"
    local build_mode="$3"
    local user_source_hash="$4"
    
    local cache_key
    cache_key=$(get_cache_key "$jdk_version" "$jdk_full_version" "${build_mode}_${user_source_hash}")
    
    local cache_path="$BUILD_CACHE_DIR/$cache_key"
    local metadata_file="$METADATA_DIR/${cache_key}.json"
    
    if [ -d "$cache_path" ] && [ -f "$metadata_file" ]; then
        # 检查用户源码是否变化
        local cached_hash
        cached_hash=$(jq -r '.user_source_hash' "$metadata_file" 2>/dev/null || echo "")
        
        if [ "$cached_hash" = "$user_source_hash" ]; then
            log "找到构建缓存: $cache_key"
            echo "$cache_path"
            return 0
        else
            log "用户源码已变化，缓存无效: $cache_key"
        fi
    fi
    
    log "未找到构建缓存: $cache_key"
    return 1
}

# 保存构建缓存
save_build_cache() {
    local jdk_version="$1"
    local jdk_full_version="$2"
    local build_mode="$3"
    local user_source_hash="$4"
    local build_path="$5"
    
    local cache_key
    cache_key=$(get_cache_key "$jdk_version" "$jdk_full_version" "${build_mode}_${user_source_hash}")
    
    local cache_path="$BUILD_CACHE_DIR/$cache_key"
    local metadata_file="$METADATA_DIR/${cache_key}.json"
    
    log "保存构建缓存: $cache_key"
    
    # 复制构建结果
    rm -rf "$cache_path"
    cp -r "$build_path" "$cache_path"
    
    # 计算大小
    local size_mb
    size_mb=$(du -sm "$cache_path" | cut -f1)
    
    # 保存元数据
    cat > "$metadata_file" << EOF
{
    "cache_key": "$cache_key",
    "jdk_version": "$jdk_version",
    "jdk_full_version": "$jdk_full_version",
    "build_mode": "$build_mode",
    "user_source_hash": "$user_source_hash",
    "type": "build",
    "created_time": "$(date -Iseconds)",
    "size_mb": $size_mb,
    "hash": "$(calculate_hash "$cache_path")"
}
EOF
    
    log "构建缓存已保存: ${size_mb}MB"
}

# 恢复构建缓存
restore_build_cache() {
    local cache_path="$1"
    local target_path="$2"
    
    log "恢复构建缓存: $cache_path -> $target_path"
    
    rm -rf "$target_path"
    cp -r "$cache_path" "$target_path"
    
    log "构建缓存恢复完成"
}

# 清理过期缓存
cleanup_cache() {
    local max_age_days="${1:-30}"  # 默认30天
    local max_size_gb="${2:-10}"   # 默认10GB
    
    log "开始清理缓存 (保留${max_age_days}天, 最大${max_size_gb}GB)"
    
    # 按时间清理
    find "$CACHE_DIR" -type f -mtime +$max_age_days -delete
    find "$CACHE_DIR" -type d -empty -delete
    
    # 按大小清理（保留最新的）
    local current_size_gb
    current_size_gb=$(du -sg "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    if [ "$current_size_gb" -gt "$max_size_gb" ]; then
        log "缓存大小超限 (${current_size_gb}GB > ${max_size_gb}GB)，清理最旧的缓存"
        
        # 获取所有缓存目录，按修改时间排序
        find "$SOURCE_CACHE_DIR" "$BUILD_CACHE_DIR" -maxdepth 1 -type d -not -path "$SOURCE_CACHE_DIR" -not -path "$BUILD_CACHE_DIR" -printf '%T@ %p\n' | sort -n | while read -r timestamp path; do
            rm -rf "$path"
            
            # 删除对应的元数据
            local basename
            basename=$(basename "$path")
            rm -f "$METADATA_DIR/${basename}.json"
            
            # 重新检查大小
            current_size_gb=$(du -sg "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
            if [ "$current_size_gb" -le "$max_size_gb" ]; then
                break
            fi
        done
    fi
    
    log "缓存清理完成"
}

# 获取缓存统计信息
get_cache_stats() {
    local total_size_mb
    total_size_mb=$(du -sm "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    local source_count
    source_count=$(find "$SOURCE_CACHE_DIR" -maxdepth 1 -type d | wc -l)
    source_count=$((source_count - 1))  # 减去目录本身
    
    local build_count
    build_count=$(find "$BUILD_CACHE_DIR" -maxdepth 1 -type d | wc -l)
    build_count=$((build_count - 1))  # 减去目录本身
    
    cat << EOF
{
    "total_size_mb": $total_size_mb,
    "source_cache_count": $source_count,
    "build_cache_count": $build_count,
    "cache_dir": "$CACHE_DIR"
}
EOF
}

# 检测源码变化
detect_source_changes() {
    local source_path="$1"
    local last_hash_file="$2"
    
    local current_hash
    current_hash=$(calculate_hash "$source_path")
    
    if [ -f "$last_hash_file" ]; then
        local last_hash
        last_hash=$(cat "$last_hash_file")
        
        if [ "$current_hash" = "$last_hash" ]; then
            log "源码未变化"
            return 1  # 未变化
        else
            log "检测到源码变化"
        fi
    else
        log "首次构建，无历史哈希"
    fi
    
    # 保存当前哈希
    echo "$current_hash" > "$last_hash_file"
    return 0  # 有变化
}

# 主函数
main() {
    case "${1:-help}" in
        "check-source")
            check_source_cache "$2" "$3"
            ;;
        "save-source")
            save_source_cache "$2" "$3" "$4"
            ;;
        "restore-source")
            restore_source_cache "$2" "$3"
            ;;
        "check-build")
            check_build_cache "$2" "$3" "$4" "$5"
            ;;
        "save-build")
            save_build_cache "$2" "$3" "$4" "$5" "$6"
            ;;
        "restore-build")
            restore_build_cache "$2" "$3"
            ;;
        "cleanup")
            cleanup_cache "${2:-30}" "${3:-10}"
            ;;
        "stats")
            get_cache_stats
            ;;
        "detect-changes")
            detect_source_changes "$2" "$3"
            ;;
        "help"|*)
            cat << EOF
用法: $0 <命令> [参数...]

命令:
  check-source <jdk_version> <jdk_full_version>
    检查源码缓存是否存在
    
  save-source <jdk_version> <jdk_full_version> <source_path>
    保存源码到缓存
    
  restore-source <cache_path> <target_path>
    从缓存恢复源码
    
  check-build <jdk_version> <jdk_full_version> <build_mode> <user_source_hash>
    检查构建缓存是否存在
    
  save-build <jdk_version> <jdk_full_version> <build_mode> <user_source_hash> <build_path>
    保存构建结果到缓存
    
  restore-build <cache_path> <target_path>
    从缓存恢复构建结果
    
  cleanup [max_age_days] [max_size_gb]
    清理过期缓存 (默认: 30天, 10GB)
    
  stats
    显示缓存统计信息
    
  detect-changes <source_path> <hash_file>
    检测源码是否有变化
    
  help
    显示此帮助信息

示例:
  $0 check-source 17 17.0.2
  $0 save-source 17 17.0.2 /app/source
  $0 cleanup 7 5
EOF
            ;;
    esac
}

# 如果直接执行脚本，调用主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi