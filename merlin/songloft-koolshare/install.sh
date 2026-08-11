#!/bin/sh
source /koolshare/scripts/base.sh
alias echo_date='echo 【$(TZ=UTC-8 date "+%Y年%m月%d日 %H:%M:%S")】:'

DIR=$(cd "$(dirname "$0")"; pwd)
module=${DIR##*/}

install_now() {
	TITLE="SongLoft"
	DESCR="轻量级音乐库管理与串流服务，支持环境变量配置启动参数"
	PLVER="$(cat "${DIR}/version" 2>/dev/null)"

	if [ -f "/koolshare/scripts/${module}_config.sh" ]; then
		echo_date "安装前先停止 ${TITLE}，以保证更新成功..."
		sh /koolshare/scripts/${module}_config.sh stop >/dev/null 2>&1
	fi

	echo_date "安装插件相关文件..."
	cp -rf "${DIR}/res/"*     /koolshare/res    2>/dev/null
	cp -rf "${DIR}/scripts/"* /koolshare/scripts/
	cp -rf "${DIR}/webs/"*    /koolshare/webs
	cp -rf "${DIR}/bin/"*     /koolshare/bin/
	cp -rf "${DIR}/uninstall.sh" "/koolshare/scripts/uninstall_${module}.sh"
    mkdir -p /koolshare/${module}

	chmod 755 /koolshare/bin/${module}          >/dev/null 2>&1
	chmod 755 /koolshare/scripts/${module}_*.sh >/dev/null 2>&1

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
	[ -z "$(dbus get ${module}_db_path 2>/dev/null)" ]          && dbus set ${module}_db_path="/koolshare/${module}"
	[ -z "$(dbus get ${module}_base_path 2>/dev/null)" ]        && dbus set ${module}_base_path=""
	[ -z "$(dbus get ${module}_admin_username 2>/dev/null)" ]   && dbus set ${module}_admin_username=""
	[ -z "$(dbus get ${module}_admin_password 2>/dev/null)" ]   && dbus set ${module}_admin_password=""
	[ -z "$(dbus get ${module}_bin_path 2>/dev/null)" ]         && dbus set ${module}_bin_path=""

	echo_date "安装完毕！"

	# 若已启用则自动启动
	if [ "$(dbus get ${module}_enable 2>/dev/null)" = "1" ]; then
		echo_date "检测到已启用，尝试启动 ${TITLE}..."
		sh /koolshare/scripts/${module}_config.sh start >/dev/null 2>&1
	fi
}

install_now
rm -rf "/tmp/${module}"* >/dev/null 2>&1
exit 0
