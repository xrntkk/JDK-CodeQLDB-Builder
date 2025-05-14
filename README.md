# JDK CodeQL 数据库构建工具

本工具提供了一个基于 Docker 的环境，用于为 JDK 源代码创建 CodeQL 数据库。

## 目录结构
### 前提条件
```bash
jdk-codeql-builder/
├── Dockerfile                 # 定义构建环境的 Docker 镜像
├── docker-compose.yml         # 容器编排和数据卷挂载配置
├── scripts/                   # 构建和辅助脚本目录
│   ├── start.sh               # 容器启动脚本
│   └── build-db.sh            # 数据库构建主脚本
│
└── data/                      # 挂载到容器的数据目录
    ├── bootjdk/               # Boot JDK (版本略低于待生成 CodeQL 数据库的 JDK) 存放目录
    ├── source/                # JDK 源代码存放目录
    ├── codeql/                # CodeQL CLI 工具存放目录
    └── database/              # 生成的 CodeQL 数据库输出目录
```
## 快速开始
### 1.前提条件
Docker 和 Docker Compose

JDK 源代码包 (版本略低于待生成 CodeQL 数据库的 JDK) https://github.com/openjdk/

Boot JDK (版本略低于待生成 CodeQL 数据库的 JDK) https://www.oracle.com/java/technologies/

CodeQL CLI 工具 (本项目中提供了 CodeQL CLI v2.21.2) https://github.com/github/codeql-cli-binaries/releases

运行以下命令来创建待挂载的文件夹

```bash
$ mkdir -p data/bootjdk data/source data/codeql data/database
```
执行此命令后，将在当前目录下创建 data 目录及其四个子目录
### 2.添加必需文件
将 JDK 源码解压到 data/source/ 目录

将 Boot JDK 解压到 data/bootjdk/ 目录

将 CodeQL CLI 解压到 data/codeql/ 目录

### 3.构建并启动容器
```bash
$ docker compose up
```

完成后，生成的 CodeQL 数据库将位于 data/database/ 目录中

## 文件准备
### JDK 源码
将 JDK 源代码解压到 data/source/ 目录
### Boot JDK
JDK 构建需要一个引导 JDK。通常，构建 JDK N 需要 JDK N-1 或 N 版本作为引导 (或略低于待生成数据库的 JDK 版本)。

例如：

构建 JDK 8 需要 JDK 7 或 8

构建 JDK 11 需要 JDK 10 或 11

将解压后的引导 JDK 放在 data/bootjdk/ 目录中。

### CodeQL CLI
将 CodeQL CLI 工具解压到 data/codeql/ 目录中。你可以从 GitHub 下载最新版本的 CodeQL CLI：
https://github.com/github/codeql-cli-binaries/releases

本工具使用 8u65 作为引导 JDK 去生成 8u442 的 CodeQL 数据库，可以解压所需文件的压缩包后直接 `docker compose up` 进行测试