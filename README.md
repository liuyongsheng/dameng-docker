# DM8 Docker

达梦数据库 DM8 Docker 镜像，基于 Debian 12 slim 构建，支持 AMD64 和 ARM64 双平台。

## 目录结构

```
├── Dockerfile        # 多阶段构建：安装 + 运行
├── build.sh          # 一键构建脚本（双平台支持）
├── entrypoint.sh     # 容器入口脚本（初始化 + 启动）
├── dm_install.xml    # DM8 静默安装配置
├── dm8_*x86*.zip     # 达梦 x86 安装包
├── dm8_*arm*.zip     # 达梦 ARM64 安装包
└── .cache/           # 缓存目录（解压后的 DMInstall-*.bin，自动生成）
```

## 环境要求

- Docker (推荐 colima 或 Docker Desktop)
- Docker BuildKit（默认已启用）
- 解压工具：p7zip / xorriso / isoinfo（任一即可）
  ```bash
  brew install p7zip    # macOS 推荐
  ```

## 双平台构建

### 下载安装包

1. **AMD64** — 从 [达梦官网下载](https://www.dameng.com) 或 [达梦技术社区](https://eco.dameng.com/download/) 下载 X86 版本（文件名含 `x86`）
2. **ARM64** — 同样从达梦官方下载，选择 ARM 版本（文件名含 `arm`，如 `dm8_20260417_HWarm920_kylin10_sp1_64.zip`）

将下载的 `dm8_*.zip` 放入项目目录，脚本通过文件名自动识别架构：

```bash
# 查看当前可识别的 zip
ls dm8_*.zip
```

```bash
# 自动识别并构建（仅一个 zip 时）
./build.sh

# 指定架构
./build.sh --arch amd64
./build.sh --arch arm64

# 两个架构同时构建
./build.sh --all
```

镜像标签：
- `liuys36/dameng:8-amd64` — AMD64 (本地构建和推送均一致)
- `liuys36/dameng:8-arm64` — ARM64 (本地构建和推送均一致)
- `liuys36/dameng:8-slim` — Multi-arch manifest（推送时自动创建）

## 推送 Multi-arch Manifest

将双架构镜像推送到 registry，统一通过 `liuys36/dameng:8-slim` 对外暴露：

```bash
# 构建 + 推送一键完成
./build.sh --all --push

# 本地已有镜像，只推送不打镜像
./build.sh push

# 镜像已在 registry，只创建 manifest
./build.sh manifest

# 单架构推送
./build.sh --arch arm64 --push
```

实现原理：
1. 分别构建并推送 `liuys36/dameng:8-amd64` 和 `liuys36/dameng:8-arm64` 到 registry
2. 创建 multi-arch manifest `liuys36/dameng:8-slim`，指向两个架构
3. 用户 `docker pull liuys36/dameng:8-slim` 时 Docker 自动匹配架构

### 缓存说明

首次解压后，DMInstall.bin 缓存到 `.cache/` 目录，后续构建跳过解压步骤。如需重新解压请先执行 `./build.sh clean`。

## 使用

### 基本启动

```bash
docker run -d --name dm8 \
  -p 5236:5236 \
  -e SYSDBA_PWD=DMdba_123 \
  liuys36/dameng:8-slim
```

### 持久化数据

```bash
docker run -d --name dm8 \
  -p 5236:5236 \
  -v /host/data/path:/opt/dmdbms/data \
  -e SYSDBA_PWD=YourPwd_123 \
  liuys36/dameng:8-slim
```

### 自定义数据目录路径

```bash
docker run -d --name dm8 \
  -p 5236:5236 \
  -v /host/data/path:/dmdata \
  -e DATA_DIR=/dmdata \
  -e SYSDBA_PWD=YourPwd_123 \
  liuys36/dameng:8-slim
```

### 连接测试

```bash
docker exec dm8 /opt/dmdbms/bin/disql SYSDBA/YourPwd_123@localhost:5236
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SYSDBA_PWD` | `DMdba_123` | SYSDBA 密码 |
| `SYSAUDITOR_PWD` | `DMAuditor_123` | SYSAUDITOR 密码 |
| `DB_NAME` | `DAMENG` | 数据库名 |
| `INSTANCE_NAME` | `DMSERVER` | 实例名 |
| `PORT_NUM` | `5236` | 端口号 |
| `PAGE_SIZE` | `8` | 页大小（KB） |
| `EXTENT_SIZE` | `16` | 簇大小（页数） |
| `LOG_SIZE` | `256` | 日志文件大小（MB），最小 256，最大 8192 |
| `CHARSET` | `1` | 字符集（0=GB18030, 1=UTF-8, 2=EUC-KR） |
| `CASE_SENSITIVE` | `Y` | 大小写敏感（Y/N） |
| `BUFFER` | `1024` | 数据缓冲区大小（MB） |
| `TIME_ZONE` | `+08:00` | 时区 |
| `BLANK_PAD_MODE` | `0` | 空格填充模式（0=不填充, 1=填充） |
| `PAGE_CHECK` | `3` | 页校验模式（0=无, 1=CRC32, 2=SHA256, 3=全校验） |
| `AUTO_OVERWRITE` | `0` | 是否覆盖已有数据库（0=不覆盖, 1=覆盖） |
| `USE_DB_NAME` | `1` | 是否使用库名作为数据子目录 |
| `VARCHAR_TYPE` | — | VARCHAR 长度单位（0=字节, 1=字符），留空则不设置，dminit 后自动写入 dm.ini |
| `ENABLE_FLASHBACK` | `1` | 启用闪回功能（1=开启, 0=关闭），开启后在 dm.ini 写入 `ENABLE_FLASH = 1` |
| `DATA_DIR` | `/opt/dmdbms/data` | 数据目录路径 |
| `INIT_SCRIPTS_DIR` | `/init-scripts` | 初始化 SQL 脚本目录，首次启动时按文件名顺序执行 |

所有变量通过 `docker run -e KEY=VALUE` 指定，仅首次初始化生效。

## 构建来源

镜像包含 `dm8.zip` label，记录构建时使用的安装包文件名：

```bash
docker inspect --format '{{.Config.Labels.dm8.zip}}' liuys36/dameng:8-arm64
# dm8_20260417_HWarm920_kylin10_sp1_64.zip
```

## 初始化脚本

将 SQL 脚本挂载到 `INIT_SCRIPTS_DIR`（默认 `/init-scripts`），将在数据库首次初始化完成后按文件名顺序自动执行：

```bash
docker run -v /path/to/scripts:/init-scripts liuys36/dameng:8-slim
```

示例脚本结构：
```
scripts/
├── 01_create_user.sql       # CREATE USER ...
├── 02_create_tables.sql     # CREATE TABLE ...
└── 03_seed_data.sql         # INSERT ...
```

流程：`dminit` → 临时启动 dmserver → 执行 SQL 脚本 → 停止临时 dmserver → 正式启动 dmserver。

## 镜像结构

- **Stage 1 (builder)**: 根据 `TARGETARCH` 选择对应架构的 DMInstall.bin，安装 DM8 到 `/opt/dmdbms`，清理 doc/desktop/samples/uninstall/include/drivers/jdk
- **Stage 2 (runtime)**: 仅复制 DM8 二进制和运行时库，最终镜像约 **165MB**
- **入口点**: `entrypoint.sh` → `dminit` 初始化 → [init SQL 脚本] → `dmap` → `dmserver`
- **双平台**: build.sh 自动从 zip 文件名识别架构，构建时复制对应 DMInstall.bin 到构建上下文；`--push` 模式自动创建 multi-arch manifest

## License

License 有效期至 2027-04-14，随 DM8 安装包自带。
