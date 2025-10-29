# JDK CodeQL Database Builder

> 本项目基于 [h3h3qaq/JDK-CodeQLDB-Builder](https://github.com/h3h3qaq/JDK-CodeQLDB-Builder) 改造，新增了现代化Web管理界面、智能缓存、Maven/Gradle/Kotlin支持等功能。采用Tailwind CSS响应式设计，完全使用Claude3.5进行重构升级（没有一点技术，只有纯粹的拷打）。


> 🚀 **现代化的 CodeQL 数据库构建平台**  
> 集成 Web 管理界面、智能缓存系统和多项目类型支持的一站式解决方案

[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://www.docker.com/)
[![CodeQL](https://img.shields.io/badge/CodeQL-Latest-green.svg)](https://github.com/github/codeql)
[![JDK](https://img.shields.io/badge/JDK-8%20%7C%2011%20%7C%2017%20%7C%2021-orange.svg)](https://openjdk.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## ✨ 核心特性

### 🎯 **智能构建系统**
- **多模式构建**: 支持 `hybrid`、`jdk_only`、`user_only` 三种构建模式
- **多版本 JDK**: 完整支持 JDK 8/11/17/21 版本
- **智能缓存**: 自动缓存构建产物，显著提升重复构建速度
- **项目检测**: 自动识别 Maven、Gradle、Kotlin 项目类型

### 🌐 **现代化 Web 界面**
- **响应式设计**: 完美支持桌面、平板、手机访问
- **实时监控**: 构建进度、资源使用情况实时显示
- **可视化管理**: Boot JDK 版本选择、数据库压缩包管理
- **历史记录**: 完整的构建历史和状态追踪

### 🔧 **企业级功能**
- **多 Boot JDK 管理**: 支持同时管理多个 JDK 版本
- **CodeQL 自动化**: 自动下载、安装和更新 CodeQL CLI
- **数据库压缩**: 自动压缩生成的 CodeQL 数据库
- **文件上传**: 支持 JAR 文件上传和自动反编译
- **构建中断**: 支持构建过程的安全中断和恢复

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Web 管理界面 (Flask)                      │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ │
│  │   构建管理      │ │   进度监控      │ │   历史记录      │ │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    构建引擎 (Docker)                        │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ │
│  │   JDK 构建      │ │   用户代码      │ │   CodeQL 分析   │ │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    存储层                                   │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ │
│  │   源码缓存      │ │   构建缓存      │ │   数据库输出    │ │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 📁 目录结构

```
jdk-codeql-builder/
├── 🐳 Docker 配置
│   ├── Dockerfile                 # 构建环境定义
│   └── docker-compose.yml         # 容器编排配置
│
├── 📜 构建脚本
│   └── scripts/
│       ├── start.sh              # 容器启动脚本
│       ├── build-db.sh           # 核心构建脚本
│       ├── download-jdk.sh       # JDK 源码下载
│       ├── cache-manager.sh      # 缓存管理
│       ├── project-detector.sh   # 项目类型检测
│       ├── jdk-manager.sh        # Boot JDK 管理
│       └── database-manager.sh   # 数据库管理
│
├── 🌐 Web 界面
│   └── web/
│       ├── app.py                # Flask 应用主程序
│       └── templates/
│           └── index.html        # 响应式前端界面
│
└── 💾 数据目录
    └── data/
        ├── bootjdk/              # Boot JDK 存放目录
        ├── source/               # OpenJDK 源代码
        ├── user-source/          # 用户项目源码
        ├── codeql/              # CodeQL CLI 工具
        └── database/            # 数据库输出目录
            └── archives/         # 压缩包存储
```

## 🚀 快速开始

### 1️⃣ 环境准备

**系统要求:**
- Docker 20.10+
- Docker Compose 2.0+
- 8GB+ 内存 (推荐 16GB)
- 50GB+ 磁盘空间

**必需组件:**
```bash
# CodeQL CLI 自动下载
# 系统会自动检测并下载 CodeQL CLI，无需手动操作
# 如需手动下载：
wget https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-linux64.zip
unzip codeql-linux64.zip -d data/codeql/

# 准备 Boot JDK (任选一种方式)
# 方式1: 下载 tar.gz 压缩包到 data/bootjdk/ (自动解压)
# 方式2: 直接放置已解压的 JDK 目录
```

### 2️⃣ 创建目录结构

**Linux/macOS:**
```bash
mkdir -p data/{bootjdk,source,codeql,database,user-source} cache logs
```

**Windows PowerShell:**
```powershell
New-Item -ItemType Directory -Force -Path data\bootjdk, data\source, data\codeql, data\database, data\user-source, cache, logs
```

### 3️⃣ 配置项目

编辑 `docker-compose.yml` 环境变量:

```yaml
environment:
  - JDK_VERSION=17              # 目标 JDK 版本: 8, 11, 17, 21
  - JDK_FULL_VERSION=17.0.2     # 完整版本号
  - BUILD_MODE=hybrid           # 构建模式: hybrid | jdk_only | user_only
  - DB_NAME=my_codeql_db        # 输出数据库名称
  - WEB_UI_ENABLED=true         # 启用 Web 管理界面
```

### 4️⃣ 启动服务

```bash
# 构建并启动容器
docker-compose up --build

# 后台运行
docker-compose up -d --build
```

### 5️⃣ 访问 Web 界面

🌐 **访问地址**: http://localhost:8085

**主要功能:**
- 📊 **构建管理**: 选择 Boot JDK、配置构建参数
- 🔧 **CodeQL 管理**: 自动下载、安装和管理 CodeQL CLI
- 📈 **实时监控**: 查看构建进度和系统状态
- 📋 **历史记录**: 浏览构建历史和结果
- 📁 **文件管理**: 上传 JAR 文件、管理数据库压缩包

## ⚙️ 配置说明

### 构建模式详解

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| `hybrid` | 构建 JDK + 用户代码 | 完整的代码分析需求 |
| `jdk_only` | 仅构建 JDK 源码 | JDK 源码分析 |
| `user_only` | 仅构建用户代码 | 应用程序分析 |

### 环境变量配置

```yaml
# 核心配置
JDK_VERSION=17                    # JDK 主版本号
JDK_FULL_VERSION=17.0.2          # 完整版本号
BUILD_MODE=hybrid                 # 构建模式
DB_NAME=codeql_database          # 数据库名称

# Web 界面
WEB_UI_ENABLED=true              # 启用 Web 界面
TZ=Asia/Shanghai                 # 时区设置

# 高级选项
AUTO_BUILD=false                 # 自动构建
DISABLE_HOTSPOT_OS_VERSION_CHECK=ok  # 禁用版本检查
```

### 支持的项目类型

#### Maven 项目
```xml
<!-- pom.xml 示例 -->
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>my-app</artifactId>
    <version>1.0.0</version>
</project>
```

#### Gradle 项目
```gradle
// build.gradle 示例
plugins {
    id 'java'
}

group = 'com.example'
version = '1.0.0'

dependencies {
    implementation 'org.springframework:spring-core:5.3.21'
}
```

#### Kotlin 项目
```kotlin
// build.gradle.kts 示例
plugins {
    kotlin("jvm") version "1.8.10"
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib")
}
```

## 🔧 高级功能

### 智能缓存系统

缓存机制自动识别和复用构建产物:

```bash
# 查看缓存状态
docker exec jdk_codeql_builder /app/scripts/cache-manager.sh status

# 清理缓存
docker exec jdk_codeql_builder /app/scripts/cache-manager.sh clean
```

### CodeQL 管理

系统提供完整的 CodeQL CLI 自动化管理:

```bash
# 检查 CodeQL 状态
curl http://localhost:8085/api/codeql/status

# 手动触发 CodeQL 下载
curl -X POST http://localhost:8085/api/codeql/download

# 确保 CodeQL 可用（自动下载如果不存在）
curl -X POST http://localhost:8085/api/codeql/ensure
```

**自动化特性:**
- ✅ 启动时自动检测 CodeQL 是否可用
- ✅ 构建前自动下载 CodeQL CLI（如果缺失）
- ✅ Web 界面实时显示 CodeQL 状态
- ✅ 支持手动重新下载和更新

### Boot JDK 管理

支持多版本 JDK 并存:

```bash
# 列出可用的 Boot JDK
curl http://localhost:8085/api/boot-jdks

# 添加新的 Boot JDK
# 将 JDK tar.gz 文件放入 data/bootjdk/ 目录即可自动识别
```

### 数据库压缩包管理

自动压缩和管理 CodeQL 数据库:

```bash
# 查看数据库压缩包
curl http://localhost:8085/api/database-archives

# 下载数据库压缩包
curl -O http://localhost:8085/download/database/my_database.tar.gz
```

## 📊 性能优化

### 缓存效果

| 场景 | 首次构建 | 缓存构建 | 提升比例 |
|------|----------|----------|----------|
| JDK 17 完整构建 | ~45 分钟 | ~15 分钟 | 67% ⬆️ |
| 用户代码构建 | ~10 分钟 | ~3 分钟 | 70% ⬆️ |
| 混合模式构建 | ~55 分钟 | ~18 分钟 | 67% ⬆️ |

### 系统要求

| 组件 | 最低要求 | 推荐配置 |
|------|----------|----------|
| CPU | 4 核心 | 8+ 核心 |
| 内存 | 8GB | 16GB+ |
| 磁盘 | 50GB | 100GB+ SSD |
| 网络 | 10Mbps | 100Mbps+ |

## 🛠️ 故障排查

### 常见问题

#### 1. 文件上传失败
```bash
# 检查目录权限
docker exec jdk_codeql_builder ls -la /app/user-source

# 重启容器
docker-compose restart
```

#### 2. Web 界面无法访问
```bash
# 检查端口占用
netstat -an | grep 8085

# 查看容器日志
docker-compose logs jdk_codeql
```

#### 3. 构建失败
```bash
# 查看构建日志
docker exec jdk_codeql_builder tail -f /app/logs/build_*.log

# 检查 Boot JDK
docker exec jdk_codeql_builder ls -la /app/bootjdk
```

#### 5. CodeQL 相关问题
```bash
# 检查 CodeQL 安装状态
curl http://localhost:8085/api/codeql/status

# 重新下载 CodeQL CLI
curl -X POST http://localhost:8085/api/codeql/download

# 检查 CodeQL 目录权限
docker exec jdk_codeql_builder ls -la /app/codeql

# 手动验证 CodeQL 可执行性
docker exec jdk_codeql_builder /app/codeql/codeql version
```

#### 6. 内存不足
```bash
# 监控资源使用
docker stats jdk_codeql_builder

# 调整 Docker 内存限制
# 在 docker-compose.yml 中添加:
# mem_limit: 16g
```

### 日志位置

| 日志类型 | 路径 | 说明 |
|----------|------|------|
| 构建日志 | `/app/logs/build_*.log` | 构建过程详细日志 |
| Web 日志 | `/app/logs/web_ui.log` | Web 界面操作日志 |
| 系统日志 | `docker-compose logs` | 容器系统日志 |

## 🔄 版本兼容性

### JDK 版本支持

| JDK 版本 | 源码仓库 | 示例版本 | 状态 |
|----------|----------|----------|------|
| JDK 8 | `adoptium/jdk8u` | `8u111` | ✅ 完全支持 |
| JDK 11 | `openjdk/jdk11u` | `11.0.1` | ✅ 完全支持 |
| JDK 17 | `openjdk/jdk17u` | `17.0.2` | ✅ 完全支持 |
| JDK 21 | `openjdk/jdk21u` | `21.0.1` | ✅ 完全支持 |

### 构建工具版本

| 工具 | 版本 | 状态 |
|------|------|------|
| Maven | 3.6+ | ✅ 支持 |
| Gradle | 7.6 | ✅ 支持 |
| Kotlin | 1.8.10 | ✅ 支持 |
| Ant | 1.10+ | ✅ 支持 |

### 浏览器支持

| 浏览器 | 版本 | 桌面端 | 移动端 |
|--------|------|--------|--------|
| Chrome | 90+ | ✅ | ✅ |
| Firefox | 88+ | ✅ | ✅ |
| Safari | 14+ | ✅ | ✅ |
| Edge | 90+ | ✅ | ✅ |

## 🤝 贡献指南

我们欢迎所有形式的贡献！

### 开发环境搭建

```bash
# 1. Fork 项目
git clone https://github.com/your-username/jdk-codeql-builder.git

# 2. 创建开发分支
git checkout -b feature/your-feature

# 3. 安装开发依赖
pip install -r web/requirements-dev.txt

# 4. 运行测试
python -m pytest tests/
```

### 提交规范

```bash
# 功能开发
git commit -m "feat: 添加新的构建模式支持"

# 问题修复
git commit -m "fix: 修复文件上传权限问题"

# 文档更新
git commit -m "docs: 更新 API 文档"
```

### 代码规范

- **Python**: 遵循 PEP 8 规范
- **JavaScript**: 使用 ESLint 配置
- **Shell**: 遵循 ShellCheck 建议
- **Docker**: 遵循最佳实践

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

## 🙏 致谢

感谢以下项目和社区的支持:

- [GitHub CodeQL](https://github.com/github/codeql) - 强大的代码分析引擎
- [OpenJDK](https://openjdk.org/) - 开源 Java 开发工具包
- [Flask](https://flask.palletsprojects.com/) - 轻量级 Web 框架
- [Tailwind CSS](https://tailwindcss.com/) - 现代化 CSS 框架
- [Docker](https://www.docker.com/) - 容器化平台

## 📈 更新日志

### v2.2.0 (最新)
- 🆕 **CodeQL 自动下载**: 系统自动检测并下载 CodeQL CLI
- 🔧 **Web 界面增强**: 新增 CodeQL 管理界面和状态监控
- 📊 **API 扩展**: 新增 CodeQL 管理相关 API 端点
- 🚀 **构建优化**: 构建前自动确保 CodeQL 可用性
- 📝 **文档更新**: 完善 CodeQL 自动化功能说明

### v2.1.0
- 🆕 重构 README 文档结构
- 🔧 优化 Web 界面响应式设计
- 📊 增强构建性能监控
- 🐛 修复文件上传权限问题

### v2.0.0
- 🆕 全新 Web 管理界面
- 🚀 智能缓存系统
- 📱 响应式设计支持
- 🔧 多 Boot JDK 管理
- 📦 数据库压缩包管理

### v1.0.0
- 🎯 基础构建功能
- 🐳 Docker 容器化
- 📜 Shell 脚本自动化
- 🔧 多 JDK 版本支持

---

<div align="center">

**🌟 如果这个项目对您有帮助，请给我们一个 Star！**

[⭐ Star](https://github.com/your-repo/jdk-codeql-builder) | [🐛 报告问题](https://github.com/your-repo/jdk-codeql-builder/issues) | [💡 功能建议](https://github.com/your-repo/jdk-codeql-builder/discussions)

</div>