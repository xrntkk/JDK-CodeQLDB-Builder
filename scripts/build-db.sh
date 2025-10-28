#!/bin/bash
set -euo pipefail

START_TIME=$(date +%s)
echo "=== CodeQL Database Builder (Hybrid Mode) ==="
echo "Starting build at $(date)"

USER_SOURCE_DIR="/app/user-source"
JDK_SOURCE_DIR="/app/source"
BOOT_JDK_PATH=""

# Validate prerequisites
if [ ! -d /app/bootjdk ] || [ -z "$(ls -A /app/bootjdk)" ]; then
    echo "Error: Boot JDK directory empty or not found at /app/bootjdk"
    exit 1
fi

if [ ! -d /app/codeql ] || [ -z "$(ls -A /app/codeql)" ]; then
    echo "Error: CodeQL directory empty or not found at /app/codeql"
    exit 1
fi

USR_PRESENT=false
JDK_PRESENT=false

if [ -d "$USER_SOURCE_DIR" ] && [ -n "$(ls -A "$USER_SOURCE_DIR" 2>/dev/null || true)" ]; then
  USR_PRESENT=true
fi

if [ -d "$JDK_SOURCE_DIR" ] && [ -n "$(ls -A "$JDK_SOURCE_DIR" 2>/dev/null || true)" ]; then
  JDK_PRESENT=true
fi

if ! $JDK_PRESENT; then
  echo "[INFO] JDK source not found in $JDK_SOURCE_DIR. Attempting auto-download via /app/scripts/download-jdk.sh ..."
  bash /app/scripts/download-jdk.sh || {
    echo "Error: JDK source download failed. Please verify network and JDK_VERSION/JDK_FULL_VERSION settings."; exit 1; }
  if [ -d "$JDK_SOURCE_DIR" ] && [ -n "$(ls -A "$JDK_SOURCE_DIR" 2>/dev/null || true)" ]; then
    JDK_PRESENT=true
    echo "[INFO] JDK source downloaded successfully."
  else
    echo "Error: JDK source still missing after download."
    exit 1
  fi
fi

mkdir -p /app/database

echo "User source present: $USR_PRESENT"
echo "JDK source present: $JDK_PRESENT"

# Build mode and DB name from environment
BUILD_MODE=${BUILD_MODE:-hybrid}   # supported: hybrid | jdk_only | user_only
DB_NAME=${DB_NAME:-hybrid}
echo "Selected build mode: $BUILD_MODE"
echo "Database name: $DB_NAME"

# Configure Java
extract_boot_jdk_if_needed() {
  local archive
  archive=$(find /app/bootjdk -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tgz" \) | head -1)
  if [ -n "$archive" ]; then
    echo "[INFO] Detected Boot JDK archive: $archive"
    mkdir -p /app/bootjdk/_extracted
    echo "[INFO] Extracting Boot JDK archive to /app/bootjdk/_extracted ..."
    tar -xzf "$archive" -C /app/bootjdk/_extracted
  fi
}

resolve_boot_jdk_path() {
  if [ -d /app/bootjdk/_extracted ]; then
    BOOT_JDK_PATH=$(find /app/bootjdk/_extracted -maxdepth 2 -type d \( -name "jdk*" -o -name "java-*" -o -name "openjdk*" \) | head -1)
  fi
  if [ -z "${BOOT_JDK_PATH:-}" ]; then
    BOOT_JDK_PATH=$(find /app/bootjdk -mindepth 1 -maxdepth 1 -type d -not -name "_extracted" | head -1)
  fi
  if [ -z "$BOOT_JDK_PATH" ]; then
    echo "Error: No valid Boot JDK directory found under /app/bootjdk after extraction."
    echo "Hint: Place a Linux x64 JDK .tar.gz or an extracted JDK directory under /app/bootjdk."
    exit 1
  fi
}

extract_boot_jdk_if_needed
resolve_boot_jdk_path

echo "Boot JDK: $BOOT_JDK_PATH"

export JAVA_HOME="$BOOT_JDK_PATH"
export PATH="$JAVA_HOME/bin:$PATH"
BOOT_VER_STR=$("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)
BOOT_MAJOR=""
if echo "$BOOT_VER_STR" | grep -q '"1\.'; then
  # Java 8 style: java version "1.8.0_71"
  BOOT_MAJOR=$(echo "$BOOT_VER_STR" | sed -E 's/.*"1\.([0-9]+)\..*/\1/')
else
  # Java 11+ style: openjdk version "11.0.23"
  BOOT_MAJOR=$(echo "$BOOT_VER_STR" | sed -E 's/.*"([0-9]+)\..*/\1/')
fi
echo "Detected Boot JDK major version: ${BOOT_MAJOR:-unknown}"
DESIRED_MAJOR=${CODEQL_RUNTIME_MAJOR:-17}
echo "Desired CodeQL runtime major: $DESIRED_MAJOR"

# Locate CodeQL CLI
CODEQL_EXE=$(find /app/codeql -type f -name codeql -o -name codeql.exe | head -1)
if [ -z "$CODEQL_EXE" ]; then
    echo "Error: CodeQL executable not found under /app/codeql"
    exit 1
fi
echo "CodeQL executable: $CODEQL_EXE"

CODEQL_DIR=$(dirname "$CODEQL_EXE")
CODEQL_JAVA_BIN_DIR="$CODEQL_DIR/tools/linux64/java/bin"

# Ensure CodeQL uses desired Java (default 17) regardless of embedded JRE presence
ensure_codeql_runtime() {
  # Prefer Boot JDK if it meets desired major
  if [ -n "$BOOT_MAJOR" ] && [ "$BOOT_MAJOR" -ge "$DESIRED_MAJOR" ]; then
    export CODEQL_JAVA_HOME="$JAVA_HOME"
    echo "[INFO] Using Boot JDK (major $BOOT_MAJOR) as CodeQL runtime via CODEQL_JAVA_HOME=$CODEQL_JAVA_HOME"
  else
    # Try installing desired Java headless runtime first
    echo "[INFO] Boot JDK is $BOOT_MAJOR; installing OpenJDK ${DESIRED_MAJOR} headless for CodeQL runtime..."
    apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "openjdk-${DESIRED_MAJOR}-jre-headless" || true
    local sys_java_home
    if [ -d "/usr/lib/jvm/java-${DESIRED_MAJOR}-openjdk-amd64" ]; then
      sys_java_home="/usr/lib/jvm/java-${DESIRED_MAJOR}-openjdk-amd64"
    else
      # Fallback resolve via absolute /usr/bin/java (ignores PATH where Boot JDK is prepended)
      if [ -x "/usr/bin/java" ]; then
        sys_java_home=$(dirname "$(dirname "$(readlink -f "/usr/bin/java")")")
      fi
    fi
    # If desired major not available, fallback to 11
    if [ -z "$sys_java_home" ] || ! "$sys_java_home/bin/java" -version >/dev/null 2>&1; then
      echo "[WARN] Java ${DESIRED_MAJOR} not available; falling back to OpenJDK 11"
      apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jre-headless
      if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
        sys_java_home="/usr/lib/jvm/java-11-openjdk-amd64"
      elif [ -x "/usr/bin/java" ]; then
        sys_java_home=$(dirname "$(dirname "$(readlink -f "/usr/bin/java")")")
      fi
      if [ -z "$sys_java_home" ] || [ ! -x "$sys_java_home/bin/java" ]; then
        echo "Error: Could not resolve system Java home for CodeQL runtime."
        exit 1
      fi
    fi
    export CODEQL_JAVA_HOME="$sys_java_home"
    echo "[INFO] Using system Java as CodeQL runtime via CODEQL_JAVA_HOME=$CODEQL_JAVA_HOME"
  fi

  # Create symlinks so CodeQL scripts that reference embedded path still resolve to our chosen runtime
  if [ -n "${CODEQL_JAVA_HOME:-}" ] && [ -x "$CODEQL_JAVA_HOME/bin/java" ]; then
    mkdir -p "$CODEQL_JAVA_BIN_DIR"
    ln -sf "$CODEQL_JAVA_HOME/bin/java" "$CODEQL_JAVA_BIN_DIR/java"
    ln -sf "$CODEQL_JAVA_HOME/bin/javac" "$CODEQL_JAVA_BIN_DIR/javac" || true
    echo "[INFO] Symlinked CodeQL tools java/javac to CODEQL_JAVA_HOME runtime"
  fi
}

ensure_codeql_runtime

# Prepare Ant build for USER sources only (avoid recompiling JDK via Ant)
BUILD_USER_XML_PATH="/app/build-user.xml"
echo "Generating Ant build file for user sources at $BUILD_USER_XML_PATH"
if [ -n "${CATALINA_HOME:-}" ] && [ -d "$CATALINA_HOME" ]; then
cat > "$BUILD_USER_XML_PATH" << 'EOF'
<project name="codeql-build-user" basedir="." default="build">
  <property name="user.dir" value="user-source"/>
  <property name="build.dir" value="build_user_classes"/>
  <property name="tomcat.dir" value="${env.CATALINA_HOME}"/>
  <path id="user-classpath">
    <pathelement path="${tomcat.dir}/lib"/>
    <fileset dir="${tomcat.dir}/lib">
      <include name="*.jar"/>
    </fileset>
    <fileset dir="${tomcat.dir}/bin">
      <include name="*.jar"/>
    </fileset>
    <fileset dir="${user.dir}/lib">
      <include name="*.jar"/>
    </fileset>
  </path>
  <target name="build" description="Compile user project sources only">
    <mkdir dir="${build.dir}"/>
    <javac destdir="${build.dir}" source="8" target="8" fork="true" optimize="off" debug="on" failonerror="false">
      <src path="${user.dir}"/>
      <classpath refid="user-classpath"/>
    </javac>
  </target>
</project>
EOF
else
cat > "$BUILD_USER_XML_PATH" << 'EOF'
<project name="codeql-build-user" basedir="." default="build">
  <property name="user.dir" value="user-source"/>
  <property name="build.dir" value="build_user_classes"/>
  <target name="build" description="Compile user project sources only">
    <mkdir dir="${build.dir}"/>
    <javac destdir="${build.dir}" source="8" target="8" fork="true" optimize="off" debug="on" failonerror="false">
      <src path="${user.dir}"/>
    </javac>
  </target>
</project>
EOF
fi

# Build CodeQL database using a single command chaining OpenJDK build and optional user Ant build
DB_PATH="/app/database/${DB_NAME}"
echo "Creating CodeQL database at: $DB_PATH"

# Prepare command strings for each mode
# Use double quotes for the -lc string to avoid mismatched single-quote issues
HYBRID_CMD="/bin/bash -lc \"set -e; cd /app/source; if [ -f configure ]; then chmod +x configure || true; echo Running configure...; ./configure --with-boot-jdk=$JAVA_HOME --with-debug-level=slowdebug --enable-debug-symbols || true; fi; echo Running make all for OpenJDK...; make all DISABLE_HOTSPOT_OS_VERSION_CHECK=OK ZIP_DEBUGINFO_FILES=0; if [ -d /app/user-source ] && ls -A /app/user-source >/dev/null 2>&1; then echo Compiling user project via Ant...; ant -f /app/build-user.xml; else echo No user sources; skipping Ant step.; fi\""

JDK_ONLY_CMD="/bin/bash -lc \"set -e; cd /app/source; if [ -f configure ]; then chmod +x configure || true; echo Running configure...; ./configure --with-boot-jdk=$JAVA_HOME --with-debug-level=slowdebug --enable-debug-symbols || true; fi; echo Running make all for OpenJDK...; make all DISABLE_HOTSPOT_OS_VERSION_CHECK=OK ZIP_DEBUGINFO_FILES=0\""

USER_ONLY_CMD="/bin/bash -lc \"set -e; if [ -d /app/user-source ] && ls -A /app/user-source >/dev/null 2>&1; then echo Compiling user project via Ant...; ant -f /app/build-user.xml; else echo No user sources; exiting.; exit 1; fi\""

# Select command based on mode
SELECTED_CMD="$HYBRID_CMD"
MODE_DESC="Hybrid: JDK make + user Ant"
case "$BUILD_MODE" in
  jdk_only)
    SELECTED_CMD="$JDK_ONLY_CMD"
    MODE_DESC="JDK only: configure + make (no Ant)"
    ;;
  user_only)
    SELECTED_CMD="$USER_ONLY_CMD"
    MODE_DESC="User only: Ant compile (no JDK build)"
    ;;
  hybrid|*)
    SELECTED_CMD="$HYBRID_CMD"
    MODE_DESC="Hybrid: JDK make + user Ant"
    ;;
esac
echo "Mode description: $MODE_DESC"

"$CODEQL_EXE" database create "$DB_PATH" \
  --language=java \
  --command="$SELECTED_CMD" \
  --source-root="/app" \
  --overwrite \
  --ram=51200

RESULT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ $RESULT -eq 0 ]; then
  echo "=== Database creation completed successfully ==="
  echo "Total time: $(($DURATION / 60)) minutes and $(($DURATION % 60)) seconds"
else
  echo "=== Database creation failed with error code $RESULT ==="
  echo "Time spent: $(($DURATION / 60)) minutes and $(($DURATION % 60)) seconds"
  exit $RESULT
fi