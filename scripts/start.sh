#!/bin/bash

echo "=== CodeQL Builder (${BUILD_MODE:-hybrid} mode) ==="
echo "This container creates one CodeQL database by first building OpenJDK (configure + make) and then compiling your project via Ant (if present)."
echo ""
echo "Available directories:"
echo "  - /app/bootjdk    : Place your Boot JDK here (supports dropping Linux JDK .tar.gz; auto-extracts)"
echo "  - /app/user-source: Place your program source code here (project root)"
echo "  - /app/source     : JDK source code directory (auto-downloaded if missing)"
echo "  - /app/codeql     : Place your CodeQL CLI here"
echo "  - /app/database   : Output directory for CodeQL databases"
echo ""
echo "Environment requirements:"
echo "  - Boot JDK under /app/bootjdk (JAVA_HOME will use it; .tar.gz supported)"
echo "  - CodeQL CLI under /app/codeql"
echo "  - Optional: User Java sources under /app/user-source (compiled via Ant after JDK build)"
echo "Behavior: If /app/source is missing, JDK sources will be downloaded automatically before building."
echo "Runtime: CodeQL CLI runs on Java ${CODEQL_RUNTIME_MAJOR:-17} by default (installs 17 if needed; falls back to 11)."
echo "Build mode: ${BUILD_MODE:-hybrid} (supported: hybrid | jdk_only | user_only)"
echo "Database name: ${DB_NAME:-hybrid}"

if [ "${AUTO_BUILD}" = "true" ]; then
  echo "Starting database build automatically..."
  /app/scripts/build-db.sh
  if [ $? -eq 0 ]; then
    echo "Build completed successfully!"
  else
    echo "Build failed! Check the logs for details."
  fi
else
  echo "AUTO_BUILD is disabled. Use './scripts/build-db.sh' to build manually."
fi