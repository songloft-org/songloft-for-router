#!/bin/sh
. /jffs/softcenter/scripts/base.sh

alias echo_date='echo [$(TZ=UTC-8 date "+%Y-%m-%d %H:%M:%S")]:'

ACTION="$1"

MODULE="songloft"
DEFAULT_BIN="/jffs/softcenter/bin/songloft"
PID_FILE="/var/run/songloft.pid"
LOG_FILE="/tmp/upload/songloft.log"
LOCK_DIR="/var/lock/${MODULE}_lock"

acquire_lock() {
	if mkdir "${LOCK_DIR}" >/dev/null 2>&1; then
		echo "$$" >"${LOCK_DIR}/pid" 2>/dev/null
		return 0
	fi
	return 1
}

release_lock() {
	rm -rf "${LOCK_DIR}" >/dev/null 2>&1
}

lock_or_exit() {
	if acquire_lock; then
		trap 'release_lock' EXIT
		return 0
	fi
	# api call: return json so frontend won't hang
	if [ -n "$2" ]; then
		http_response "{\"ok\":0,\"msg\":\"busy\"}"
	fi
	exit 0
}

lock_or_exit "$@"

# 获取实际使用的二进制路径：优先使用用户自定义路径，否则使用默认路径
get_bin_path() {
	if [ -n "${songloft_bin_path}" ] && [ "${songloft_bin_path}" != "null" ]; then
		echo "${songloft_bin_path}"
	else
		echo "${DEFAULT_BIN}"
	fi
}

is_running() {
	if [ -f "${PID_FILE}" ]; then
		pid="$(cat "${PID_FILE}" 2>/dev/null)"
		[ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1 && return 0
	fi
	return 1
}

stop_proc() {
	if [ -f "${PID_FILE}" ]; then
		start-stop-daemon -K -q -p "${PID_FILE}" >/dev/null 2>&1
		rm -f "${PID_FILE}" >/dev/null 2>&1
	fi
	# fallback
	pidof songloft >/dev/null 2>&1 && killall songloft >/dev/null 2>&1
}

nat_start_link() {
	if [ "$(dbus get songloft_enable 2>/dev/null)" = "1" ]; then
		[ ! -L "/jffs/softcenter/init.d/N99SongLoft.sh" ] && \
			ln -sf /jffs/softcenter/scripts/songloft_config.sh \
			       /jffs/softcenter/init.d/N99SongLoft.sh
	else
		[ -L "/jffs/softcenter/init.d/N99SongLoft.sh" ] && \
			rm -f /jffs/softcenter/init.d/N99SongLoft.sh >/dev/null 2>&1
	fi
}

clear_log() {
	: >"${LOG_FILE}"
	http_response "{\"ok\":1}"
}

trim_log() {
	[ ! -f "${LOG_FILE}" ] && http_response "{\"ok\":1}" && return 0
	lines="$(wc -l < "${LOG_FILE}" 2>/dev/null)"
	case "${lines}" in
		''|*[!0-9]*)
			http_response "{\"ok\":1}"
			return 0
			;;
	esac
	if [ "${lines}" -gt 500 ]; then
		tmp="${LOG_FILE}.tmp"
		tail -n 10 "${LOG_FILE}" >"${tmp}" 2>/dev/null
		cat "${tmp}" >"${LOG_FILE}" 2>/dev/null
		rm -f "${tmp}" >/dev/null 2>&1
	fi
	http_response "{\"ok\":1}"
}

start_songloft() {
	eval "$(dbus export songloft_)"
	mkdir -p /tmp/upload >/dev/null 2>&1

	if [ "${songloft_enable}" != "1" ]; then
		stop_proc
		nat_start_link
		return 0
	fi

	# 确定二进制路径
	BIN="$(get_bin_path)"

	if [ ! -x "${BIN}" ]; then
		echo_date "未找到可执行文件：${BIN}" >>"${LOG_FILE}"
		return 1
	fi

	# 停止旧进程
	stop_proc

	# 直接 export dbus 变量
	export LISTEN_PORT="${songloft_listen_port:-58091}"
	export ADMIN_USERNAME="${songloft_admin_username}"
	export ADMIN_PASSWORD="${songloft_admin_password}"
	export BASE_PATH="${songloft_base_path}"

	# cd 到数据根目录，songloft 以当前目录作为工作目录
	_work_dir="${songloft_db_path:-/jffs/softcenter/songloft}"
	mkdir -p "${_work_dir}" >/dev/null 2>&1
	cd "${_work_dir}" || { echo_date "无法进入目录：${_work_dir}" >>"${LOG_FILE}"; return 1; }

	echo_date "启动 SongLoft..." >>"${LOG_FILE}"
	echo_date "执行：cd ${_work_dir} && ${BIN}" >>"${LOG_FILE}"

	nohup "${BIN}" >>"${LOG_FILE}" 2>&1 &
	echo $! >"${PID_FILE}"
	sleep 2

	if is_running; then
		echo_date "SongLoft 已启动（pid=$(cat "${PID_FILE}" 2>/dev/null)，端口：${LISTEN_PORT}）" >>"${LOG_FILE}"
	else
		echo_date "SongLoft 启动失败，请查看日志排查。" >>"${LOG_FILE}"
		nat_start_link
		return 1
	fi

	nat_start_link
	return 0
}

stop_songloft() {
	stop_proc
	nat_start_link
	echo_date "SongLoft 已停止。" >>"${LOG_FILE}"
}

start_nat() {
	[ "${songloft_enable}" != "1" ] && return 0
	if ! is_running; then
		start_songloft
	fi
}

case "$ACTION" in
	start)
		start_songloft
		;;
	stop)
		stop_songloft
		;;
	restart)
		stop_songloft
		start_songloft
		;;
	start_nat)
		start_nat
		;;
esac

http_response "$1"

case "$2" in
	1)
		# apply from web (dbus values already written by httpdb)
		start_songloft
		;;
	2)
		stop_songloft
		;;
	3)
		clear_log
		;;
	4)
		trim_log
		;;
esac
