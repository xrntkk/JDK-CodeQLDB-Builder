#!/bin/bash

JDK_VERSION="${JDK_VERSION:-17}"
JDK_FULL_VERSION="${JDK_FULL_VERSION}"
SOURCE_DIR="/app/source"

# 检查主版本号是否有效
if [[ ! "$JDK_VERSION" =~ ^(8|11|17|21)$ ]]; then
    echo "Error: Invalid JDK version. Supported versions are: 8, 11, 17, 21"
    exit 1
fi

# 清空源码目录
rm -rf "${SOURCE_DIR:?}"/*

# 创建临时目录
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || exit 1

# 获取版本信息的函数
get_latest_tag() {
    local repo=$1
    local pattern=$2
    git ls-remote --tags --sort='-v:refname' "https://github.com/$repo" |
    grep -E "refs/tags/$pattern" |
    head -n 1 |
    awk '{print $2}' |
    sed 's/refs\/tags\///'
}

# 对提供的版本做模糊匹配，支持部分版本号（例如 17.0.2 或 8u111）
fuzzy_match_tag() {
    local repo=$1
    local prefix=$2   # 例如 jdk- 或 jdk
    local query=$3    # 例如 17.0.2 或 8u111
    local suffix_pat=$4 # 例如 \\+[0-9]+ 或 -b[0-9]+

    # 转义正则特殊字符
    local query_escaped
    query_escaped=$(printf '%s' "$query" | sed 's/[.[\()*^$?+|{}]/\\&/g')

    git ls-remote --tags --sort='-v:refname' "https://github.com/$repo" |
      awk '{print $2}' |
      sed 's#refs/tags/##' |
      grep -E "^${prefix}${query_escaped}(${suffix_pat})?$" |
      head -n 1
}

echo "Downloading OpenJDK $JDK_VERSION source code..."

# 根据版本选择下载地址
case "$JDK_VERSION" in
    "8")
        REPO="adoptium/jdk8u"
        if [ -n "$JDK_FULL_VERSION" ]; then
            TAG=$(fuzzy_match_tag "$REPO" "jdk" "$JDK_FULL_VERSION" "-b[0-9]+")
        fi
        # 回退到最新匹配
        if [ -z "$TAG" ]; then
            TAG=$(get_latest_tag "$REPO" "jdk8u[0-9]+-b[0-9]+$")
        fi
        git clone --depth 1 -b "$TAG" "https://github.com/$REPO.git" "$SOURCE_DIR"
        ;;
    "11")
        REPO="openjdk/jdk11"
        if [ -n "$JDK_FULL_VERSION" ]; then
            TAG=$(fuzzy_match_tag "$REPO" "jdk-" "$JDK_FULL_VERSION" "\\+[0-9]+")
        fi
        if [ -z "$TAG" ]; then
            TAG=$(get_latest_tag "$REPO" "jdk-11\\.[0-9]+\\.[0-9]+\\+[0-9]+$")
        fi
        git clone --depth 1 -b "$TAG" "https://github.com/$REPO.git" "$SOURCE_DIR"
        ;;
    "17")
        REPO="openjdk/jdk17"
        if [ -n "$JDK_FULL_VERSION" ]; then
            TAG=$(fuzzy_match_tag "$REPO" "jdk-" "$JDK_FULL_VERSION" "\\+[0-9]+")
        fi
        if [ -z "$TAG" ]; then
            TAG=$(get_latest_tag "$REPO" "jdk-17\\.[0-9]+\\.[0-9]+\\+[0-9]+$")
        fi
        git clone --depth 1 -b "$TAG" "https://github.com/$REPO.git" "$SOURCE_DIR"
        ;;
    "21")
        REPO="openjdk/jdk21"
        if [ -n "$JDK_FULL_VERSION" ]; then
            TAG=$(fuzzy_match_tag "$REPO" "jdk-" "$JDK_FULL_VERSION" "\\+[0-9]+")
        fi
        if [ -z "$TAG" ]; then
            TAG=$(get_latest_tag "$REPO" "jdk-21\\.[0-9]+\\.[0-9]+\\+[0-9]+$")
        fi
        git clone --depth 1 -b "$TAG" "https://github.com/$REPO.git" "$SOURCE_DIR"
        ;;
esac

if [ $? -eq 0 ]; then
    echo "Successfully downloaded OpenJDK $JDK_VERSION source code"
    
    # 如果是 JDK 8，需要运行 get_source.sh
    if [ "$JDK_VERSION" = "8" ]; then
        cd "$SOURCE_DIR" || exit 1
        bash get_source.sh
    fi
else
    echo "Error: Failed to download OpenJDK $JDK_VERSION source code"
    exit 1
fi

# 清理临时目录
rm -rf "$TMP_DIR"