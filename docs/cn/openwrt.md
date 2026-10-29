# SongLoft - OpenWrt 安装包

适用于 OpenWrt 官方固件生态，提供 `songloft` / `songloft-lite` 两个软件包以及配套的 `luci-app-songloft` LuCI 图形管理界面。

> ⚠️ **暂无实体设备测试**：本项目当前没有可用的 OpenWrt 硬件设备进行实际安装验证，以下内容均基于源码（Makefile / init 脚本 / LuCI 页面）梳理得出，尚未在真实路由器上完整测试过安装、启停与 Web 管理流程。如果你在使用中发现问题，欢迎反馈。

## 版本说明

`openwrt/songloft/Makefile` 提供两个变体，二选一安装即可：

| 包名 | 说明 |
| --- | --- |
| `songloft` | 完整版，内置 Web UI（构建时会下载 [songloft-org/songloft-player](https://github.com/songloft-org/songloft-player) 发布的 Web 资源并裁剪打包） |
| `songloft-lite` | 精简版，不含 Web UI，体积更小 |

源码从 [songloft-org/songloft](https://github.com/songloft-org/songloft) 指定版本拉取构建，构建过程无需手动下载二进制文件。`luci-app-songloft` 可单独安装，程序可由用户自行部署；若使用本项目的 `songloft` 或 `songloft-lite` 软件包，启动脚本会读取 LuCI 保存的配置。

GitHub 流水线将 LuCI 与 Go 服务端分开构建：

- `luci-app-songloft` 和中文语言包 `luci-i18n-songloft-zh-cn` 均为 `all` 架构，IPK、APK 各构建一次，共发布四个通用包，文件名以 `_all.ipk` / `_all.apk` 结尾。IPK 使用 OpenWrt `24.10.8` SDK，APK 使用 `25.12.5` SDK；按固件的包管理格式选择，通用架构不代表兼容所有固件版本。
- Go 服务端 `songloft` / `songloft-lite` 使用 OpenWrt `25.12.5` SDK，为 `x86_64`、`aarch64_cortex-a53`、`aarch64_cortex-a72`、`aarch64_generic`、`arm_cortex-a7`、`arm_cortex-a9` 分别构建 APK，下载时需匹配设备架构。当前流水线不构建服务端 IPK。

## 编译方式

### 使用 feed

在 OpenWrt / ImmortalWrt 源码目录的 `feeds.conf.default` 中添加以下一行；如果已有 `feeds.conf`，则添加到该文件中：

```text
src-git --root=openwrt songloft https://github.com/songloft-org/songloft-for-router.git
```

此方式要求构建环境的 `scripts/feeds` 支持 `--root`。它会拉取完整仓库，但只扫描 `openwrt/` 子目录，避免将 `entware/songloft/Makefile` 识别为 OpenWrt 包而产生同名冲突。构建环境还需提供标准的 LuCI 和 packages/golang feed。

在固件源码根目录更新并安装 feed：

```sh
./scripts/feeds update songloft
./scripts/feeds install -p songloft luci-app-songloft songloft
make menuconfig
```

在 **LuCI → Applications** 中选择 `luci-app-songloft`。如需同时编译服务端，在 **Network** 中选择 `songloft`（内置播放器 Web UI）或 `songloft-lite`（不含播放器 Web UI），二选一；两个变体都由 `openwrt/songloft/Makefile` 定义，因此扫描日志只显示一个 `songloft` 源码包目录。

如果只需要 LuCI 管理页面，在 `.config` 或固件的配置模板中设置：

```text
CONFIG_PACKAGE_luci-app-songloft=y
# CONFIG_PACKAGE_songloft is not set
# CONFIG_PACKAGE_songloft-lite is not set
```

`luci-app-songloft` 不强制依赖 SongLoft 二进制，可以自行部署服务端。`feeds install` 仅将包源码链接加入构建目录，实际是否编译、打包由配置决定；LuCI 的依赖由 `make defconfig` 自动选中。

```sh
make defconfig
# 单独编译 LuCI 包
make package/feeds/songloft/luci-app-songloft/compile V=s
# 若已选中服务端，也可单独编译其源码包
# make package/feeds/songloft/songloft/compile V=s
# 或编译完整固件
# make -j"$(nproc)"
```

### 手动复制包目录

不支持 `--root` 的构建环境，可以将本项目的 `openwrt/songloft` 与 `openwrt/luci-app-songloft` 复制到 OpenWrt 编译环境的 `package` 目录后自行编译：

```bash
# 假设已准备好 OpenWrt SDK / 完整编译环境，位于 openwrt-src 目录
cp -r openwrt/songloft openwrt-src/package/songloft
cp -r openwrt/luci-app-songloft openwrt-src/package/luci-app-songloft

cd openwrt-src
make menuconfig   # 在 Network 分类下选中 songloft 或 songloft-lite，
                  # 在 LuCI -> Applications 下选中 luci-app-songloft
make package/songloft/compile V=s
make package/luci-app-songloft/compile V=s
```

编译完成后，将生成的软件包上传到路由器。使用 opkg 的固件通过 `opkg install <包名>.ipk` 安装；使用 apk 的固件通过 `apk add --allow-untrusted /tmp/<包名>.apk` 安装本地包。软件包格式由所用源码或 SDK 决定。

## 配置说明

- 配置文件：`/etc/config/songloft`（UCI 格式），对应仓库中的 [`openwrt/luci-app-songloft/root/etc/config/songloft`](../../openwrt/luci-app-songloft/root/etc/config/songloft)。
- 启动脚本：`/etc/init.d/songloft`（procd 管理），对应 [`openwrt/luci-app-songloft/root/etc/init.d/songloft`](../../openwrt/luci-app-songloft/root/etc/init.d/songloft)。

UCI 配置项：

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `enabled` | `0` | 是否启用服务 |
| `listen_port` | `58091` | 监听端口，对应环境变量 `LISTEN_PORT` |
| `db_path` | 空（必须自行设置） | 可写的持久化数据/工作目录 |
| `music_path` | 空（使用 `db_path/music`） | 音乐目录的绝对路径，通过环境变量 `MUSIC_DIR` 传给服务端；目录不存在时自动创建 |
| `base_path` | 空 | URL 基础路径，对应环境变量 `BASE_PATH`，用于反向代理场景 |
| `admin_username` | 空 | 管理员用户名，对应环境变量 `ADMIN_USERNAME` |
| `admin_password` | 空 | 管理员密码，对应环境变量 `ADMIN_PASSWORD` |
| `bin_path` | 空 | 自定义二进制路径，留空则使用默认路径 `/usr/bin/songloft` |
| `web_path` | 空 | 自定义 Web UI 静态资源路径，留空则使用默认路径 `/usr/share/songloft/web-embedded`（仅完整版有效） |

**首次启用前必须指定数据目录**：新安装默认不设置 `db_path`，也不会自动向 `/etc/songloft/data` 写数据。请选择空间足够、可写的持久化存储（例如已挂载的外置存储），在 LuCI「数据目录」填写其绝对路径（例如 `/mnt/storage/songloft`），再启用服务并保存配置。

音乐路径留空时，启动脚本会创建数据目录及其 `music/` 子目录；本例的音乐目录是 `/mnt/storage/songloft/music/`。如果音乐已在其他目录（如 `/mnt/storage/my-music`），直接在 LuCI「音乐路径」填写该目录的绝对路径即可，也可以使用 UCI：

```sh
uci set songloft.@songloft[0].music_path='/mnt/storage/my-music'
uci commit songloft
/etc/init.d/songloft restart
```

启动脚本会创建并使用选定的音乐目录；使用自定义路径时无需绑定挂载，也不会额外创建默认的 `music/`。清空音乐路径后，下次启动恢复为当前数据目录下的 `music/`。每次启动都会通过 `MUSIC_DIR` 设置曲库路径并覆盖服务端数据库中保存的路径。

`db_path` 是工作目录，**不要直接设为已有音乐文件夹**，否则数据库等工作数据也会写入该文件夹。确保所选存储在服务启动前已挂载，数据目录可写、音乐目录可读。手工部署二进制时，只有使用本项目的启动脚本才会读取这些 UCI 设置。

在 LuCI 页面保存配置后会自动重新加载服务；如需手动重新加载或重启服务，可执行：

```bash
/etc/init.d/songloft reload
# 或
/etc/init.d/songloft restart
```

## LuCI 管理界面

安装 `luci-app-songloft` 后，可在 LuCI 后台的 **服务（Services） -> SongLoft** 菜单中进行图形化配置与状态查看。LuCI 单独安装时会创建 `/etc/config/songloft`；页面只在配置文件存在时显示菜单项。

运行日志由 SongLoft 自身写入 `<db_path>/data/logs/`，可在 LuCI「日志」页查看。启动脚本关闭 procd 对服务 stdout 的 syslog 采集，避免访问日志重复刷入系统日志；stderr 仍写入 syslog。这不会降低文件日志等级。启动脚本自身的配置校验、启停失败仍通过 `logger -t songloft` 写入 syslog，并输出到命令行 stderr；排查时也可运行 `/etc/init.d/songloft check` 查看。更新启动脚本后需重启服务才会生效。

## 服务管理（命令行）

```bash
# 启动
/etc/init.d/songloft start

# 停止
/etc/init.d/songloft stop

# 重启
/etc/init.d/songloft restart

# 开机自启
/etc/init.d/songloft enable
```

## 卸载

```bash
opkg remove luci-app-songloft
opkg remove songloft   # 或 songloft-lite
```

卸载不会自动清理数据目录（`db_path` 指向的路径），如需彻底清理请手动删除。

## 常见问题

- **是否已在真实路由器上验证？** 尚未验证，当前仅完成源码层面的整理与自查，欢迎有 OpenWrt 设备的用户帮忙测试反馈。
- **`songloft` 和 `songloft-lite` 能否同时安装？** 不建议，两者会安装到相同的可执行文件路径与配置文件，请二选一。
