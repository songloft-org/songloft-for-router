#!/bin/sh
# Host-only unit tests. No live LuCI, OpenWrt services or config writes.
# Usage: sh test/run.sh [repository-root]
# Required: Lua 5.1 (or LuaJIT), Node.js >= 18, Bash >= 4.
# Override interpreters with LUA, NODE and BASH_BIN if needed.
set -eu

if [ "$#" -gt 1 ]; then
	printf 'Usage: %s [repository-root]\n' "$0" >&2
	exit 2
fi

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${1:-$test_dir/..}" && pwd)
if [ ! -f "$root/openwrt/luci-app-songloft/Makefile" ]; then
	printf 'SongLoft LuCI package not found under %s\n' "$root" >&2
	exit 2
fi

if [ -z "${LUA:-}" ]; then
	for candidate in lua5.1 luajit lua; do
		if command -v "$candidate" >/dev/null 2>&1 &&
			"$candidate" -e 'assert(_VERSION == "Lua 5.1")' >/dev/null 2>&1; then
			LUA=$candidate
			break
		fi
	done
fi
LUA=${LUA:-lua}
NODE=${NODE:-node}
BASH_BIN=${BASH_BIN:-bash}
for interpreter in "$LUA" "$NODE" "$BASH_BIN"; do
	if ! command -v "$interpreter" >/dev/null 2>&1; then
		printf 'Missing interpreter: %s\n' "$interpreter" >&2
		exit 2
	fi
done
"$LUA" -e 'assert(_VERSION == "Lua 5.1", "Lua 5.1 or LuaJIT required")'
"$NODE" -e 'if (Number(process.versions.node.split(".")[0]) < 18) { console.error("Node.js >= 18 required"); process.exit(2); }'
"$BASH_BIN" -c 'if (( BASH_VERSINFO[0] < 4 )); then printf "Bash >= 4 required\n" >&2; exit 2; fi'

printf '\n== Controller and latest-log API ==\n'
"$LUA" "$test_dir/songloft-controller.test.lua" "$root"
printf '\n== CBI model and apply callback ==\n'
"$LUA" "$test_dir/songloft-cbi.test.lua" "$root"
printf '\n== LuCI status and log views ==\n'
SONGLOFT_TEST_ROOT="$root" "$NODE" --test "$test_dir/songloft-views.test.cjs"
printf '\n== Merlin music directory and startup environment ==\n'
SONGLOFT_TEST_ROOT="$root" "$NODE" --test "$test_dir/songloft-merlin.test.cjs"
printf '\n== Init script and apply registration ==\n'
"$BASH_BIN" -n "$test_dir/songloft-init.test.sh"
"$BASH_BIN" "$test_dir/songloft-init.test.sh" "$root"
printf '\nAll SongLoft test suites passed.\n'
