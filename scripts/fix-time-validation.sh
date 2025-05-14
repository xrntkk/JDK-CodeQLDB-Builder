#!/bin/bash

# 此脚本用于修复 JDK 编译时可能遇到的时间验证问题

SOURCE_DIR="$1"

if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: $0 <jdk_source_dir>"
    exit 1
fi

# 检查是否存在 GenerateCurrencyData.java 文件
CURRENCY_DATA_FILE=$(find "$SOURCE_DIR" -name "GenerateCurrencyData.java")

if [ -n "$CURRENCY_DATA_FILE" ]; then
    echo "Fixing time validation in $CURRENCY_DATA_FILE"

    # 备份文件
    cp "$CURRENCY_DATA_FILE" "${CURRENCY_DATA_FILE}.bak"

    # 修改时间验证条件
    sed -i 's/if (Math.abs(time - System.currentTimeMillis()) > (10L * 365 * 24 * 60 * 60 * 1000)) {/if (false) {/' "$CURRENCY_DATA_FILE"

    echo "Time validation fix applied"
else
    echo "Currency data file not found, skipping time validation fix"
fi