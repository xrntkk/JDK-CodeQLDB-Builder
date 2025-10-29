#!/bin/bash

echo "=== CodeQL Builder (Enhanced with Web UI) ==="
echo "This container creates CodeQL databases with enhanced features:"
echo "  - Web management interface"
echo "  - Intelligent caching system"
echo "  - Maven/Gradle/Kotlin support"
echo "  - Build progress monitoring"
echo ""
echo "Available directories:"
echo "  - /app/bootjdk    : Place your Boot JDK here (supports dropping Linux JDK .tar.gz; auto-extracts)"
echo "  - /app/user-source: Place your program source code here (project root)"
echo "  - /app/source     : JDK source code directory (auto-downloaded if missing)"
echo "  - /app/codeql     : Place your CodeQL CLI here"
echo "  - /app/database   : Output directory for CodeQL databases"
echo "  - /app/cache      : Cache directory for sources and builds"
echo "  - /app/logs       : Log files directory"
echo ""
echo "Environment requirements:"
echo "  - Boot JDK under /app/bootjdk (JAVA_HOME will use it; .tar.gz supported)"
echo "  - CodeQL CLI under /app/codeql"
echo "  - Optional: User Java/Kotlin sources under /app/user-source"
echo "Behavior: If /app/source is missing, JDK sources will be downloaded automatically before building."
echo "Runtime: CodeQL CLI runs on Java ${CODEQL_RUNTIME_MAJOR:-17} by default (installs 17 if needed; falls back to 11)."
echo ""

# 启动Web管理界面（如果启用）
if [ "${WEB_UI_ENABLED:-false}" = "true" ]; then
  echo "Starting Web Management Interface on port 8080..."
  cd /app/web && python3 app.py &
  WEB_PID=$!
  echo "Web UI started with PID: $WEB_PID"
  echo "Access the web interface at: http://localhost:8080"
  echo ""
fi

# 清理过期缓存
echo "Cleaning up expired cache..."
bash /app/scripts/cache-manager.sh cleanup 30 10

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
  echo "Or use the Web UI at http://localhost:8080 to manage builds."
fi

# 保持容器运行
if [ "${WEB_UI_ENABLED:-false}" = "true" ]; then
  echo "Container will keep running with Web UI..."
  wait $WEB_PID
else
  echo "Build process completed. Container will exit."
fi