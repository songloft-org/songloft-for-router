module("luci.controller.songloft", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/songloft") then
		return
	end

	entry({"admin", "services", "songloft"}, cbi("songloft"), _("SongLoft"), 60).dependent = true
	entry({"admin", "services", "songloft", "status"}, call("act_status")).leaf = true
	entry({"admin", "services", "songloft", "action"}, post("act_action")).leaf = true
end

local function service_status()
	local result = require("luci.util").ubus("service", "list", { name = "songloft" })
	if type(result) ~= "table" then
		return { error = "service_unavailable" }
	end

	local instances = (result.songloft or {}).instances or {}
	local e = { running = false, active = next(instances) ~= nil }
	for _, instance in pairs(instances) do
		if instance.running then
			e.running = true
			break
		end
	end

	local uci = require("luci.model.uci").cursor()
	e.port = uci:get_first("songloft", "songloft", "listen_port") or "58091"
	e.base_path = uci:get_first("songloft", "songloft", "base_path") or ""
	return e
end

function act_status()
	luci.http.prepare_content("application/json")
	luci.http.write_json(service_status())
end

function act_action()
	local action = luci.http.formvalue("action")
	if action ~= "start" and action ~= "stop" and action ~= "restart" then
		luci.http.status(400, "Bad Request")
		luci.http.prepare_content("application/json")
		luci.http.write_json({ success = false, error = "invalid_action" })
		return
	end

	-- Only allow fixed init-script actions. The POST dispatcher validates CSRF.
	local code = luci.sys.call("/etc/init.d/songloft " .. action .. " >/dev/null 2>&1")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ success = code == 0, status = service_status() })
end
