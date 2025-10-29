#!/bin/bash
set -euo pipefail

# CodeQL Database Builder - 数据库管理器
# 支持数据库压缩、下载、删除和清理功能

DATABASE_DIR="/app/database"
ARCHIVE_DIR="/app/database/archives"
METADATA_FILE="/app/database/.db_metadata.json"

# 确保目录存在
mkdir -p "$ARCHIVE_DIR"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 压缩数据库
compress_database() {
    local db_name="$1"
    local db_path="$DATABASE_DIR/$db_name"
    
    if [ ! -d "$db_path" ]; then
        log "数据库不存在: $db_path"
        return 1
    fi
    
    local archive_name="${db_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local archive_path="$ARCHIVE_DIR/$archive_name"
    
    log "开始压缩数据库: $db_name -> $archive_name"
    
    # 计算原始大小
    local original_size_mb
    original_size_mb=$(du -sm "$db_path" | cut -f1)
    
    # 压缩数据库
    tar -czf "$archive_path" -C "$DATABASE_DIR" "$db_name"
    
    if [ $? -eq 0 ]; then
        # 计算压缩后大小
        local compressed_size_mb
        compressed_size_mb=$(du -sm "$archive_path" | cut -f1)
        
        # 计算压缩比
        local compression_ratio
        compression_ratio=$(echo "scale=2; $compressed_size_mb * 100 / $original_size_mb" | bc -l)
        
        log "压缩完成: $original_size_mb MB -> $compressed_size_mb MB (${compression_ratio}%)"
        
        # 保存元数据
        save_archive_metadata "$archive_name" "$db_name" "$original_size_mb" "$compressed_size_mb"
        
        # 删除原始数据库目录
        log "删除原始数据库目录: $db_path"
        rm -rf "$db_path"
        
        echo "$archive_path"
        return 0
    else
        log "压缩失败"
        rm -f "$archive_path"
        return 1
    fi
}

# 保存压缩包元数据
save_archive_metadata() {
    local archive_name="$1"
    local db_name="$2"
    local original_size_mb="$3"
    local compressed_size_mb="$4"
    
    local metadata
    metadata=$(cat << EOF
{
    "archive_name": "$archive_name",
    "database_name": "$db_name",
    "created_time": "$(date -Iseconds)",
    "original_size_mb": $original_size_mb,
    "compressed_size_mb": $compressed_size_mb,
    "compression_ratio": $(echo "scale=2; $compressed_size_mb * 100 / $original_size_mb" | bc -l),
    "archive_path": "$ARCHIVE_DIR/$archive_name"
}
EOF
    )
    
    # 读取现有元数据
    local existing_metadata="[]"
    if [ -f "$METADATA_FILE" ]; then
        existing_metadata=$(cat "$METADATA_FILE")
    fi
    
    # 添加新的元数据
    echo "$existing_metadata" | jq ". + [$metadata]" > "$METADATA_FILE"
}

# 列出所有压缩包
list_archives() {
    if [ ! -f "$METADATA_FILE" ]; then
        echo "[]"
        return 0
    fi
    
    # 验证文件是否存在，清理无效条目
    local valid_archives=()
    
    while IFS= read -r archive_info; do
        local archive_path
        archive_path=$(echo "$archive_info" | jq -r '.archive_path')
        
        if [ -f "$archive_path" ]; then
            valid_archives+=("$archive_info")
        else
            log "清理无效压缩包条目: $archive_path"
        fi
    done < <(jq -c '.[]' "$METADATA_FILE")
    
    if [ ${#valid_archives[@]} -gt 0 ]; then
        printf '%s\n' "${valid_archives[@]}" | jq -s '.'
    else
        echo "[]"
    fi > "$METADATA_FILE"
    
    cat "$METADATA_FILE"
}

# 解压数据库
extract_database() {
    local archive_name="$1"
    local archive_path="$ARCHIVE_DIR/$archive_name"
    
    if [ ! -f "$archive_path" ]; then
        log "压缩包不存在: $archive_path"
        return 1
    fi
    
    log "解压数据库: $archive_name"
    
    # 解压到数据库目录
    tar -xzf "$archive_path" -C "$DATABASE_DIR"
    
    if [ $? -eq 0 ]; then
        log "解压完成"
        return 0
    else
        log "解压失败"
        return 1
    fi
}

# 删除压缩包
delete_archive() {
    local archive_name="$1"
    local archive_path="$ARCHIVE_DIR/$archive_name"
    
    if [ ! -f "$archive_path" ]; then
        log "压缩包不存在: $archive_path"
        return 1
    fi
    
    log "删除压缩包: $archive_name"
    rm -f "$archive_path"
    
    # 从元数据中移除
    if [ -f "$METADATA_FILE" ]; then
        jq --arg name "$archive_name" 'map(select(.archive_name != $name))' "$METADATA_FILE" > "$METADATA_FILE.tmp"
        mv "$METADATA_FILE.tmp" "$METADATA_FILE"
    fi
    
    log "压缩包已删除"
}

# 获取压缩包信息
get_archive_info() {
    local archive_name="$1"
    
    if [ ! -f "$METADATA_FILE" ]; then
        return 1
    fi
    
    jq --arg name "$archive_name" '.[] | select(.archive_name == $name)' "$METADATA_FILE"
}

# 清理残留文件
cleanup_residual_files() {
    log "清理残留的数据库文件"
    
    # 获取所有压缩包对应的数据库名称
    local archived_dbs=()
    if [ -f "$METADATA_FILE" ]; then
        while IFS= read -r db_name; do
            archived_dbs+=("$db_name")
        done < <(jq -r '.[].database_name' "$METADATA_FILE")
    fi
    
    # 检查数据库目录中的残留文件
    for db_dir in "$DATABASE_DIR"/*; do
        if [ -d "$db_dir" ] && [ "$(basename "$db_dir")" != "archives" ]; then
            local db_name=$(basename "$db_dir")
            
            # 检查是否有对应的压缩包
            local has_archive=false
            for archived_db in "${archived_dbs[@]}"; do
                if [ "$archived_db" = "$db_name" ]; then
                    has_archive=true
                    break
                fi
            done
            
            if [ "$has_archive" = "true" ]; then
                log "发现残留数据库目录: $db_name (已有压缩包)"
                read -p "是否删除残留目录 $db_name? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -rf "$db_dir"
                    log "已删除残留目录: $db_name"
                fi
            fi
        fi
    done
}

# 获取存储统计信息
get_storage_stats() {
    local total_archives=0
    local total_compressed_size_mb=0
    local total_original_size_mb=0
    
    if [ -f "$METADATA_FILE" ]; then
        total_archives=$(jq 'length' "$METADATA_FILE")
        total_compressed_size_mb=$(jq 'map(.compressed_size_mb) | add // 0' "$METADATA_FILE")
        total_original_size_mb=$(jq 'map(.original_size_mb) | add // 0' "$METADATA_FILE")
    fi
    
    local avg_compression_ratio=0
    if [ "$total_original_size_mb" -gt 0 ]; then
        avg_compression_ratio=$(echo "scale=2; $total_compressed_size_mb * 100 / $total_original_size_mb" | bc -l)
    fi
    
    cat << EOF
{
    "total_archives": $total_archives,
    "total_compressed_size_mb": $total_compressed_size_mb,
    "total_original_size_mb": $total_original_size_mb,
    "space_saved_mb": $(echo "$total_original_size_mb - $total_compressed_size_mb" | bc -l),
    "average_compression_ratio": $avg_compression_ratio
}
EOF
}

# 自动压缩完成的数据库
auto_compress_databases() {
    log "自动压缩完成的数据库"
    
    for db_dir in "$DATABASE_DIR"/*; do
        if [ -d "$db_dir" ] && [ "$(basename "$db_dir")" != "archives" ]; then
            local db_name=$(basename "$db_dir")
            
            # 检查是否是完整的CodeQL数据库
            if [ -f "$db_dir/codeql-database.yml" ]; then
                log "发现完成的数据库: $db_name"
                compress_database "$db_name"
            fi
        fi
    done
}

# 主函数
main() {
    case "${1:-help}" in
        "compress")
            compress_database "$2"
            ;;
        "list")
            list_archives
            ;;
        "extract")
            extract_database "$2"
            ;;
        "delete")
            delete_archive "$2"
            ;;
        "info")
            get_archive_info "$2"
            ;;
        "cleanup")
            cleanup_residual_files
            ;;
        "stats")
            get_storage_stats
            ;;
        "auto-compress")
            auto_compress_databases
            ;;
        "help"|*)
            cat << EOF
用法: $0 <命令> [参数...]

命令:
  compress <database_name>
    压缩指定的数据库
    
  list
    列出所有压缩包
    
  extract <archive_name>
    解压指定的压缩包
    
  delete <archive_name>
    删除指定的压缩包
    
  info <archive_name>
    显示压缩包信息
    
  cleanup
    清理残留的数据库文件
    
  stats
    显示存储统计信息
    
  auto-compress
    自动压缩所有完成的数据库
    
  help
    显示此帮助信息

示例:
  $0 compress my_database
  $0 list
  $0 delete my_database_20231028_120000.tar.gz
  $0 stats
EOF
            ;;
    esac
}

# 如果直接执行脚本，调用主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi