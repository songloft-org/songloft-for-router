-- Standalone Lua 5.1 controller tests. All filesystem and service APIs are mocked.
assert(_VERSION == "Lua 5.1", "Run this suite with Lua 5.1")
local root = arg[1]
if not root then
	local script = assert(arg[0], "Missing script path"):gsub("\\", "/")
	root = script:match("^(.*)/test/[^/]+$")
	if root == "" then root = "/" end
	if not root and script:match("^test/[^/]+$") then root = "." end
	assert(root, "Pass the repository root as arg[1]")
end
local controller_path = root:gsub("/+$", "") ..
	"/openwrt/luci-app-songloft/luasrc/controller/songloft.lua"
local directory, limit = "/db/data/logs", 128 * 1024
local state, controller
local tests, totals = {}, {}

local function equal(actual, expected)
	if actual ~= expected then
		local function describe(value)
			if type(value) == "string" then
				return string.format("%q (%d bytes)", value:sub(1,80), #value)
			end
			return tostring(value)
		end
		error("expected " .. describe(expected) .. ", got " .. describe(actual), 2)
	end
end
local function copy(value)
	local result = {}
	for key, item in pairs(value) do result[key] = item end
	return result
end
local function add(name, mtime, data, kind)
	local file = { name = name, mtime = mtime, data = data or "",
		type = kind or "reg", dev = 7, ino = #state.entries + 1 }
	file.size = #file.data
	state.entries[#state.entries + 1] = file
	return file
end
local function lookup(path)
	for _, file in ipairs(state.entries) do
		if path == directory .. "/" .. file.name then return file end
	end
	error("Unexpected file access: " .. tostring(path))
end

local fs = {}
function fs.access(path)
	equal(path, "/etc/config/songloft")
	return state.config_exists
end
function fs.stat(path, field)
	equal(path, directory)
	equal(field, "type")
	state.stat_calls = state.stat_calls + 1
	return state.directory_type
end
function fs.dir(path)
	equal(path, directory)
	if state.directory_unreadable then return nil, 13, "Permission denied" end
	local i = 0
	return function()
		i = i + 1
		return state.entries[i] and state.entries[i].name
	end
end
function fs.lstat(path)
	local file = lookup(path)
	if file.gone then return nil, 2, "Not found" end
	return copy(file)
end

local nx = { fs = fs }
function nx.open_flags(readonly, nonblock)
	equal(readonly, "rdonly")
	equal(nonblock, "nonblock")
	return 2048
end
function nx.open(path, flags)
	equal(flags, 2048)
	state.opens[#state.opens + 1] = path
	local file = lookup(path)
	if file.unreadable then return nil, 13, "Permission denied" end
	local fd = { position = 0, reads = 0, bytes = 0, closed = false }
	state.fds[#state.fds + 1] = fd
	function fd:stat()
		assert(not self.closed, "stat on closed descriptor")
		if file.stat_error then return nil, 5, "I/O error" end
		return copy(file.open_stat or file)
	end
	function fd:seek(offset, whence)
		assert(not self.closed, "seek on closed descriptor")
		equal(whence, "set")
		assert(offset >= 0 and offset == math.floor(offset), "Invalid offset")
		state.offsets[#state.offsets + 1] = offset
		if file.seek_error then return nil, 5, "I/O error" end
		self.position = offset
		return offset -- Zero is a successful, truthy result in Lua.
	end
	function fd:read(length)
		assert(not self.closed, "read on closed descriptor")
		assert(length > 0 and length <= 8192, "Controller read exceeds 8KiB")
		state.requests[#state.requests + 1] = length
		self.reads = self.reads + 1
		if file.read_error == self.reads then return nil, 5, "I/O error" end
		if file.eof then return "" end
		local count = math.min(length, 8192, file.short_read or 8192)
		local chunk = file.data:sub(self.position + 1, self.position + count)
		self.position = self.position + #chunk
		self.bytes = self.bytes + #chunk
		assert(self.bytes <= limit, "Descriptor read exceeds 128KiB")
		return chunk
	end
	function fd:close()
		assert(not self.closed, "Descriptor closed twice")
		self.closed = true
		state.closes = state.closes + 1
		return true
	end
	return fd
end

local cursor = {}
function cursor:get(config, section, option)
	equal(config, "songloft")
	local value = state.sections[section]
	if not value then return nil end
	if option then return value[option] end
	return value[".type"]
end
function cursor:foreach(config, kind, callback)
	equal(config, "songloft")
	equal(kind, "songloft")
	for _, name in ipairs(state.section_order) do
		local value = state.sections[name]
		if value[".type"] == kind then callback(copy(value)) end
	end
end
local http = {}
function http.header(key, value) state.headers[key] = value end
function http.prepare_content(mime) state.mime = mime end
function http.formvalue(key)
	assert(key == "section" or key == "action", "Unexpected query parameter: " .. key)
	return state.query[key]
end
function http.write_json(value) state.response = value end
function http.status(code, message) state.http_status = { code, message } end
local util = {}
function util.ubus(object, method, arguments)
	equal(object, "service")
	equal(method, "list")
	equal(arguments.name, "songloft")
	state.ubus_calls = state.ubus_calls + 1
	return state.ubus_result
end
function util.shellquote(value)
	state.quotes[#state.quotes + 1] = value
	return "'" .. value:gsub("'", "'\\''") .. "'"
end
local sys = {}
function sys.call(command)
	state.commands[#state.commands + 1] = command
	return state.exit_code
end
local modules = {
	["nixio"] = nx, ["nixio.fs"] = fs,
	["luci.model.uci"] = { cursor = function() return cursor end },
	["luci.http"] = http, ["luci.sys"] = sys, ["luci.util"] = util
}
local function reset()
	state = {
		entries = {}, sections = { main = { [".name"] = "main",
			[".type"] = "songloft", db_path = "/db", enabled = "1" } },
		section_order = { "main" }, directory_type = "dir", config_exists = true,
		query = { section = "main" }, headers = {}, opens = {}, fds = {},
		offsets = {}, requests = {}, closes = 0, stat_calls = 0, quotes = {},
		commands = {}, exit_code = 0, ubus_result = {}, ubus_calls = 0, routes = {}
	}
	for name, value in pairs(modules) do
		package.loaded[name] = nil
		local stub = value
		package.preload[name] = function() return stub end
	end
	_G.nixio = require("nixio")
	_G.luci = { http = require("luci.http"), sys = require("luci.sys") }
	_G.luci.controller = nil
	package.loaded["luci.controller.songloft"] = nil
	local function target(kind, name) return { kind = kind, name = name } end
	_G.cbi = function(name) return target("cbi", name) end
	_G.call = function(name) return target("call", name) end
	_G.post = function(name) return target("post", name) end
	_G._ = function(value) return value end
	_G.entry = function(path, action, title, order)
		local route = { target = action, title = title, order = order }
		state.routes[table.concat(path, "/")] = route
		return route
	end
	dofile(controller_path)
	controller = assert(package.loaded["luci.controller.songloft"])
end
local function invoke(method)
	state.response, state.mime, state.http_status = nil, nil, nil
	state.headers = {}
	controller[method]()
	equal(state.mime, "application/json")
	assert(type(state.response) == "table", "Missing JSON response")
	if method == "act_log" then equal(state.headers["Cache-Control"], "no-store") end
	for _, fd in ipairs(state.fds) do assert(fd.closed, "Leaked descriptor") end
	return state.response
end
local function log_error(code)
	local response = invoke("act_log")
	equal(response.error, code)
	equal(response.file, nil)
	equal(response.content, nil)
	return response
end
local function test(suite, name, run)
	tests[#tests + 1] = { suite = suite, name = name, run = run }
end
local function logtest(name, run) test("logs", name, run) end

-- Selection/configuration regression cases (36).
logtest("mtime ignores lexical order, dates, prefixes and extensions", function()
	add("songloft-2099.log", 10, "old")
	add("aaa-1900.bin", 30, "new")
	add("zzz-2100.log", 20)
	local response = invoke("act_log")
	equal(response.file, "aaa-1900.bin")
	equal(response.modified, 30)
	equal(response.content, "new")
end)
for _, name in ipairs({ "extensionless", "最新·日志", ". hidden arbitrary" }) do
	local filename = name
	logtest("opaque filename: " .. filename, function()
		add("normal.log", 1)
		add(filename, 2, "ok")
		equal(invoke("act_log").file, filename)
	end)
end
for _, kind in ipairs({ "dir", "fifo", "lnk", "chr", "blk", "sock" }) do
	local filetype = kind
	logtest("skip newer " .. filetype, function()
		add("safe", 1)
		add("newer", 99, "unsafe", filetype)
		equal(invoke("act_log").file, "safe")
		equal(#state.opens, 1)
	end)
end
logtest("only nonregular entries", function()
	add("d", 1, "", "dir"); add("f", 2, "", "fifo"); add("l", 3, "", "lnk")
	log_error("no_logs")
	equal(#state.opens, 0)
end)
logtest("vanished entry skipped", function()
	add("gone", 9).gone = true
	add("safe", 1)
	equal(invoke("act_log").file, "safe")
end)
logtest("query paths cannot select file", function()
	add("old", 1); add("new", 2)
	state.query.path, state.query.file = "/etc/shadow", "../../etc/passwd"
	state.query.directory, state.query.db_path = "/tmp", "/tmp"
	equal(invoke("act_log").file, "new")
	equal(state.opens[1], directory .. "/new")
end)
for _, value in ipairs({ false, 123, "", "../main", "main/../x", "main;id", "未知", "missing" }) do
	local section = value
	logtest("invalid section: " .. tostring(section), function()
		state.query.section = section
		log_error("invalid_section")
		equal(state.stat_calls, 0)
		equal(#state.opens, 0)
	end)
end
logtest("missing section", function()
	state.query.section = nil
	log_error("invalid_section")
end)
logtest("wrong section type", function()
	state.sections.main[".type"] = "other"
	log_error("invalid_section")
end)
for _, value in ipairs({ false, 123, "", "relative", "/", "//host", "/db/\nunsafe" }) do
	local base = value
	logtest("invalid db_path: " .. string.format("%q", tostring(base)), function()
		state.sections.main.db_path = base
		log_error("data_directory_missing")
		equal(state.stat_calls, 0)
	end)
end
logtest("missing db_path", function()
	state.sections.main.db_path = nil
	log_error("data_directory_missing")
end)
logtest("trailing slashes normalized", function()
	state.sections.main.db_path = "/db///"
	add("f", 1)
	equal(invoke("act_log").directory, directory)
end)
logtest("missing log directory", function()
	state.directory_type = nil
	log_error("log_directory_missing")
end)
logtest("log path is not directory", function()
	state.directory_type = "reg"
	log_error("log_directory_missing")
end)
logtest("unreadable directory", function()
	state.directory_unreadable = true
	log_error("log_directory_unreadable")
end)
logtest("empty directory", function() log_error("no_logs") end)

-- Reading/resource/tail regression cases (20). Newline trimming is NOT required.
logtest("empty newest does not fall back", function()
	add("old", 1, "old"); add("new", 2)
	local response = invoke("act_log")
	equal(response.file, "new"); equal(response.content, "")
	equal(response.truncated, false); equal(#state.requests, 0)
	equal(state.offsets[1], 0); equal(state.closes, 1)
end)
logtest("unreadable newest does not fall back", function()
	add("old", 1); add("new", 2).unreadable = true
	log_error("log_read_failed")
	equal(#state.opens, 1); equal(state.opens[1], directory .. "/new")
	equal(state.closes, 0)
end)
logtest("refresh reselects changed mtime", function()
	local a, b = add("a", 1), add("b", 2)
	equal(invoke("act_log").file, "b")
	a.mtime = 3
	equal(invoke("act_log").file, "a")
	b.mtime = 4
	local response = invoke("act_log")
	equal(response.file, "b"); equal(response.modified, 4)
	equal(state.closes, 3)
end)
for _, size in ipairs({ 8192, 1000 }) do
	local chunk_size = size
	logtest("accumulate reads of " .. chunk_size .. " bytes", function()
		local data = string.rep("x", 20000)
		add("f", 1, data).short_read = chunk_size
		equal(invoke("act_log").content, data)
		equal(#state.requests, chunk_size == 8192 and 3 or 20)
		equal(state.fds[1].bytes, 20000)
		if chunk_size == 8192 then equal(state.requests[3], 3616) end
	end)
end
logtest("exactly 128KiB is not truncated", function()
	local data = string.rep("x", limit)
	add("f", 1, data)
	local response = invoke("act_log")
	equal(response.content, data); equal(response.truncated, false)
	equal(state.offsets[1], 0); equal(state.fds[1].bytes, limit)
	equal(#state.requests, 16)
end)
local function tailtest(name, prefix, tail, expected)
	logtest(name, function()
		add("f", 1, prefix .. tail)
		local response = invoke("act_log")
		equal(response.content, expected or tail); equal(response.truncated, true)
		equal(state.offsets[1], #prefix); equal(state.fds[1].bytes, limit)
		equal(#state.requests, 16)
	end)
end
tailtest("partial first line preserved", string.rep("p", 100), "partial\n" .. string.rep("x", limit - 8))
tailtest("complete first line preserved", "prefix\n", "complete\n" .. string.rep("x", limit - 9))
tailtest("very long line preserved", "x", string.rep("x", limit))
tailtest("split UTF8 continuation bytes dropped", "prefix",
	string.char(128, 191) .. string.rep("x", limit - 2), string.rep("x", limit - 2))
tailtest("complete UTF8 at boundary preserved", "prefix",
	string.char(228, 184, 173) .. string.rep("x", limit - 3))
logtest("untruncated leading continuation bytes unchanged", function()
	local data = string.char(128, 191) .. "abc"
	add("f", 1, data)
	equal(invoke("act_log").content, data)
end)
logtest("early EOF closes descriptor", function()
	add("f", 1, "abc").eof = true
	equal(invoke("act_log").content, ""); equal(state.closes, 1)
end)
local function read_error()
	log_error("log_read_failed")
	equal(state.closes, 1)
end
for _, field in ipairs({ "stat_error", "seek_error" }) do
	local failure = field
	logtest("close on " .. failure, function()
		add("f", 1, "abc")[failure] = true
		read_error(); equal(#state.requests, 0)
	end)
end
for _, nth in ipairs({ 1, 2 }) do
	local read_number = nth
	logtest("close on read error " .. read_number, function()
		add("f", 1, string.rep("x", 20000)).read_error = read_number
		read_error(); equal(#state.requests, read_number)
	end)
end
for _, field in ipairs({ "ino", "dev", "type" }) do
	local changed = field
	logtest("close on opened replacement " .. changed, function()
		local file = add("f", 1, "abc")
		file.open_stat = copy(file)
		file.open_stat[changed] = changed == "type" and "fifo" or 999
		read_error(); equal(#state.requests, 0); equal(#state.offsets, 0)
	end)
end

local log_count = #tests
assert(log_count == 56, "Expected all 56 log regression cases")

-- These assertions exercise the controller, not the LuCI dispatcher/CSRF runtime.
for _, action in ipairs({ "start", "stop", "restart" }) do
	local requested, expected = action, action .. "_now"
	test("actions", "whitelist " .. requested, function()
		state.query.action = requested
		state.sections.main.enabled = "0"
		state.query.command, state.query.db_path = "rm -rf /", "/tmp;id"
		local response = invoke("act_action")
		equal(response.success, true)
		equal(#state.commands, 1)
		equal(state.commands[1], "/etc/init.d/songloft " .. expected .. " 'main' >/dev/null 2>&1")
		equal(state.quotes[1], "main"); equal(state.ubus_calls, 1)
		equal(response.status.sections.main.enabled, false)
		equal(state.http_status, nil)
	end)
end
local function invalid_action()
	local response = invoke("act_action")
	equal(response.success, false); equal(response.error, "invalid_action")
	equal(state.http_status[1], 400); equal(state.http_status[2], "Bad Request")
	equal(#state.commands, 0); equal(#state.quotes, 0); equal(state.ubus_calls, 0)
end
for _, value in ipairs({ false, 123, "", "reload", "start_now", "start;id" }) do
	local action = value
	test("actions", "reject action " .. tostring(action), function()
		state.query.action = action
		invalid_action()
	end)
end
test("actions", "reject missing action", function() invalid_action() end)
for _, value in ipairs({ false, 123, "", "../main", "main;id", "main'", "main\n", "未知", "missing" }) do
	local section = value
	test("actions", "reject section " .. string.format("%q", tostring(section)), function()
		state.query.action, state.query.section = "start", section
		invalid_action()
	end)
end
test("actions", "reject missing section", function()
	state.query.action, state.query.section = "start", nil
	invalid_action()
end)
test("actions", "reject wrong UCI section type", function()
	state.query.action = "start"
	state.sections.main[".type"] = "other"
	invalid_action()
end)
test("actions", "quote valid section and report status after command failure", function()
	state.sections.main = nil
	state.sections.Zone_9 = { [".name"] = "Zone_9", [".type"] = "songloft", enabled = "1" }
	state.section_order = { "Zone_9" }
	state.query.section, state.query.action = "Zone_9", "restart"
	state.exit_code = 7
	state.ubus_result = { songloft = { instances = {
		["songloft.Zone_9"] = { running = true, pid = 42 }
	} } }
	local response = invoke("act_action")
	equal(response.success, false); equal(response.error, nil)
	equal(state.commands[1], "/etc/init.d/songloft restart_now 'Zone_9' >/dev/null 2>&1")
	equal(state.quotes[1], "Zone_9")
	equal(response.status.sections.Zone_9.running, true)
	equal(response.status.sections.Zone_9.pids[1], 42)
end)
test("actions", "successful command with unavailable status", function()
	state.query.action, state.ubus_result = "stop", nil
	local response = invoke("act_action")
	equal(response.success, true); equal(response.status.error, "service_unavailable")
end)

for _, value in ipairs({ false, 123, "unavailable" }) do
	local result = value
	test("status", "unavailable ubus " .. tostring(result), function()
		state.ubus_result = result
		equal(invoke("act_status").error, "service_unavailable")
	end)
end
test("status", "nil ubus", function()
	state.ubus_result = nil
	equal(invoke("act_status").error, "service_unavailable")
end)
for _, result in ipairs({ {}, { songloft = {} } }) do
	local response = result
	test("status", "missing service or instances uses defaults", function()
		state.ubus_result = response
		local section = invoke("act_status").sections.main
		equal(section.enabled, true); equal(section.running, false); equal(section.active, false)
		equal(#section.pids, 0); equal(section.port, "58091"); equal(section.base_path, "")
	end)
end
test("status", "per-section isolation, stopped and running instances", function()
	state.sections.main.listen_port, state.sections.main.base_path = "60000", "/music"
	state.sections.off = { [".name"] = "off", [".type"] = "songloft", enabled = "0" }
	state.sections.absent = { [".name"] = "absent", [".type"] = "songloft" }
	state.sections.other = { [".name"] = "other", [".type"] = "not-songloft" }
	state.section_order = { "main", "off", "absent", "other" }
	state.ubus_result = { songloft = { instances = {
		["songloft.main"] = { running = true, pid = 10 },
		["songloft.off"] = { running = false, pid = 20 },
		["songloft.orphan"] = { running = true, pid = 30 }
	} } }
	local sections = invoke("act_status").sections
	equal(sections.main.running, true); equal(sections.main.active, true)
	equal(sections.main.pids[1], 10); equal(#sections.main.pids, 1)
	equal(sections.main.port, "60000"); equal(sections.main.base_path, "/music")
	equal(sections.off.enabled, false); equal(sections.off.running, false)
	equal(sections.off.active, true); equal(#sections.off.pids, 0)
	equal(sections.absent.enabled, false); equal(sections.absent.active, false)
	equal(sections.other, nil); equal(sections.orphan, nil)
end)
test("status", "running without pid yields empty pid list", function()
	state.ubus_result = { songloft = { instances = { ["songloft.main"] = { running = true } } } }
	local section = invoke("act_status").sections.main
	equal(section.running, true); equal(#section.pids, 0)
end)
test("status", "empty configuration", function()
	state.sections, state.section_order = {}, {}
	equal(next(invoke("act_status").sections), nil)
end)

test("routes", "absent config registers no routes", function()
	state.config_exists = false
	controller.index()
	equal(next(state.routes), nil)
end)
test("routes", "CBI, status/log calls and POST action registration", function()
	controller.index()
	local prefix = "admin/services/songloft"
	local main = assert(state.routes[prefix])
	equal(main.target.kind, "cbi"); equal(main.target.name, "songloft")
	equal(main.title, "SongLoft"); equal(main.order, 60); equal(main.dependent, true)
	for suffix, method in pairs({ status = "act_status", log = "act_log", action = "act_action" }) do
		local route = assert(state.routes[prefix .. "/" .. suffix])
		equal(route.target.kind, suffix == "action" and "post" or "call")
		equal(route.target.name, method); equal(route.leaf, true)
	end
	local count = 0
	for _ in pairs(state.routes) do count = count + 1 end
	equal(count, 4)
end)

local failures = 0
for _, case in ipairs(tests) do
	local total = totals[case.suite] or { passed = 0, failed = 0 }
	totals[case.suite] = total
	local ok, message = xpcall(function()
		reset()
		case.run()
		for _, fd in ipairs(state.fds) do assert(fd.closed, "Leaked descriptor") end
	end, debug.traceback)
	if ok then
		total.passed = total.passed + 1
	else
		total.failed, failures = total.failed + 1, failures + 1
		io.stderr:write("FAIL [", case.suite, "] ", case.name, "\n", message, "\n")
	end
end
for _, suite in ipairs({ "logs", "actions", "status", "routes" }) do
	local total = totals[suite]
	print(string.format("%s: %d passed, %d failed", suite, total.passed, total.failed))
end
print(string.format("TOTAL: %d cases, %d passed, %d failed", #tests, #tests - failures, failures))
os.exit(failures == 0 and 0 or 1)
