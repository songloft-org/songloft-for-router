module("luci.controller.songloft", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/songloft") then
		return
	end

	entry({"admin", "services", "songloft"}, cbi("songloft"), _("SongLoft"), 60).dependent = true
	entry({"admin", "services", "songloft", "status"}, call("act_status")).leaf = true
	entry({"admin", "services", "songloft", "log"}, call("act_log")).leaf = true
	entry({"admin", "services", "songloft", "action"}, post("act_action")).leaf = true
end

local function service_status()
	local result = require("luci.util").ubus("service", "list", { name = "songloft" })
	if type(result) ~= "table" then
		return { error = "service_unavailable" }
	end

	local instances = (result.songloft or {}).instances or {}
	local status = { sections = {} }
	local uci = require("luci.model.uci").cursor()
	uci:foreach("songloft", "songloft", function(section)
		local instance = instances["songloft." .. section[".name"]] or {}
		status.sections[section[".name"]] = {
			enabled = section.enabled == "1",
			running = instance.running == true,
			active = next(instance) ~= nil,
			pids = instance.running and instance.pid and { instance.pid } or {},
			port = section.listen_port or "58091",
			base_path = section.base_path or ""
		}
	end)
	return status
end

function act_status()
	luci.http.prepare_content("application/json")
	luci.http.write_json(service_status())
end

local function latest_log(section)
	local fs = require "nixio.fs"
	local nx = require "nixio"
	local uci = require("luci.model.uci").cursor()
	if type(section) ~= "string" or not section:match("^[A-Za-z0-9_]+$") or
		uci:get("songloft", section) ~= "songloft" then
		return { error = "invalid_section" }
	end

	local base = uci:get("songloft", section, "db_path")
	if type(base) ~= "string" or not base:match("^/[^/]") or base:find("%c") then
		return { error = "data_directory_missing" }
	end
	local directory = base:gsub("/+$", "") .. "/data/logs"
	local result = { directory = directory }
	if fs.stat(directory, "type") ~= "dir" then
		result.error = "log_directory_missing"
		return result
	end
	local entries = fs.dir(directory)
	if not entries then
		result.error = "log_directory_unreadable"
		return result
	end

	local newest, metadata
	-- Names are opaque: no date parsing, prefix or extension filtering.
	-- Ignore directories, devices and symlinks; only read regular files.
	for name in entries do
		local stat = fs.lstat(directory .. "/" .. name)
		if stat and stat.type == "reg" and (not metadata or stat.mtime > metadata.mtime) then
			newest, metadata = name, stat
		end
	end
	if not newest then
		result.error = "no_logs"
		return result
	end

	local fd = nx.open(directory .. "/" .. newest, nx.open_flags("rdonly", "nonblock"))
	if not fd then
		result.error = "log_read_failed"
		return result
	end
	local stat = fd:stat()
	-- Recheck the opened file in case it was replaced during rotation.
	if not stat or stat.type ~= "reg" or stat.dev ~= metadata.dev or stat.ino ~= metadata.ino then
		fd:close()
		result.error = "log_read_failed"
		return result
	end
	local limit = 128 * 1024
	local offset = math.max(0, stat.size - limit)
	if not fd:seek(offset, "set") then
		fd:close()
		result.error = "log_read_failed"
		return result
	end
	local chunks, remaining = {}, math.min(stat.size, limit)
	while remaining > 0 do
		local chunk = fd:read(math.min(remaining, 8192))
		if not chunk then
			fd:close()
			result.error = "log_read_failed"
			return result
		end
		if #chunk == 0 then break end
		chunks[#chunks + 1] = chunk
		remaining = remaining - #chunk
	end
	fd:close()
	local content = table.concat(chunks)
	if offset > 0 then
		-- Preserve the byte-limited tail, including very long lines. Only
		-- discard UTF-8 continuation bytes split by the read boundary.
		content = content:gsub("^[\128-\191]+", "")
	end
	result.file = newest
	result.modified = stat.mtime
	result.content = content
	result.truncated = offset > 0
	return result
end

function act_log()
	luci.http.header("Cache-Control", "no-store")
	luci.http.prepare_content("application/json")
	luci.http.write_json(latest_log(luci.http.formvalue("section")))
end

function act_action()
	local actions = { start = "start_now", stop = "stop_now", restart = "restart_now" }
	local command = actions[luci.http.formvalue("action")]
	local section = luci.http.formvalue("section")
	local uci = require("luci.model.uci").cursor()
	if not command or type(section) ~= "string" or not section:match("^[A-Za-z0-9_]+$") or
		uci:get("songloft", section) ~= "songloft" then
		luci.http.status(400, "Bad Request")
		luci.http.prepare_content("application/json")
		luci.http.write_json({ success = false, error = "invalid_action" })
		return
	end

	-- The POST dispatcher validates CSRF; only fixed commands and UCI
	-- section identifiers are passed to the shell, never form settings.
	local code = luci.sys.call("/etc/init.d/songloft " .. command .. " " ..
		require("luci.util").shellquote(section) .. " >/dev/null 2>&1")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ success = code == 0, status = service_status() })
end
