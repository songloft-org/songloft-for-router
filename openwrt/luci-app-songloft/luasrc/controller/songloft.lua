module("luci.controller.songloft", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/songloft") then
		return
	end

	entry({"admin", "services", "songloft"}, cbi("songloft"), _("SongLoft"), 60).dependent = true
	entry({"admin", "services", "songloft", "status"}, call("act_status")).leaf = true
end

function act_status()
	local e = {}
	-- Let rc.common/procd report the actual service instance. The executable path
	-- is configurable, so matching a hard-coded default binary path is unreliable.
	e.running = luci.sys.call("/etc/init.d/songloft running >/dev/null 2>&1") == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
