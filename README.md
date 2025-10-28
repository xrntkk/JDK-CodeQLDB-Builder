# CodeQL 数据库构建工具

> 本项目基于 [h3h3qaq/JDK-CodeQLDB-Builder](https://github.com/h3h3qaq/JDK-CodeQLDB-Builder) 改造，新增了使用 Ant 构建用户 Java 项目并通过 CodeQL CLI 提取数据库的方式。完全使用Claude3.5进行修改，有问题找Claude3.5解决。

本工具提供了一个基于 Docker 的环境，在同一条 CodeQL 提取命令中：先构建 OpenJDK（`configure` + `make`），随后编译你的 Java 项目（Ant）。提取器一次性拦截整个构建过程，生成单一数据库。若缺少 JDK 源码，将自动调用下载脚本获取。

## 特性

- OpenJDK 构建 + 用户项目编译，在同一条 CodeQL 命令中顺序执行（单一数据库）
- 若缺少 `source/`（OpenJDK 源码），自动调用 `scripts/download-jdk.sh` 下载
- 若存在用户源码，则在 JDK 构建完成后用 Ant 编译 `user-source/`；否则仅构建 JDK
- Docker 容器化部署，确保构建环境一致
- 无需下载/构建 OpenJDK 源码（保留原脚本但默认不使用）

> 可选：保留了“JDK 源码模式”脚本用于拉取与构建 OpenJDK 源码，并支持对版本号进行模糊匹配（详见下文）。

## 目录结构
```bash
jdk-codeql-builder/
├── Dockerfile                 # 定义构建环境的 Docker 镜像
├── docker-compose.yml         # 容器编排和数据卷挂载配置
├── scripts/                   # 构建和辅助脚本目录
│   ├── start.sh              # 容器启动脚本
│   ├── build-db.sh           # 数据库构建脚本（JDK + Ant；支持 hybrid/jdk_only/user_only）
│   ├── download-jdk.sh       # JDK 源码下载脚本
│   └── fix-time-validation.sh # 时间验证修复脚本
│
└── data/                      # 挂载到容器的数据目录
    ├── bootjdk/              # Boot JDK 存放目录
    ├── source/               # OpenJDK 源代码目录（若缺失将自动下载）
    ├── user-source/          # 用户程序源码目录（JDK 构建完成后再编译）
    │   └── lib/             # 用户程序依赖库目录
    ├── codeql/              # CodeQL CLI 工具存放目录
    └── database/            # 生成的 CodeQL 数据库输出目录
```
## 快速开始

### 1. 环境准备

- 安装 Docker 和 Docker Compose
- 下载 CodeQL CLI 工具：https://github.com/github/codeql-cli-binaries/releases
- 准备引导 JDK（用于运行 Ant/Javac）：支持两种方式放置到 `data/bootjdk/`
  - 直接将 Linux x64 的 JDK 压缩包（`.tar.gz`/`.tgz`）放入目录，脚本会自动解压并使用
  - 或者放置已解压的 JDK 目录（包含 `bin/java` 与 `bin/javac`）

### 2. 配置版本

无需手动准备 OpenJDK 源码：若 `data/source/` 为空，构建脚本会自动调用 `download-jdk.sh` 按环境变量下载。

### 3. 准备目录和文件

```bash
# 创建必要的目录
mkdir -p data/bootjdk data/source data/codeql data/database data/user-source/lib

# 放置必要文件
1. 将 CodeQL CLI 解压到 `data/codeql/` 目录
2. 将引导 JDK 的 `.tar.gz`（Linux x64）直接放入 `data/bootjdk/`，或将已解压的 JDK 目录放入该目录
3. 将要分析的 Java 程序放入 `data/user-source/`；`data/source/` 可留空（将自动下载 OpenJDK 源码）。
```

### 4. 启动构建

```bash
docker-compose up --build
```

构建完成后，数据库将生成在 `data/database/` 目录中：
- `[hybrid]`：单一数据库，包含 OpenJDK 构建（`make all`）与（可选）用户项目 Ant 编译的提取数据

## 详细说明

### 构建与提取（按模式）

容器启动后将自动执行：

1. 若 `source/` 为空：调用 `scripts/download-jdk.sh` 自动下载 JDK 源码（支持模糊匹配版本）
2. 在容器内 `/app/` 生成 `build-user.xml`（仅编译 `user-source/`；避免用 Ant 重新编译 JDK）
   - 若设置了 `CATALINA_HOME`，会将其 `lib/*.jar` 与 `bin/*.jar` 以及 `user-source/lib/*.jar` 加入 classpath
3. 调用 CodeQL CLI（将构建流程作为单一命令执行），按模式进行：
   - `hybrid`：先执行 `./configure` 与 `make all` 构建 OpenJDK，再执行 `ant -f /app/build-user.xml` 编译用户源码；一次性提取为一个数据库。
   - `jdk_only`：只执行 `./configure` 与 `make all`，不进行用户源码的 Ant 编译。
   - `user_only`：只执行 `ant -f /app/build-user.xml` 编译用户源码（需提供 Boot JDK 以使用 `javac`）。

说明：

> 注意：容器会解析 `data/bootjdk/` 中的 JDK，支持自动解压 `.tar.gz`。解析成功后将 `JAVA_HOME` 指向该 JDK，并加入 `PATH`，确保 `ant` 能调用到 `javac`。

### 环境变量（混合模式）

- `AUTO_BUILD`：是否容器启动后自动执行构建（`true`/`false`）。
- `CATALINA_HOME`：可选；设置后会把其中的 `lib/*.jar` 与 `bin/*.jar` 加入 `build.xml` 的编译类路径。
- `JDK_VERSION`/`JDK_FULL_VERSION`：当自动下载 JDK 源码时用于模糊匹配目标版本（详见下文“模糊匹配说明”）。
- `CODEQL_RUNTIME_MAJOR`：可选；指定 CodeQL CLI 运行时主版本，默认 `17`，无法找到时回退到 `11`。该变量仅影响 CodeQL 运行时，不影响用于构建 OpenJDK 的 Boot JDK。
- `BUILD_MODE`：构建模式（默认 `hybrid`）。支持：`hybrid`（先构建 JDK 再编译用户源码）、`jdk_only`（仅构建 JDK）、`user_only`（仅编译用户源码）。
- `DB_NAME`：输出数据库名称（默认 `hybrid`）。结果位于 `/app/database/<DB_NAME>`。

示例（`docker-compose.yml` 中）：
```
environment:
  - TZ=Asia/Shanghai
  - AUTO_BUILD=true
  - CATALINA_HOME=/opt/tomcat
  - CODEQL_RUNTIME_MAJOR=17
  - BUILD_MODE=hybrid
  - DB_NAME=hybrid
```

### CodeQL 运行时（JDK 17 默认）

- 容器内预装 `openjdk-17-jre-headless`，并将 CodeQL CLI 默认运行在 JDK 17；若 17 不可用则回退到 JDK 11。
- 与 Boot JDK 分离：Boot JDK（可为 8/11/17）仅用于执行 OpenJDK 的 `./configure` 与 `make`，不影响 CodeQL CLI 的 Java 运行时。
- 覆盖方式：
  - 通过环境变量 `CODEQL_RUNTIME_MAJOR` 指定目标主版本（支持 `17` 或 `11`）。
  - 或在宿主机将 JDK 目录或压缩包放入 `data/codeql-jdk/`，脚本会优先使用该目录的 JDK 作为 CodeQL 运行时。
- 自检方法（容器内）：
  - `echo $CODEQL_JAVA_HOME && $CODEQL_JAVA_HOME/bin/java -version`
  - `ls -l /app/codeql/tools/linux64/java /app/codeql/tools/linux64/javac`（应指向 JDK 17/11 的二进制，非 Boot JDK 8）。

### 系统要求

- 内存：建议至少 4GB RAM（复杂项目建议更高）
- 磁盘空间：数据库约 1-3GB 视项目规模
- 推荐使用 SSD 存储以提高构建速度


### 使用方法

1. 在 `docker-compose.yml` 中设置：
   - `AUTO_BUILD=false`（避免入口自动走 Ant 构建）。
2. 启动容器后在容器内执行：
   - `bash /app/scripts/download-jdk.sh` 下载源码
   - `bash /app/scripts/build-db.sh` 构建数据库（旧流程：构建 JDK 并用 `codeql database create --command="make images"` 提取）

### 模糊匹配说明

- 变量：
  - `JDK_VERSION`：主版本号（支持 `8`、`11`、`17`、`21`）。
  - `JDK_FULL_VERSION`：完整或部分版本号，用于模糊匹配。

- 匹配规则：
  - JDK 8：匹配 `^jdk${JDK_FULL_VERSION}(-b[0-9]+)?$`，例如：
    - `JDK_FULL_VERSION="8u111"` → 匹配 `jdk8u111-bXX`（从远端 tag 列表选择最新一个）。
  - JDK 11/17/21：匹配 `^jdk-${JDK_FULL_VERSION}(\+[0-9]+)?$`，例如：
    - `JDK_FULL_VERSION="17.0.2"` → 匹配 `jdk-17.0.2+XX`（从远端 tag 列表选择最新一个）。
    - 支持更具体的版本号：`JDK_FULL_VERSION="17.0.2+9"` → 精确匹配 `jdk-17.0.2+9`。

- 回退策略：如果模糊匹配未命中，将自动回退到对应主版本的“最新 tag”（基于远端 tag 列表排序）。

### 例子（容器内执行）

```
export JDK_VERSION=8
export JDK_FULL_VERSION="8u111"
bash /app/scripts/download-jdk.sh

export JDK_VERSION=17
export JDK_FULL_VERSION="17.0.2"
bash /app/scripts/download-jdk.sh
```

下载完成后可执行旧版构建：
```
bash /app/scripts/build-db.sh
```

> 注意：当前项目默认使用“混合模式”；若需手动控制流程，可设置 `AUTO_BUILD=false` 并在容器内显式运行脚本。

### 故障排查

1. 构建日志位置：
   - JDK 构建日志：容器内 `/app/source/build/` 目录
   - CodeQL 构建日志：直接显示在控制台

2. 常见问题：
   - 内存不足：检查 Docker 资源配额
   - 网络问题：检查 JDK 源码下载连接
   - 版本冲突：确认引导 JDK 版本是否匹配

