#!/bin/sh
. /jffs/softcenter/scripts/base.sh

PID_FILE="/var/run/songloft.pid"

pid=""
running="0"

if [ -f "${PID_FILE}" ]; then
	pid="$(cat "${PID_FILE}" 2>/dev/null)"
	if [ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1; then
		running="1"
	fi
fi

if [ "${running}" != "1" ]; then
	pid="$(pidof songloft 2>/dev/null | awk '{print $1}')"
	if [ -n "${pid}" ]; then
		running="1"
	fi
fi

if [ "${running}" = "1" ]; then
	http_response "songloft 运行中, pid:${pid}"
else
	http_response "songloft 未运行"
fi
