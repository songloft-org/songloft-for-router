# SongLoft - Entware 安装包

适用于刷入 [Entware](https://github.com/Entware/Entware) 的各类路由器 / NAS 设备，通过 `opkg` 包管理器安装 [SongLoft](https://github.com/songloft-org/songloft) 轻量级自建音乐库管理与串流服务。

## 版本说明

Entware 打包提供两个变体（`entware/songloft/Makefile`），二选一安装即可：

| 包名 | 说明 |
| --- | --- |
| `songloft` | 完整版，内置 Web UI（基于 Flutter Web 构建的 `songloft-player`） |
| `songloft-lite` | 精简版，不含 Web UI，体积更小，适合仅通过 API / 客户端使用的场景 |

两个包的源码均从 [songloft-org/songloft](https://github.com/songloft-org/songloft) 拉取指定版本构建，完整版还会额外下载 [songloft-org/songloft-player](https://github.com/songloft-org/songloft-player) 发布的 Web UI 资源一并打包，构建过程无需手动下载二进制文件。

## 安装方式

> 暂未提供 Entware 官方源，需自行下载编译好的 `.ipk` 安装包，通过 `opkg install` 本地安装。

1. 根据路由器 / NAS 的 CPU 架构，下载对应的 `songloft_*.ipk`（完整版）或 `songloft-lite_*.ipk`（精简版）。
2. 将 `.ipk` 文件上传到设备（如 `/opt/tmp/` 目录）。
3. 执行本地安装：

```bash
# 完整版（含 Web UI）
opkg install /opt/tmp/songloft_<版本号>_<架构>.ipk

# 或安装精简版（不含 Web UI）
opkg install /opt/tmp/songloft-lite_<版本号>_<架构>.ipk
```

若提示依赖缺失（如 `ca-bundle`），请先执行 `opkg update && opkg install ca-bundle` 补齐依赖后再重新安装。

### 手动部署二进制（不使用 ipk）

如果不方便使用 `.ipk` 安装，也可以自行前往 [songloft-org/songloft Releases](https://github.com/songloft-org/songloft/releases) 下载对应架构的 SongLoft 二进制文件，手动部署并交给 Entware 管理：

1. 下载二进制文件，重命名为 `songloft` 并放到 `PATH` 可搜索到的位置（如 `/opt/usr/bin/songloft` 或 `/opt/bin/songloft`），赋予可执行权限：`chmod +x /opt/usr/bin/songloft`。
2. 将仓库内的启动脚本 [`entware/songloft/files/S80songloft`](../../entware/songloft/files/S80songloft) 复制到 `/opt/etc/init.d/S80songloft`，并赋予可执行权限：

   ```bash
   cp entware/songloft/files/S80songloft /opt/etc/init.d/S80songloft
   chmod +x /opt/etc/init.d/S80songloft
   ```

3. 根据需要修改脚本中的 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 等环境变量，以及 `EXEHOME`（数据/工作目录，默认 `/opt/var/lib/songloft`）、`ARGS`（启动参数）等配置。
4. 执行 `/opt/etc/init.d/S80songloft start` 启动服务，此后即可交由 Entware 的 init.d 机制统一管理开机自启、启停等。

此方式与通过 `.ipk` 安装的效果一致，区别仅在于二进制文件与启动脚本需要自行下载/放置，适合需要自定义二进制版本（如使用尚未打包的最新版本）的场景。

## 配置说明

安装后会生成 init.d 启动脚本 `/opt/etc/init.d/S80songloft`，内容如下（对应仓库中的 [`entware/songloft/files/S80songloft`](../../entware/songloft/files/S80songloft)）：

- `EXEHOME`：SongLoft 的数据/工作目录，默认为 `/opt/var/lib/songloft`。
- `ADMIN_USERNAME` / `ADMIN_PASSWORD`：以环境变量方式设置管理员账号密码，默认均为 `admin`，**建议安装后尽快修改**。
- `ARGS`：额外的启动参数，默认留空，可参考 SongLoft 官方文档支持的命令行参数按需填写（如监听端口、`base-path` 等）。
- 进程通过 `start-stop-daemon` 以 `PATH` 中可搜索到的 `songloft` 二进制（如 `/opt/usr/bin/songloft`）启动。

修改上述配置后，执行 `/opt/etc/init.d/S80songloft restart` 使其生效。

### 修改管理员账号密码

无论通过 `.ipk` 安装还是手动部署，管理员账号密码均默认写死在 `/opt/etc/init.d/S80songloft` 脚本开头的环境变量中，**默认用户名/密码均为 `admin`**，为安全起见请安装后尽快修改：

```bash
vi /opt/etc/init.d/S80songloft
```

找到并修改以下两行：

```bash
export ADMIN_USERNAME=admin
export ADMIN_PASSWORD=admin
```

改为自己的账号密码后保存，执行以下命令重启服务使其生效：

```bash
/opt/etc/init.d/S80songloft restart
```

## 服务管理

```bash
# 启动
/opt/etc/init.d/S80songloft start

# 停止
/opt/etc/init.d/S80songloft stop

# 重启
/opt/etc/init.d/S80songloft restart

# 查看状态
/opt/etc/init.d/S80songloft status
```

## 升级 / 卸载

```bash
# 升级：下载新版本 .ipk 后重新本地安装即可覆盖旧版本
opkg install /opt/tmp/songloft_<新版本号>_<架构>.ipk

# 卸载
opkg remove songloft    # 或 songloft-lite
```

卸载不会自动清理数据目录 `/opt/var/lib/songloft`，如需彻底清理请手动删除。

## 常见问题

- **完整版和精简版可以共存吗？** 不建议同时安装，两者均会占用同一个二进制路径与启动脚本，请根据需要二选一。
- **服务未自动启动？** 请确认 `/opt/etc/init.d/S80songloft` 中 `ENABLED` 是否为 `yes`，并检查 Entware 的 `rc.unslung` 是否已正常拉起 init.d 脚本。
