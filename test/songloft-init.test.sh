#!/usr/bin/env bash
# Bash 4+ init-function logic tests. Run: bash test/songloft-init.test.sh [project-root]
# Source the production init directly: this does NOT exercise rc.common,
# procd JSON serialization, flock, real processes, or a device's apply lifecycle.
# All state changes are in memory. mkdir/logger/RPC/sleep are mocked; the
# executable fixture is inspected, never executed. PID $$ is only read via /proc.

if (( BASH_VERSINFO[0] < 4 )); then
	printf 'Bash 4 or newer is required.\n' >&2
	exit 2
fi
if (( $# > 1 )); then
	printf 'Usage: bash %s [project-root]\n' "$0" >&2
	exit 2
fi
ROOT=$(cd -- "${1:-${BASH_SOURCE[0]%/*}/..}" && pwd -P) || exit 2
PACKAGE="$ROOT/openwrt/luci-app-songloft"
INIT="$PACKAGE/root/etc/init.d/songloft"
[[ -r "$INIT" && -f /bin/sh && -s /bin/sh && -x /bin/sh ]] || {
	printf 'Production init or /bin/sh fixture is unavailable.\n' >&2
	exit 2
}
DB_FIXTURE=/tmp
[[ -d "$DB_FIXTURE" && -w "$DB_FIXTURE" && -x "$DB_FIXTURE" ]] || DB_FIXTURE="$ROOT"
[[ -w "$DB_FIXTURE" && -x "$DB_FIXTURE" ]] || exit 2

declare -A CONFIG INSTANCES
SECTION_IDS=(cfg000001 cfg000002 cfg000003)
A=songloft.cfg000001
B=songloft.cfg000002
C=songloft.cfg000003

assert_equal() {
	if [[ "$2" != "$3" ]]; then
		printf 'Assertion failed: %s\n  expected: <%s>\n  actual:   <%s>\n' "$1" "$2" "$3" >&2
		exit 1
	fi
}
assert_present() {
	[[ ${INSTANCES[$1]+present} ]] || { printf 'Missing instance: %s\n' "$1" >&2; exit 1; }
}
assert_absent() {
	[[ ! ${INSTANCES[$1]+present} ]] || { printf 'Unexpected instance: %s\n' "$1" >&2; exit 1; }
}
invoke() {
	local expected="$1" before actual
	shift
	before=$(declare -p CONFIG)
	"$@"
	actual=$?
	assert_equal "exit status of $*" "$expected" "$actual"
	assert_equal "operation must not mutate UCI: $*" "$before" "$(declare -p CONFIG)"
}

reset_state() {
	CONFIG=()
	INSTANCES=()
	local section
	for section in "${SECTION_IDS[@]}"; do
		CONFIG[$section.TYPE]=songloft
		CONFIG[$section.enabled]=0
		CONFIG[$section.db_path]="$DB_FIXTURE"
		CONFIG[$section.bin_path]=/bin/sh
		CONFIG[$section.listen_port]=58091
	done
	CONFIG[cfg000001.enabled]=1
	REGISTERED=1
	CREATED=()
	DELETED=()
	START_CALLS=0
	CLOCK=0
	SLEEP_CALLS=0
	MKDIR_FAILURE=0
	UBUS_FAILURE=0
	START_FAILURE=0
	STOP_FAILURE=0
	NEVER_RUNNING=0
	LIVE_PID=0
	LOGS=()
	START_NOW=0
	CHECK_ONLY=0
	START_RESULT=0
	EXPECTED_INSTANCES=''
}

# UCI has no write API in these mocks. invoke() additionally checks that every
# production operation leaves the complete configuration snapshot unchanged.
config_load() { assert_equal 'config_load package' songloft "$1"; }
config_get() {
	local mock_value="${CONFIG[$2.$3]-${4-}}"
	printf -v "$1" '%s' "$mock_value"
}
config_get_bool() { config_get "$@"; }
config_foreach() {
	local callback="$1" type="$2" section
	shift 2
	for section in "${SECTION_IDS[@]}"; do
		[[ ${CONFIG[$section.TYPE]-} == "$type" ]] || continue
		"$callback" "$section" "$@"
	done
	return 0
}
logger() { LOGS+=("$*"); }
mkdir() { return "$MKDIR_FAILURE"; }
sleep() {
	case "$1" in 1|0.1) ;; *) printf 'Unexpected sleep: %s\n' "$1" >&2; exit 1 ;; esac
	SLEEP_CALLS=$((SLEEP_CALLS + 1))
	CLOCK=$((CLOCK + 1))
	# Guard against accidental infinite waits without ever sleeping for real.
	(( SLEEP_CALLS <= 100 )) || { printf 'Mock wait budget exceeded.\n' >&2; exit 1; }
}
date() { assert_equal 'fake date arguments' +%s "$*"; printf '%s\n' "$CLOCK"; }
procd_open_instance() { CREATED+=("$1"); }
procd_set_param() { :; }
procd_append_param() { :; }
procd_close_instance() { :; }
service_running() { [[ ${INSTANCES[$1]-0} == 1 ]]; }

# Deliberately simplified start/stop adapters, NOT copies of rc.common. A
# target start merges one instance; a full start replaces the registered set.
start() {
	START_CALLS=$((START_CALLS + 1))
	(( START_FAILURE == 0 )) || return "$START_FAILURE"
	CREATED=()
	start_service "${1-}"
	[[ -n ${1-} ]] || INSTANCES=()
	local instance
	for instance in "${CREATED[@]}"; do
		INSTANCES[$instance]=$((1 - NEVER_RUNNING))
	done
	REGISTERED=1
	service_started
}
stop() {
	(( STOP_FAILURE == 0 )) || return "$STOP_FAILURE"
	if [[ -n ${1-} ]]; then
		DELETED+=("$1")
		unset 'INSTANCES[$1]'
	else
		DELETED+=(ALL)
		INSTANCES=()
		REGISTERED=0
	fi
}
ubus() {
	assert_equal 'ubus request' 'call service list {"name":"songloft"}' "$*"
	(( UBUS_FAILURE == 0 )) || return "$UBUS_FAILURE"
	if (( REGISTERED )); then
		printf '{"songloft":{"instances":{}}}\n'
	else
		printf '{}\n'
	fi
}
jsonfilter() {
	local selector="${2-}" input instance
	# Consume the pipeline. The memory map supplies selected instance data;
	# this does not claim to test the real jsonfilter parser or JSON schema.
	while IFS= read -r input; do :; done
	assert_equal 'jsonfilter mode' -e "$1"
	case "$selector" in
		@.songloft.instances.*.pid|@.songloft.instances\[\"*\"\].pid)
			# No PID matches is a legitimate nonzero jsonfilter result.
			(( LIVE_PID )) || return 1
			printf '%s\n' "$$"
			;;
		@.songloft.instances\[\"*\"\])
			instance=${selector#*instances[\"}
			instance=${instance%\"]}
			[[ ${INSTANCES[$instance]+present} ]] || return 1
			printf '{}\n'
			;;
		*) printf 'Unexpected selector: %s\n' "$selector" >&2; exit 1 ;;
	esac
}

normal_enabled() { invoke 0 start; assert_equal 'enabled instances only' "$A" "${CREATED[*]}"; }
normal_disabled() { CONFIG[cfg000001.enabled]=0; invoke 0 start; assert_equal 'no instances' 0 "${#CREATED[@]}"; }
temporary_start() {
	INSTANCES[$A]=1
	invoke 0 start_now cfg000002
	assert_equal 'target only' "$B" "${CREATED[*]}"
	assert_present "$A"; assert_present "$B"; assert_absent "$C"
}
temporary_enabled() { invoke 0 start_now cfg000001; assert_equal 'target only' "$A" "${CREATED[*]}"; }
reload_stopped() { INSTANCES[$B]=1; invoke 0 reload_service; assert_present "$A"; assert_absent "$B"; assert_equal 'full delete' ALL "${DELETED[*]}"; }
reload_absent() { REGISTERED=0; invoke 0 reload_service; assert_present "$A"; assert_equal 'no unnecessary delete' 0 "${#DELETED[@]}"; }
reload_empty() { invoke 0 reload_service; assert_present "$A"; assert_equal 'empty service deleted' ALL "${DELETED[*]}"; }
reload_crashed() { INSTANCES[$A]=0; invoke 0 reload_service; assert_equal 'crashed instance restarted' 1 "${INSTANCES[$A]}"; }
reload_disabled() {
	CONFIG[cfg000001.enabled]=0; INSTANCES[$B]=1
	invoke 0 reload_service
	assert_equal 'all instances removed' 0 "${#INSTANCES[@]}"
	assert_equal 'disabled service deleted' ALL "${DELETED[*]}"
}
stop_target() {
	INSTANCES[$A]=1; INSTANCES[$B]=1
	invoke 0 stop_now cfg000002
	assert_present "$A"; assert_absent "$B"
	assert_equal 'target delete only' "$B" "${DELETED[*]}"
}
stop_crashed() { INSTANCES[$B]=0; invoke 0 stop_now cfg000002; assert_absent "$B"; assert_equal 'crashed state deleted' "$B" "${DELETED[*]}"; }
stop_missing_target() { INSTANCES[$A]=1; invoke 0 stop_now cfg000002; assert_present "$A"; assert_equal 'no deletion' 0 "${#DELETED[@]}"; }
stop_absent() { REGISTERED=0; invoke 0 stop_now; assert_equal 'no deletion' 0 "${#DELETED[@]}"; }
stop_empty() { invoke 0 stop_now; assert_equal 'empty service deleted' ALL "${DELETED[*]}"; }
restart_target() {
	INSTANCES[$A]=1; INSTANCES[$B]=1
	invoke 0 restart_now cfg000002
	assert_present "$A"; assert_present "$B"
	assert_equal 'target delete only' "$B" "${DELETED[*]}"
	assert_equal 'target start only' "$B" "${CREATED[*]}"
}
invalid_before_restart() {
	CONFIG[cfg000001.$1]="$2"; INSTANCES[$A]=1
	invoke 1 restart_now cfg000001
	assert_equal 'precheck did not stop' 0 "${#DELETED[@]}"
	assert_equal 'precheck did not start' 0 "$START_CALLS"
	assert_present "$A"
}
invalid_section() { invoke 1 start_now 'bad-name'; assert_equal 'no start' 0 "$START_CALLS"; }
missing_section() { invoke 1 restart_now missing; assert_equal 'no deletion' 0 "${#DELETED[@]}"; }
wrong_type() { CONFIG[cfg000001.TYPE]=other; invoke 1 restart_now cfg000001; assert_equal 'no deletion' 0 "${#DELETED[@]}"; }
normal_failure() { CONFIG[cfg000001.bin_path]="$ROOT/test/nonexistent-songloft-fixture"; invoke 1 start; }
mkdir_failure() { MKDIR_FAILURE=1; invalid_before_restart db_path "$DB_FIXTURE"; }
reload_invalid() { CONFIG[cfg000001.listen_port]=0; INSTANCES[$B]=1; invoke 1 reload_service; assert_present "$B"; assert_equal 'no deletion' 0 "${#DELETED[@]}"; }
start_failure() { START_FAILURE=7; invoke 1 start_now cfg000001; assert_equal 'no instances' 0 "${#INSTANCES[@]}"; }
stop_failure() { STOP_FAILURE=7; INSTANCES[$A]=1; invoke 1 restart_now cfg000001; assert_present "$A"; assert_equal 'no start after failure' 0 "$START_CALLS"; }
start_timeout() { NEVER_RUNNING=1; invoke 1 start_now cfg000001; assert_equal 'deterministic startup timeout' 9 "$SLEEP_CALLS"; }
stop_timeout() {
	[[ -d /proc/$$ ]] || { printf '/proc is required for timeout fixture.\n' >&2; exit 1; }
	LIVE_PID=1; INSTANCES[$A]=1
	invoke 1 restart_now cfg000001
	assert_equal 'deterministic stop timeout' 60 "$SLEEP_CALLS"
	assert_equal 'restart blocked' 0 "$START_CALLS"
}
ubus_failure() { UBUS_FAILURE=7; invoke 1 stop_now; assert_equal 'no deletion' 0 "${#DELETED[@]}"; }

static_integration() {
	local json defaults cbi init_text registration_pattern
	json=$(<"$PACKAGE/root/usr/share/ucitrack/luci-app-songloft.json")
	# Permit formatting whitespace outside strings, preserving command spaces.
	# This intentionally checks one exact object, not a general JSON parser.
	registration_pattern='^[[:space:]]*\{[[:space:]]*"config"[[:space:]]*:[[:space:]]*"songloft"[[:space:]]*,[[:space:]]*"exec"[[:space:]]*:[[:space:]]*"/bin/sh /etc/rc.common /etc/init.d/songloft reload"[[:space:]]*\}[[:space:]]*$'
	[[ "$json" =~ $registration_pattern ]] || {
		printf 'Unexpected ucitrack registration: %s\n' "$json" >&2; exit 1;
	}
	defaults=$(<"$PACKAGE/root/etc/uci-defaults/90-songloft")
	[[ "$defaults" == *'/etc/init.d/songloft enable || exit 1'* &&
		"$defaults" == *'/etc/init.d/ucitrack enable || exit 1'* &&
		"$defaults" == *'/etc/init.d/ucitrack reload || exit 1'* ]] || {
		printf 'Missing boot/ucitrack registration commands in defaults.\n' >&2; exit 1;
	}
	cbi=$(<"$PACKAGE/luasrc/model/cbi/songloft.lua")
	[[ "$cbi" != *apply_on_parse* ]] || {
		printf 'Unexpected forced CBI apply flow.\n' >&2; exit 1;
	}
	# A no-delta reconciliation callback is permitted: it does not duplicate
	# ucitrack for committed changes. This is a static guard, not Lua execution.
	if [[ "$cbi" == *luci.sys.call* || "$cbi" == *on_after_commit* ]]; then
		[[ "$cbi" == *'map.uci:changes("songloft")'* &&
			"$cbi" == *'if type(changes) == "table" and not next(changes.songloft or {}) then'* ]] || {
			printf 'CBI reload callback lacks the no-delta guard.\n' >&2; exit 1;
		}
	fi
	init_text=$(<"$INIT")
	[[ "$init_text" != *'service_triggers()'* && "$init_text" != *procd_add_reload_trigger* ]] || {
		printf 'Unexpected duplicate init config trigger.\n' >&2; exit 1;
	}
}

PASSED=0
FAILED=0
run_case() {
	local name="$1"
	shift
	# Each case has a fresh shell state, including production globals.
	if (
		reset_state
		# shellcheck source=/dev/null
		source "$INIT" || exit 1
		"$@"
	); then
		printf 'PASS %s\n' "$name"
		PASSED=$((PASSED + 1))
	else
		printf 'FAIL %s\n' "$name" >&2
		FAILED=$((FAILED + 1))
	fi
}

run_case 'normal/boot start gates enabled instances' normal_enabled
run_case 'normal start with all sections disabled' normal_disabled
run_case 'temporary start targets disabled section without UCI changes' temporary_start
run_case 'temporary start of enabled section' temporary_enabled
run_case 'reload starts manually stopped enabled section and stops disabled' reload_stopped
run_case 'reload starts completely unregistered service' reload_absent
run_case 'reload deletes empty no-PID registered service' reload_empty
run_case 'reload restarts crashed no-PID instance' reload_crashed
run_case 'reload stops all-disabled service' reload_disabled
run_case 'stop targets one instance and preserves another' stop_target
run_case 'stop removes crashed no-PID instance' stop_crashed
run_case 'stop ignores absent target' stop_missing_target
run_case 'stop ignores absent service' stop_absent
run_case 'stop deletes empty registered service' stop_empty
run_case 'temporary restart targets one instance without UCI changes' restart_target
run_case 'reject invalid section identifier' invalid_section
run_case 'reject missing section' missing_section
run_case 'reject wrong section type' wrong_type
run_case 'binary precheck preserves running instance' invalid_before_restart bin_path "$ROOT/test/nonexistent-songloft-fixture"
run_case 'directory binary rejected before stopping' invalid_before_restart bin_path "$DB_FIXTURE"
run_case 'relative path rejected before stopping' invalid_before_restart db_path relative
run_case 'root path rejected before stopping' invalid_before_restart db_path /
run_case 'empty path rejected before stopping' invalid_before_restart db_path ''
run_case 'nonnumeric port rejected before stopping' invalid_before_restart listen_port abc
run_case 'zero port rejected before stopping' invalid_before_restart listen_port 0
run_case 'out-of-range port rejected before stopping' invalid_before_restart listen_port 65536
run_case 'empty port rejected before stopping' invalid_before_restart listen_port ''
run_case 'normal startup validation failure propagates' normal_failure
run_case 'mkdir failure preserves running instance' mkdir_failure
run_case 'reload precheck preserves running instance' reload_invalid
run_case 'start adapter failure propagates' start_failure
run_case 'stop adapter failure prevents restart' stop_failure
run_case 'startup wait times out without real sleep' start_timeout
run_case 'stop wait times out without signals or real sleep' stop_timeout
run_case 'ubus failure prevents deletion' ubus_failure
run_case 'ucitrack/defaults registration and no duplicate callbacks (static)' static_integration

printf '\nResult: %d passed, %d failed, %d total\n' "$PASSED" "$FAILED" "$((PASSED + FAILED))"
(( FAILED == 0 ))
