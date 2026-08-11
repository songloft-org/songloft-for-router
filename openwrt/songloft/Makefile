# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 songloft-for-router contributors

include $(TOPDIR)/rules.mk

PKG_NAME:=songloft
PKG_VERSION:=2.11.3
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=cf3e19842080ab62444ffa2a594ca5b4ccc65248
PKG_SOURCE_URL:=https://github.com/songloft-org/songloft.git
PKG_MIRROR_HASH:=skip

PKG_SOURCE_SUBMODULES:=pkg/tag

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=songloft-for-router contributors

PKG_BUILD_PARALLEL:=1
PKG_BUILD_DEPENDS:=golang/host

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(BUILD_VARIANT)/$(PKG_NAME)-$(PKG_VERSION)

SONGLOFT_WEB_SOURCE:=songloft-web-embedded-v$(PKG_VERSION).tar.gz
SONGLOFT_WEB_URL:=https://github.com/songloft-org/songloft-player/releases/download/v$(PKG_VERSION)
SONGLOFT_WEB_URL_FILE:=songloft-web-embedded.tar.gz
SONGLOFT_WEB_HASH:=skip

PKG_SOURCE_VERSION_SHORT:=$(shell echo $(PKG_SOURCE_VERSION) | cut -c1-7)
PKG_BUILD_TIME:=$(shell TZ=Asia/Shanghai date '+%Y-%m-%d_%H:%M:%S')

GO_PKG:=songloft
GO_PKG_BUILD_PKG:=songloft

GO_PKG_LDFLAGS_X:= \
	songloft/internal/version.Version=$(PKG_VERSION) \
	songloft/internal/version.GitCommit=$(PKG_SOURCE_VERSION_SHORT) \
	songloft/internal/version.BuildTime=$(PKG_BUILD_TIME) \
	songloft/internal/version.BuildType=$(BUILD_VARIANT)

ifeq ($(BUILD_VARIANT),lite)
  GO_PKG_TAGS:=lite
endif

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/songloft/Default
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A lightweight self-hosted music server
  URL:=https://github.com/songloft-org/songloft
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/songloft-lite
  $(call Package/songloft/Default)
  TITLE:=A lightweight self-hosted music server (no web UI)
  VARIANT:=lite
  DEFAULT_VARIANT:=1
endef

define Package/songloft-lite/description
  Songloft is a lightweight self-hosted music server written in Go.
  It supports local music management, network songs, radio stations
  and playlist features. This package is the lite version without
  the embedded web UI.
endef

define Package/songloft
  $(call Package/songloft/Default)
  VARIANT:=full
endef

define Package/songloft/description
  Songloft is a lightweight self-hosted music server written in Go.
  It supports local music management, network songs, radio stations
  and playlist features. This package includes the embedded web UI.
endef

define Download/songloft-web
  FILE:=$(SONGLOFT_WEB_SOURCE)
  URL:=$(SONGLOFT_WEB_URL)
  URL_FILE:=$(SONGLOFT_WEB_URL_FILE)
  HASH:=$(SONGLOFT_WEB_HASH)
endef
$(eval $(call Download,songloft-web))

define Build/Prepare
	$(call Build/Prepare/Default)
ifeq ($(BUILD_VARIANT),full)
	mkdir -p $(PKG_BUILD_DIR)/songloft-player-build/web-embedded
	tar -xzf $(DL_DIR)/$(SONGLOFT_WEB_SOURCE) -C $(PKG_BUILD_DIR)/songloft-player-build/web-embedded
	# 清理未使用的 canvaskit 渲染器变体（仅保留 canvaskit 本体）
	rm -f  $(PKG_BUILD_DIR)/songloft-player-build/web-embedded/canvaskit/skwasm* \
	       $(PKG_BUILD_DIR)/songloft-player-build/web-embedded/canvaskit/wimp* \
	       $(PKG_BUILD_DIR)/songloft-player-build/web-embedded/canvaskit/*.symbols
	rm -rf $(PKG_BUILD_DIR)/songloft-player-build/web-embedded/canvaskit/chromium
	# 移除 NotoSansSC OTF（8MB eager loading），CanvasKit 已有 woff2 分片按需加载
	rm -f  $(PKG_BUILD_DIR)/songloft-player-build/web-embedded/assets/fonts/NotoSansSC-Regular.otf
	# 从 FontManifest.json 移除 NotoSansSC 条目，避免 Flutter 尝试加载已删除的文件
	python3 -c "\
import json; \
p='$(PKG_BUILD_DIR)/songloft-player-build/web-embedded/assets/FontManifest.json'; \
d=json.load(open(p)); \
json.dump([e for e in d if e.get('family')!='NotoSansSC'],open(p,'w'))" 2>/dev/null || true
	# 同步清理 Service Worker RESOURCES map，移除已删除文件的条目（避免 404 缓存请求）
	python3 -c "\
import json,os,re; \
d='$(PKG_BUILD_DIR)/songloft-player-build/web-embedded'; \
p=d+'/flutter_service_worker.js'; \
c=open(p).read(); \
m=re.search(r'const RESOURCES = (\{.*?\});',c,re.DOTALL); \
r=json.loads(m.group(1)) if m else {}; \
cl={k:v for k,v in r.items() if k=='/' or os.path.exists(d+'/'+k)}; \
open(p,'w').write(c[:m.start(1)]+json.dumps(cl)+c[m.end(1):]) if m and len(cl)!=len(r) else None" 2>/dev/null || true
endif
endef

define Package/songloft-lite/conffiles
/etc/config/songloft
endef

define Package/songloft/conffiles
/etc/config/songloft
endef

define Package/songloft-lite/install
	$(call GoPackage/Package/Install/Bin,$(1))
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/songloft.init $(1)/etc/init.d/songloft
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/songloft.config $(1)/etc/config/songloft
endef

define Package/songloft/install
	$(call Package/songloft-lite/install,$(1))
	$(INSTALL_DIR) $(1)/usr/share/songloft/web-embedded
	$(CP) $(PKG_BUILD_DIR)/songloft-player-build/web-embedded/. $(1)/usr/share/songloft/web-embedded/
endef

$(eval $(call BuildPackage,songloft-lite))
$(eval $(call BuildPackage,songloft))
