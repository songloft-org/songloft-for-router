# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 songloft-for-router contributors

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-songloft
PKG_VERSION:=1.0
PKG_RELEASE:=2

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=songloft-for-router contributors

LUCI_TITLE:=LuCI support for SongLoft music server
LUCI_DESCRIPTION:=Provides a web management page for SongLoft, a lightweight self-hosted music server.
# SongLoft 完整版和精简版共享配置与启动脚本；不强制安装任一变体。
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
