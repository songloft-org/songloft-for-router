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
	e.running = luci.sys.call("pgrep -f '/usr/bin/songloft' >/dev/null") == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
