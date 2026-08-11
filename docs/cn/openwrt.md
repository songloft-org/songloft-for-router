# SongLoft - OpenWrt 安装包

适用于 OpenWrt 官方固件生态，提供 `songloft` / `songloft-lite` 两个软件包以及配套的 `luci-app-songloft` LuCI 图形管理界面。

> ⚠️ **暂无实体设备测试**：本项目当前没有可用的 OpenWrt 硬件设备进行实际安装验证，以下内容均基于源码（Makefile / init 脚本 / LuCI 页面）梳理得出，尚未在真实路由器上完整测试过安装、启停与 Web 管理流程。如果你在使用中发现问题，欢迎反馈。

## 版本说明

`openwrt/songloft/Makefile` 提供两个变体，二选一安装即可：

| 包名 | 说明 |
| --- | --- |
| `songloft` | 完整版，内置 Web UI（构建时会下载 [songloft-org/songloft-player](https://github.com/songloft-org/songloft-player) 发布的 Web 资源并裁剪打包） |
| `songloft-lite` | 精简版，不含 Web UI，体积更小 |

源码从 [songloft-org/songloft](https://github.com/songloft-org/songloft) 指定 commit 拉取构建，构建过程无需手动下载二进制文件；`luci-app-songloft` 依赖 `songloft` 包（`LUCI_DEPENDS:=+songloft`），因此若只安装 `songloft-lite` 也可以正常配合使用，但请注意二者当前均需要自行编译（尚未提供官方 / 第三方 opkg 源）。

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
| `db_path` | `/etc/songloft/data` | 数据/工作目录 |
| `base_path` | 空 | URL 基础路径，对应环境变量 `BASE_PATH`，用于反向代理场景 |
| `admin_username` | 空 | 管理员用户名，对应环境变量 `ADMIN_USERNAME` |
| `admin_password` | 空 | 管理员密码，对应环境变量 `ADMIN_PASSWORD` |
| `bin_path` | 空 | 自定义二进制路径，留空则使用默认路径 `/usr/bin/songloft` |
| `web_path` | 空 | 自定义 Web UI 静态资源路径，留空则使用默认路径 `/usr/share/songloft/web-embedded`（仅完整版有效） |

修改配置后可通过 LuCI 页面保存，或使用 `uci` 命令行工具编辑，然后执行：

```bash
/etc/init.d/songloft reload
# 或
/etc/init.d/songloft restart
```

## LuCI 管理界面

安装 `luci-app-songloft` 后，可在 LuCI 后台的 **服务（Services） -> SongLoft** 菜单中进行图形化配置与状态查看（页面仅在 `/etc/config/songloft` 存在时显示菜单项）。

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
