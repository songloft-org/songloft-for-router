#!/bin/sh
source /jffs/softcenter/scripts/base.sh
alias echo_date='echo 【$(TZ=UTC-8 date "+%Y年%m月%d日 %H:%M:%S")】:'

DIR=$(cd "$(dirname "$0")"; pwd)
module=${DIR##*/}

install_now() {
	TITLE="SongLoft"
	DESCR="轻量级音乐库管理与串流服务，支持环境变量配置启动参数"
	PLVER="$(cat "${DIR}/version" 2>/dev/null)"

	if [ -f "/jffs/softcenter/scripts/${module}_config.sh" ]; then
		echo_date "安装前先停止 ${TITLE}，以保证更新成功..."
		sh /jffs/softcenter/scripts/${module}_config.sh stop >/dev/null 2>&1
	fi

	echo_date "安装插件相关文件..."
	cp -rf "${DIR}/res/"*     /jffs/softcenter/res    2>/dev/null
	cp -rf "${DIR}/scripts/"* /jffs/softcenter/scripts/
	cp -rf "${DIR}/webs/"*    /jffs/softcenter/webs
	cp -rf "${DIR}/bin/"*     /jffs/softcenter/bin/
	cp -rf "${DIR}/uninstall.sh" "/jffs/softcenter/scripts/uninstall_${module}.sh"
    mkdir -p /jffs/softcenter/${module}

	chmod 755 /jffs/softcenter/bin/${module}          >/dev/null 2>&1
	chmod 755 /jffs/softcenter/scripts/${module}_*.sh >/dev/null 2>&1

	echo_date "设置插件默认参数..."
	dbus set ${module}_version="${PLVER}"
	dbus set softcenter_module_${module}_version="${PLVER}"
	dbus set softcenter_module_${module}_install="1"
	dbus set softcenter_module_${module}_name="${module}"
	dbus set softcenter_module_${module}_title="${TITLE}"
	dbus set softcenter_module_${module}_description="${DESCR}"

	# 初始化默认配置，不覆盖用户已有配置
	[ -z "$(dbus get ${module}_enable 2>/dev/null)" ]           && dbus set ${module}_enable="0"
	[ -z "$(dbus get ${module}_listen_port 2>/dev/null)" ]      && dbus set ${module}_listen_port="58091"
	[ -z "$(dbus get ${module}_db_path 2>/dev/null)" ]          && dbus set ${module}_db_path="/jffs/softcenter/${module}"
	[ -z "$(dbus get ${module}_base_path 2>/dev/null)" ]        && dbus set ${module}_base_path=""
	[ -z "$(dbus get ${module}_admin_username 2>/dev/null)" ]   && dbus set ${module}_admin_username=""
	[ -z "$(dbus get ${module}_admin_password 2>/dev/null)" ]   && dbus set ${module}_admin_password=""
	[ -z "$(dbus get ${module}_bin_path 2>/dev/null)" ]         && dbus set ${module}_bin_path=""

	echo_date "安装完毕！"

	# 若已启用则自动启动
	if [ "$(dbus get ${module}_enable 2>/dev/null)" = "1" ]; then
		echo_date "检测到已启用，尝试启动 ${TITLE}..."
		sh /jffs/softcenter/scripts/${module}_config.sh start >/dev/null 2>&1
	fi
}

install_now
rm -rf "/tmp/${module}"* >/dev/null 2>&1
exit 0
