# DM8 Docker

达梦数据库 DM8 Docker 镜像，基于 Debian 12 slim 构建。

## 目录结构

```
├── Dockerfile        # 多阶段构建：安装 + 运行
├── build.sh          # 一键构建脚本
├── entrypoint.sh     # 容器入口脚本（初始化 + 启动）
├── dm_install.xml    # DM8 静默安装配置
├── dm8_*.zip         # 达梦安装包（需自行下载）
└── DMInstall.bin     # 解压后的安装程序（自动生成）
```

## 环境要求

- Docker (推荐 colima 或 Docker Desktop)
- Apple Silicon 用户需启用 Rosetta：`colima start --arch x86_64 --vz-rosetta`

## 构建

### 自动构建（推荐）

```bash
# 将 dm8_*.zip 放在项目目录，一键构建
./build.sh

# 脚本会自动完成：解压 zip → 提取 DMInstall.bin → 构建镜像
# 镜像名自动从 zip 文件名获取：liuys36/dm8:<zip_文件名>
```

### 更新版本

```bash
# 只需替换 dm8_*.zip 文件，重新构建即可
./build.sh
```

### 管理容器

```bash
./build.sh run                # 启动容器（默认密码 DMdba_123）
SYSDBA_PWD=MyPwd_123 ./build.sh run  # 指定密码启动
./build.sh stop               # 停止并删除容器
./build.sh clean              # 删除 DMInstall.bin
```

### 手动构建

```bash
# 从 zip 中提取安装程序
unzip dm8_20260427_x86_rh7_64.zip
# 从 ISO 中提取 DMInstall.bin（需要 7z / xorriso / isoinfo）

# 构建镜像
docker buildx build --platform linux/amd64 --load -t dm8:dm8_20260427_x86_rh7_64 .
```

## 使用

### 基本启动

```bash
./build.sh run
# 或指定密码：SYSDBA_PWD=YourPwd_123 ./build.sh run
```

### 持久化数据

```bash
docker run -d --name dm8 \
  -p 5236:5236 \
  -v /host/data/path:/opt/dmdbms/data \
  -e SYSDBA_PWD=YourPwd_123 \
  liuys36/dm8:dm8_20260427_x86_rh7_64
```

### 自定义数据目录路径

```bash
docker run -d --name dm8 \
  -p 5236:5236 \
  -v /host/data/path:/dmdata \
  -e DATA_DIR=/dmdata \
  -e SYSDBA_PWD=YourPwd_123 \
  liuys36/dm8:dm8_20260427_x86_rh7_64
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
| `LOG_SIZE` | `50` | 日志文件大小（MB） |
| `CHARSET` | `1` | 字符集（0=GB18030, 1=UTF-8, 2=EUC-KR） |
| `CASE_SENSITIVE` | `Y` | 大小写敏感（Y/N） |
| `BUFFER` | `8000` | 系统缓冲区大小（MB） |
| `TIME_ZONE` | `+08:00` | 时区 |
| `BLANK_PAD_MODE` | `0` | 空格填充模式（0=不填充, 1=填充） |
| `PAGE_CHECK` | `3` | 页校验模式（0=无, 1=CRC32, 2=SHA256, 3=全校验） |
| `AUTO_OVERWRITE` | `0` | 是否覆盖已有数据库（0=不覆盖, 1=覆盖） |
| `USE_DB_NAME` | `1` | 是否使用库名作为数据子目录 |
| `VARCHAR_TYPE` | — | VARCHAR 长度单位（0=字节, 1=字符），留空则不设置，dminit 后自动写入 dm.ini |
| `DATA_DIR` | `/opt/dmdbms/data` | 数据目录路径 |
| `INIT_SCRIPTS_DIR` | `/init-scripts` | 初始化 SQL 脚本目录，首次启动时按文件名顺序执行 |

所有变量通过 `docker run -e KEY=VALUE` 指定，仅首次初始化生效。

## 初始化脚本

将 SQL 脚本挂载到 `INIT_SCRIPTS_DIR`（默认 `/init-scripts`），将在数据库首次初始化完成后按文件名顺序自动执行：

```bash
docker run -v /path/to/scripts:/init-scripts liuys36/dm8:dm8_20260427_x86_rh7_64
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

- **Stage 1 (builder)**: 安装 DM8 到 `/opt/dmdbms`，清理 doc/desktop/samples/uninstall/include/drivers/jdk
- **Stage 2 (runtime)**: 仅复制 DM8 二进制和运行时库，最终镜像约 **165MB**
- **入口点**: `entrypoint.sh` → `dminit` 初始化 → [init SQL 脚本] → `dmap` → `dmserver`

## License

License 有效期至 2027-04-14，随 DM8 安装包自带。
