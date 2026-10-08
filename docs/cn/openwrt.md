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

## 编译方式

由于暂无官方源，需要将本项目的 `openwrt/songloft` 与 `openwrt/luci-app-songloft` 加入 OpenWrt 编译环境的 `package` 目录后自行编译：

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

编译完成后，将生成的 `.ipk` 上传到路由器，通过 `opkg install <包名>.ipk` 安装。

## 配置说明

- 配置文件：`/etc/config/songloft`（UCI 格式），对应仓库中的 [`openwrt/songloft/files/songloft.config`](../../openwrt/songloft/files/songloft.config)。
- 启动脚本：`/etc/init.d/songloft`（procd 管理），对应 [`openwrt/songloft/files/songloft.init`](../../openwrt/songloft/files/songloft.init)。

UCI 配置项：

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `enabled` | `0` | 是否启用服务 |
| `listen_port` | `58091` | 监听端口，对应环境变量 `LISTEN_PORT` |
| `db_path` | 空（必须自行设置） | 可写的持久化数据/工作目录；音乐文件从该目录下的 `music/` 子目录读取 |
| `base_path` | 空 | URL 基础路径，对应环境变量 `BASE_PATH`，用于反向代理场景 |
| `admin_username` | 空 | 管理员用户名，对应环境变量 `ADMIN_USERNAME` |
| `admin_password` | 空 | 管理员密码，对应环境变量 `ADMIN_PASSWORD` |
| `bin_path` | 空 | 自定义二进制路径，留空则使用默认路径 `/usr/bin/songloft` |
| `web_path` | 空 | 自定义 Web UI 静态资源路径，留空则使用默认路径 `/usr/share/songloft/web-embedded`（仅完整版有效） |

**首次启用前必须指定数据目录**：新安装默认不设置 `db_path`，也不会自动向 `/etc/songloft/data` 写数据。请选择空间足够、可写的持久化存储（例如已挂载的外置存储），在 LuCI「数据目录」填写其绝对路径（例如 `/mnt/storage/songloft`），再启用服务并保存配置。

启动脚本会创建指定目录及其 `music/` 子目录；本例的音乐目录是 `/mnt/storage/songloft/music/`。将音乐文件放入该子目录即可。如果音乐已在其他目录（如 `/mnt/storage/my-music`），可在启动前将其绑定挂载到 `music/`；挂载需在每次启动 SongLoft 前完成，重启设备后也要重新挂载，不要只执行一次：

```sh
mkdir -p /mnt/storage/songloft/music
mount --bind /mnt/storage/my-music /mnt/storage/songloft/music
```

`db_path` 是工作目录，**不要直接设为已有音乐文件夹**，否则数据库等工作数据也会写入该文件夹。确保所选存储在服务启动前已挂载且可写；`web_path` 指网页静态资源目录，不是音乐目录。手工部署二进制时，只有使用本项目的启动脚本才会读取这些 UCI 设置。

在 LuCI 页面保存配置后会自动重新加载服务；如需手动重新加载或重启服务，可执行：

```bash
/etc/init.d/songloft reload
# 或
/etc/init.d/songloft restart
```

## LuCI 管理界面

安装 `luci-app-songloft` 后，可在 LuCI 后台的 **服务（Services） -> SongLoft** 菜单中进行图形化配置与状态查看。LuCI 单独安装时会创建 `/etc/config/songloft`；页面只在配置文件存在时显示菜单项。

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
