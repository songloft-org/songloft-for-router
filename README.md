# songloft-for-router

本仓库提供面向家庭场景的路由器与光猫部署方案，由于路由器与光猫是家庭中常见的基础网络设备，天然支持 24 小时不间断运行，非常适合用于部署 [SongLoft](https://github.com/songloft-org/songloft)（轻量级自建音乐库管理与串流服务），帮助用户轻松部署 SongLoft 服务。项目覆盖 OpenWrt、Entware 与梅林（Merlin，含 SWRTdev / Koolshare 软件中心）三类主流路由器固件生态。

## 项目结构

- `openwrt/`：OpenWrt 官方包管理格式，包含 `songloft`（含 `songloft-lite` 无 Web UI 变体）以及配套的 `luci-app-songloft` LuCI 管理界面
- `entware/`：Entware 包管理格式，适用于安装 Entware 的各类路由器/NAS/光猫
- `merlin/`：梅林第三方固件离线安装包，包含 `songloft-SWRT`（SWRTdev 软件中心）与 `songloft-koolshare`（Koolshare 软件中心）两个版本
- `docs/`：使用文档
- `script/`：维护脚本

## 更新打包版本

运行以下脚本，自动查找 SongLoft 最新稳定版本标签，并同步更新 Entware 和 OpenWrt 的服务端版本、源码 SHA256、`pkg/tag` 子模块固定提交及 SHA256、同版本内嵌 Web 资源 SHA256：

```sh
./script/update-version.py
# 指定版本会强制下载检查，即使当前版本相同：
./script/update-version.py 2.13.2
# 下载 Web 压缩包，额外验证 GitHub 提供的 SHA256：
./script/update-version.py 2.13.2 --verify-web
```

不传版本号时，仅先查询最新稳定版本标签；如果 Entware 和 OpenWrt 当前版本均与其一致，就直接退出，不再查询子模块、Web 资源或下载校验源码。显式传入版本号才会强制检查同版本，单独使用 `--verify-web` 不会绕过跳过逻辑。

需要 Python 3.6+、curl 和 GitHub 网络访问；可通过 `GITHUB_TOKEN` 提高 API 限额。源码与子模块均从 codeload 压缩包下载，不使用 Git 拉取。Web 资源优先使用 GitHub 发布资产的 SHA256，未提供时自动下载计算；构建时 SDK 会校验资源。脚本在所有下载和校验成功后才写入两个 Makefile，升级版本时将 `PKG_RELEASE` 重置为 `1`；强制检查同版本会保留打包修订号。对应版本的 Web 发布资源必须已上传。

GitHub Actions 的 `Check upstream and build router packages` 每天北京时间 08:23 自动检查一次，也可在 Actions 页面点击 **Run workflow** 手动检查。发现更新后会自动提交两个 Makefile、创建 `entware-版本号` 和 `openwrt-版本号` 标签，并直接调用对应的编译工作流，无需额外配置 PAT。手动推送这两类标签仍会触发编译。

新版本先创建草稿 Release，等该平台全部构建及上传成功后才正式发布，并删除该平台较旧版本的 Release（含附件）及对应标签，OpenWrt、Entware 各保留一个最新成功版本。失败构建保留草稿与上一成功版本，下次检查自动重试；Merlin 发布不参与清理。定时工作流需存在于默认分支，仓库规则须允许 `GITHUB_TOKEN` 写入版本提交、标签和 Release。

维护脚本的本地测试：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 test/update-version.test.py
PYTHONDONTWRITEBYTECODE=1 python3 test/prune-releases.test.py
```

## 安装文档

发布包可从以下 GitHub Releases 下载：

| 固件生态 | 发布包 | 安装与使用文档 |
| --- | --- | --- |
| OpenWrt | [下载 OpenWrt 发布包](https://github.com/songloft-org/songloft-for-router/releases?q=openwrt) | [OpenWrt 安装与使用文档](docs/cn/openwrt.md) |
| Entware | [下载 Entware 发布包](https://github.com/songloft-org/songloft-for-router/releases?q=entware) | [Entware 安装与使用文档](docs/cn/entware.md) |
| 梅林（Merlin） | [下载 Merlin 发布包](https://github.com/songloft-org/songloft-for-router/releases?q=merlin) | [梅林（Merlin）安装与使用文档](docs/cn/merlin.md)（⚠️ 只在 SWRT 下测试通过） |

## 部署建议

对于内存资源有限的嵌入式设备（路由器/光猫），建议部署 **lite 版本**（不含内置 Web UI），运行时内存占用约 **27 MB**，非常适合资源受限的设备。

lite 版本需要单独部署 Web 客户端（前端），可选方案：

- **Flutter 客户端**（iOS / Android / macOS / Windows / Linux）：直接连接 SongLoft 服务，无需在路由器上部署前端，推荐大多数用户使用。
- **网页版客户端**：如需在浏览器中访问，可将 [songloft-player](https://github.com/songloft-org/songloft-player) 前端静态文件部署到路由器上，搭配轻量级静态文件服务器 [darkhttpd](https://github.com/emikulic/darkhttpd) 提供服务。`darkhttpd` 是一个开箱即用的静态文件 HTTP 服务器，单一二进制、无需安装配置；采用事件循环单线程模型，内存占用仅几十 KB；利用 `sendfile()` 零拷贝加速文件传输，支持断点续传（Range 请求）和 Keep-Alive，非常适合在路由器等嵌入式设备上托管前端静态文件。

## 关于 SongLoft

SongLoft 是一个使用 Go 编写的轻量级自建音乐库管理与串流服务，支持本地音乐管理、网络歌曲、电台及歌单等功能。更多信息请参考官方仓库：[songloft-org/songloft](https://github.com/songloft-org/songloft)。
