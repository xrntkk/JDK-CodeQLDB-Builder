#!/bin/bash
set -euo pipefail

# CodeQL Database Builder - 项目类型检测器
# 自动检测Java/Kotlin项目类型并生成相应的构建配置

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# 检测项目类型
detect_project_type() {
    local project_dir="$1"
    
    if [ ! -d "$project_dir" ]; then
        echo "unknown"
        return 1
    fi
    
    # 检测Maven项目
    if [ -f "$project_dir/pom.xml" ]; then
        echo "maven"
        return 0
    fi
    
    # 检测Gradle项目
    if [ -f "$project_dir/build.gradle" ] || [ -f "$project_dir/build.gradle.kts" ]; then
        echo "gradle"
        return 0
    fi
    
    # 检测Ant项目
    if [ -f "$project_dir/build.xml" ]; then
        echo "ant"
        return 0
    fi
    
    # 检测是否包含Java源码
    if find "$project_dir" -name "*.java" -type f -print -quit 2>/dev/null | grep -q .; then
        echo "java"
        return 0
    fi
    
    # 检测是否包含Kotlin源码
    if find "$project_dir" -name "*.kt" -type f -print -quit 2>/dev/null | grep -q .; then
        echo "kotlin"
        return 0
    fi
    
    echo "unknown"
    return 1
}

# 检测是否包含Kotlin代码
has_kotlin_sources() {
    local project_dir="$1"
    find "$project_dir" -name "*.kt" -type f | head -1 | grep -q . 2>/dev/null
}

# 检测是否为多模块项目
is_multimodule_project() {
    local project_dir="$1"
    local project_type="$2"
    
    case "$project_type" in
        "maven")
            # 检查是否有子模块的pom.xml
            find "$project_dir" -mindepth 2 -name "pom.xml" -type f | head -1 | grep -q . 2>/dev/null
            ;;
        "gradle")
            # 检查是否有settings.gradle或子项目的build.gradle
            [ -f "$project_dir/settings.gradle" ] || [ -f "$project_dir/settings.gradle.kts" ] || \
            find "$project_dir" -mindepth 2 -name "build.gradle*" -type f | head -1 | grep -q . 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# 生成Maven构建配置
generate_maven_build() {
    local project_dir="$1"
    local has_kotlin="$2"
    local is_multimodule="$3"
    
    cat << 'EOF'
<project name="codeql-build-maven" basedir="." default="build">
    <property name="user.dir" value="user-source"/>
    <property name="build.dir" value="build_classes"/>
    
    <!-- Maven构建任务 -->
    <target name="build" description="Build Maven project">
        <mkdir dir="${build.dir}"/>
        
        <!-- 使用Maven进行构建 -->
        <exec executable="mvn" dir="${user.dir}" failonerror="false">
            <arg value="clean"/>
            <arg value="compile"/>
EOF

    if [ "$has_kotlin" = "true" ]; then
        cat << 'EOF'
            <arg value="-Dkotlin.compiler.incremental=false"/>
EOF
    fi

    if [ "$is_multimodule" = "true" ]; then
        cat << 'EOF'
            <arg value="-pl"/>
            <arg value="!integration-tests"/>
EOF
    fi

    cat << 'EOF'
        </exec>
        
        <!-- 复制编译结果 -->
        <copy todir="${build.dir}" failonerror="false">
            <fileset dir="${user.dir}/target/classes" erroronmissingdir="false"/>
        </copy>
        
        <!-- 处理多模块项目 -->
EOF

    if [ "$is_multimodule" = "true" ]; then
        cat << 'EOF'
        <exec executable="find" outputproperty="module.targets">
            <arg value="${user.dir}"/>
            <arg value="-name"/>
            <arg value="target"/>
            <arg value="-type"/>
            <arg value="d"/>
        </exec>
        
        <for list="${module.targets}" param="target.dir" delimiter="${line.separator}">
            <sequential>
                <copy todir="${build.dir}" failonerror="false">
                    <fileset dir="@{target.dir}/classes" erroronmissingdir="false"/>
                </copy>
            </sequential>
        </for>
EOF
    fi

    cat << 'EOF'
    </target>
</project>
EOF
}

# 生成Gradle构建配置
generate_gradle_build() {
    local project_dir="$1"
    local has_kotlin="$2"
    local is_multimodule="$3"
    
    cat << 'EOF'
<project name="codeql-build-gradle" basedir="." default="build">
    <property name="user.dir" value="user-source"/>
    <property name="build.dir" value="build_classes"/>
    
    <!-- Gradle构建任务 -->
    <target name="build" description="Build Gradle project">
        <mkdir dir="${build.dir}"/>
        
        <!-- 使用Gradle进行构建 -->
        <exec executable="./gradlew" dir="${user.dir}" failonerror="false">
            <arg value="clean"/>
            <arg value="compileJava"/>
EOF

    if [ "$has_kotlin" = "true" ]; then
        cat << 'EOF'
            <arg value="compileKotlin"/>
EOF
    fi

    cat << 'EOF'
        </exec>
        
        <!-- 复制编译结果 -->
        <copy todir="${build.dir}" failonerror="false">
            <fileset dir="${user.dir}/build/classes" erroronmissingdir="false"/>
        </copy>
        
EOF

    if [ "$is_multimodule" = "true" ]; then
        cat << 'EOF'
        <!-- 处理多模块项目 -->
        <exec executable="find" outputproperty="module.builds">
            <arg value="${user.dir}"/>
            <arg value="-name"/>
            <arg value="build"/>
            <arg value="-type"/>
            <arg value="d"/>
        </exec>
        
        <for list="${module.builds}" param="build.dir.path" delimiter="${line.separator}">
            <sequential>
                <copy todir="${build.dir}" failonerror="false">
                    <fileset dir="@{build.dir.path}/classes" erroronmissingdir="false"/>
                </copy>
            </sequential>
        </for>
EOF
    fi

    cat << 'EOF'
    </target>
</project>
EOF
}

# 生成Kotlin专用构建配置
generate_kotlin_build() {
    local project_dir="$1"
    
    cat << 'EOF'
<project name="codeql-build-kotlin" basedir="." default="build">
    <property name="user.dir" value="user-source"/>
    <property name="build.dir" value="build_classes"/>
    
    <!-- Kotlin构建任务 -->
    <target name="build" description="Build Kotlin project">
        <mkdir dir="${build.dir}"/>
        
        <!-- 编译Kotlin源码 -->
        <path id="kotlin.classpath">
            <fileset dir="${user.dir}/lib" includes="*.jar" erroronmissingdir="false"/>
            <pathelement path="${java.class.path}"/>
        </path>
        
        <!-- 使用kotlinc编译 -->
        <exec executable="kotlinc" failonerror="false">
            <arg value="-cp"/>
            <arg pathref="kotlin.classpath"/>
            <arg value="-d"/>
            <arg value="${build.dir}"/>
            <arg line="-Xjsr305=strict"/>
            <arg line="-Xjvm-default=all"/>
        </exec>
        
        <!-- 编译Java源码（如果存在） -->
        <javac destdir="${build.dir}" 
               source="8" 
               target="8" 
               fork="true" 
               optimize="off" 
               debug="on" 
               failonerror="false"
               includeantruntime="false">
            <src path="${user.dir}"/>
            <include name="**/*.java"/>
            <classpath refid="kotlin.classpath"/>
            <classpath path="${build.dir}"/>
        </javac>
    </target>
</project>
EOF
}

# 生成通用Java构建配置
generate_java_build() {
    local project_dir="$1"
    
    cat << 'EOF'
<project name="codeql-build-java" basedir="." default="build">
    <property name="user.dir" value="user-source"/>
    <property name="build.dir" value="build_classes"/>
    
    <!-- 通用Java构建任务 -->
    <target name="build" description="Build Java project">
        <mkdir dir="${build.dir}"/>
        
        <path id="project.classpath">
            <fileset dir="${user.dir}/lib" includes="*.jar" erroronmissingdir="false"/>
            <fileset dir="${user.dir}" includes="**/*.jar" erroronmissingdir="false"/>
            <pathelement path="${java.class.path}"/>
        </path>
        
        <javac destdir="${build.dir}" 
               source="8" 
               target="8" 
               fork="true" 
               optimize="off" 
               debug="on" 
               failonerror="false"
               includeantruntime="false">
            <src path="${user.dir}"/>
            <include name="**/*.java"/>
            <classpath refid="project.classpath"/>
        </javac>
    </target>
</project>
EOF
}

# 主函数
main() {
    local project_dir="${1:-/app/user-source}"
    local output_file="${2:-/app/build-user.xml}"
    
    if [ ! -d "$project_dir" ]; then
        log "项目目录不存在: $project_dir"
        exit 1
    fi
    
    log "检测项目类型: $project_dir"
    
    # 检测项目类型
    local project_type
    project_type=$(detect_project_type "$project_dir") || project_type="java"
    
    log "检测到项目类型: $project_type"
    
    # 检测是否包含Kotlin代码
    local has_kotlin="false"
    if has_kotlin_sources "$project_dir" 2>/dev/null; then
        has_kotlin="true"
        log "检测到Kotlin源码"
    fi
    
    # 检测是否为多模块项目
    local is_multimodule="false"
    if is_multimodule_project "$project_dir" "$project_type" 2>/dev/null; then
        is_multimodule="true"
        log "检测到多模块项目"
    fi
    
    log "项目类型: $project_type"
    log "包含Kotlin: $has_kotlin"
    log "多模块项目: $is_multimodule"
    
    # 生成构建配置
    case "$project_type" in
        "maven")
            log "生成Maven构建配置"
            generate_maven_build "$project_dir" "$has_kotlin" "$is_multimodule" > "$output_file"
            ;;
        "gradle")
            log "生成Gradle构建配置"
            generate_gradle_build "$project_dir" "$has_kotlin" "$is_multimodule" > "$output_file"
            ;;
        "kotlin")
            log "生成Kotlin构建配置"
            generate_kotlin_build "$project_dir" > "$output_file"
            ;;
        "java"|"ant"|*)
            log "生成Java构建配置"
            generate_java_build "$project_dir" > "$output_file"
            ;;
    esac
    
    log "构建配置已生成: $output_file"
    
    # 输出项目信息JSON
    cat << EOF
{
    "project_type": "$project_type",
    "has_kotlin": $has_kotlin,
    "is_multimodule": $is_multimodule,
    "build_file": "$output_file"
}
EOF
}

# 如果直接执行脚本，调用主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi