#!/bin/bash
set -e

START_TIME=$(date +%s)
echo "=== JDK CodeQL Database Builder ==="
echo "Starting build process at $(date)"

SOURCE_DIR_PATTERN="/app/source/*"
BOOT_JDK_PATTERN="/app/bootjdk/*"
CODEQL_PATH_PATTERN="/app/codeql/*"

if [ ! -d /app/bootjdk ] || [ -z "$(ls -A /app/bootjdk)" ]; then
    echo "Error: Boot JDK directory empty or not found"
    exit 1
fi

if [ ! -d /app/source ] || [ -z "$(ls -A /app/source)" ]; then
    echo "Error: Source directory empty or not found"
    exit 1
fi

if [ ! -d /app/codeql ] || [ -z "$(ls -A /app/codeql)" ]; then
    echo "Error: CodeQL directory empty or not found"
    exit 1
fi

mkdir -p /app/database

cd $SOURCE_DIR_PATTERN
SOURCE_DIR=$(pwd)
echo "Source directory: $SOURCE_DIR"

# 时间验证修复
CURRENCY_DATA_FILE=$(find . -name "GenerateCurrencyData.java")
if [ -n "$CURRENCY_DATA_FILE" ]; then
    echo "Applying time validation fix to $CURRENCY_DATA_FILE"
    cp "$CURRENCY_DATA_FILE" "${CURRENCY_DATA_FILE}.bak"
    sed -i 's/if (Math.abs(time - System.currentTimeMillis()) > (10L * 365 * 24 * 60 * 60 * 1000)) {/if (false) {/' "$CURRENCY_DATA_FILE"
fi

BOOT_JDK_PATH=$(echo $BOOT_JDK_PATTERN)
echo "Boot JDK: $BOOT_JDK_PATH"

CODEQL_EXE=$(find /app/codeql -name "codeql" -type f | head -1)
if [ -z "$CODEQL_EXE" ]; then
    echo "Error: CodeQL executable not found"
    exit 1
fi
echo "CodeQL executable: $CODEQL_EXE"

DB_NAME=$(basename "$SOURCE_DIR")
DB_PATH="/app/database/$DB_NAME"
echo "Database will be created at: $DB_PATH"


cd $SOURCE_DIR
echo "Cleaning previous build artifacts..."
make dist-clean

echo "Configuring build..."
export DISABLE_HOTSPOT_OS_VERSION_CHECK=ok
bash configure --with-boot-jdk=$BOOT_JDK_PATH

echo "Creating CodeQL database..."
"$CODEQL_EXE" database create "$DB_PATH" \
    --language="java" \
    --source-root="$SOURCE_DIR" \
    --command="make images"

RESULT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ $RESULT -eq 0 ]; then
    echo "=== Database creation completed successfully! ==="
    echo "Total time: $(($DURATION / 60)) minutes and $(($DURATION % 60)) seconds"
else
    echo "=== Database creation failed with error code $RESULT ==="
    echo "Time spent: $(($DURATION / 60)) minutes and $(($DURATION % 60)) seconds"

    exit $RESULT
fi