# songloft-for-router

本仓库提供面向家庭场景的路由器与光猫部署方案，由于路由器与光猫是家庭中常见的基础网络设备，天然支持 24 小时不间断运行，非常适合用于部署 [SongLoft](https://github.com/songloft-org/songloft)（轻量级自建音乐库管理与串流服务），帮助用户轻松部署 SongLoft 服务。项目覆盖 OpenWrt、Entware 与梅林（Merlin，含 SWRTdev / Koolshare 软件中心）三类主流路由器固件生态。

## 项目结构

- `openwrt/`：OpenWrt 官方包管理格式，包含 `songloft`（含 `songloft-lite` 无 Web UI 变体）以及配套的 `luci-app-songloft` LuCI 管理界面
- `entware/`：Entware 包管理格式，适用于安装 Entware 的各类路由器/NAS/光猫
- `merlin/`：梅林第三方固件离线安装包，包含 `songloft-SWRT`（SWRTdev 软件中心）与 `songloft-koolshare`（Koolshare 软件中心）两个版本
- `docs/`：使用文档

## 安装文档

- [梅林（Merlin）安装与使用文档](docs/cn/merlin.md)
- [Entware 安装与使用文档](docs/cn/entware.md)
- [OpenWrt 安装与使用文档](docs/cn/openwrt.md)（⚠️ 暂无设备测试）

## 部署建议

对于内存资源有限的嵌入式设备（路由器/光猫），建议部署 **lite 版本**（不含内置 Web UI），运行时内存占用约 **27 MB**，非常适合资源受限的设备。

lite 版本需要单独部署 Web 客户端（前端），可选方案：

- **Flutter 客户端**（iOS / Android / macOS / Windows / Linux）：直接连接 SongLoft 服务，无需在路由器上部署前端，推荐大多数用户使用。
- **网页版客户端**：如需在浏览器中访问，可将 [songloft-player](https://github.com/songloft-org/songloft-player) 前端静态文件部署到路由器上，搭配轻量级静态文件服务器 [darkhttpd](https://github.com/emikulic/darkhttpd) 提供服务。`darkhttpd` 是一个开箱即用的静态文件 HTTP 服务器，单一二进制、无需安装配置；采用事件循环单线程模型，内存占用仅几十 KB；利用 `sendfile()` 零拷贝加速文件传输，支持断点续传（Range 请求）和 Keep-Alive，非常适合在路由器等嵌入式设备上托管前端静态文件。

## 关于 SongLoft

SongLoft 是一个使用 Go 编写的轻量级自建音乐库管理与串流服务，支持本地音乐管理、网络歌曲、电台及歌单等功能。更多信息请参考官方仓库：[songloft-org/songloft](https://github.com/songloft-org/songloft)。
