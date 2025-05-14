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


ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

COPY scripts/ /app/scripts/

RUN chmod +x /app/scripts/start.sh
RUN chmod +x /app/scripts/build-db.sh
RUN chmod +x /app/scripts/fix-time-validation.sh

ENTRYPOINT ["/app/scripts/start.sh"]