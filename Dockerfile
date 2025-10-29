FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update

# 安装开发工具和基础依赖
RUN apt-get install -y build-essential \
    ccache \
    autoconf \
    file \
    unzip \
    zip \
    cpio \
    make \
    ant \
    git \
    libtool \
    m4 \
    patch \
    pkg-config

# 安装 X11 开发库
RUN apt-get install -y libxtst-dev \
    libxt-dev \
    libxrender-dev \
    libxrandr-dev \
    libxi-dev \
    libx11-dev \
    libxext-dev \
    libxcomposite-dev

# 安装图形和多媒体相关库
RUN apt-get install -y \
    libcups2-dev \
    libfreetype6-dev \
    libasound2-dev \
    libfontconfig1-dev \
    libjpeg-dev \
    libpng-dev \
    libgif-dev

# 安装系统和工具库
RUN apt-get install -y \
    libffi-dev \
    libz-dev \
    libelf-dev \
    libsystemd-dev

# 安装其他工具（包含wget）
RUN apt-get install -y jq curl wget

# 安装用于运行 CodeQL CLI 的 Java 运行时（优先 17，失败则回退到 11）
RUN apt-get install -y openjdk-17-jre-headless || apt-get install -y openjdk-11-jre-headless

# 更新包列表并安装Maven和Gradle
RUN apt-get update && apt-get install -y maven || \
    (apt-get update --fix-missing && apt-get install -y maven)

# 安装Gradle
RUN wget -q https://services.gradle.org/distributions/gradle-7.6-bin.zip -O /tmp/gradle.zip && \
    unzip -q /tmp/gradle.zip -d /opt && \
    ln -s /opt/gradle-7.6/bin/gradle /usr/local/bin/gradle && \
    rm /tmp/gradle.zip

# 安装Kotlin编译器
RUN wget -q https://github.com/JetBrains/kotlin/releases/download/v1.8.10/kotlin-compiler-1.8.10.zip -O /tmp/kotlin.zip && \
    unzip -q /tmp/kotlin.zip -d /opt && \
    ln -s /opt/kotlinc/bin/kotlinc /usr/local/bin/kotlinc && \
    ln -s /opt/kotlinc/bin/kotlin /usr/local/bin/kotlin && \
    rm /tmp/kotlin.zip

# 安装反编译器
RUN mkdir -p /app/tools && \
    # 下载Procyon反编译器
    wget -O /app/tools/procyon-decompiler.jar \
    "https://github.com/mstrobel/procyon/releases/download/v0.6.0/procyon-decompiler-0.6.0.jar" && \
    # 下载Fernflower反编译器（使用Maven Central）
    wget -O /app/tools/fernflower.jar \
    "https://repo1.maven.org/maven2/org/jetbrains/java/decompiler/fernflower/1.0.0/fernflower-1.0.0.jar" || \
    # 如果上面的链接失败，创建一个占位符文件
    echo "Fernflower not available" > /app/tools/fernflower.jar

# # 安装bc计算器（用于数据库管理脚本）
RUN apt-get install -y bc && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装Python和Flask（用于Web界面）
RUN apt-get update --fix-missing && apt-get install -y python3 python3-pip && \
    pip3 install flask requests && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 默认 CodeQL 运行时主版本为 17（可在 docker-compose.yml 中覆盖 CODEQL_RUNTIME_MAJOR）
ENV CODEQL_RUNTIME_MAJOR=17

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 设置工作目录
WORKDIR /app

# 复制脚本文件
COPY scripts/ /app/scripts/
COPY web/ /app/web/

# 设置脚本执行权限
RUN chmod +x /app/scripts/*.sh

# 设置入口点
CMD ["/app/scripts/start.sh"]