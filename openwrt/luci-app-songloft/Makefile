# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 songloft-for-router contributors

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-songloft
PKG_VERSION:=1.0
PKG_RELEASE:=7

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=songloft-for-router contributors

LUCI_TITLE:=LuCI support for SongLoft music server
LUCI_DESCRIPTION:=Provides a web management page for SongLoft, a lightweight self-hosted music server.
# LuCI 包自带配置与启动脚本；SongLoft 二进制可由用户自行部署。
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# Preserve settings made through LuCI when the package is upgraded.
define Package/luci-app-songloft/conffiles
/etc/config/songloft
endef

# call BuildPackage - OpenWrt buildroot signature
