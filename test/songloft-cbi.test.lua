-- Lua 5.1 model/unit tests, not live LuCI or Map.parse integration tests.
-- Run: lua test/songloft-cbi.test.lua [repository-root]
-- The doubles below cover only the Value.parse branches used by this model.
-- on_after_commit is invoked directly: dispatcher timing, rpcd and ucitrack
-- execution are deliberately outside this suite's scope.

local script = arg[0] or "test/songloft-cbi.test.lua"
local root = arg[1] or ((script:match("^(.*)/[^/]+$") or ".") .. "/..")
local model_path = root .. "/openwrt/luci-app-songloft/luasrc/model/cbi/songloft.lua"
local passed, failed = 0, 0

local function equal(actual, expected, message)
	assert(actual == expected, (message or "unexpected value") ..
		": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
	local ok, err = pcall(run)
	if ok then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local function fixture()
	local state = { forms = {}, saved = {}, errors = {}, writes = {}, removals = {},
		reads = 0, queries = {}, commands = {}, reload_code = 0, changes = {} }
	local Value, Flag, DummyValue, TypedSection = {}, {}, {}, {}
	local map

	-- Minimal Value.parse double: mirrors nonempty validation/write and empty
	-- remove/missing branches of LuCI's AbstractValue.parse, with readonly and
	-- novld behavior. It is not a full CBI implementation.
	function Value.parse(self, section, novld)
		if self.readonly then return end
		local value, previous = self:formvalue(section), self:cfgvalue(section)
		if value and #value > 0 then
			local validated, err = self:validate(value, section)
			if not validated and not novld then
				self:add_error(section, "invalid", err)
			end
			if validated and (self.forcewrite or validated ~= previous) then
				self:write(section, validated)
			end
		elseif self.rmempty or self.optional then
			self:remove(section)
		elseif (value ~= nil or self.nilasempty) and previous ~= value and not novld then
			local _, err = self:validate(nil, section)
			self:add_error(section, "missing", err)
		end
	end

	local function option(class, tab, name)
		local object = setmetatable({ option = name, tab = tab, class = class,
			rmempty = true, optional = false }, { __index = class })
		function object:formvalue(section)
			state.reads = state.reads + 1
			return (state.forms[section] or {})[self.option]
		end
		function object:cfgvalue(section)
			return (state.saved[section] or {})[self.option]
		end
		function object:add_error(section, kind, message)
			state.errors[#state.errors + 1] = { section = section, kind = kind, message = message }
		end
		function object:write(section, value)
			state.saved[section] = state.saved[section] or {}
			state.saved[section][self.option] = value
			state.writes[#state.writes + 1] = { section = section, value = value }
			return true
		end
		function object:remove(section)
			state.saved[section] = state.saved[section] or {}
			state.saved[section][self.option] = nil
			state.removals[#state.removals + 1] = section
			return true
		end
		return object
	end

	local environment = setmetatable({
		Value = Value, Flag = Flag, DummyValue = DummyValue, TypedSection = TypedSection,
		translate = function(value) return value end,
		luci = { sys = { call = function(command)
			state.commands[#state.commands + 1] = command
			return state.reload_code
		end } },
		Map = function(config)
			map = { config = config, changed = false, options = {}, sections = {} }
			map.uci = { changes = function(_, queried_config)
				state.queries[#state.queries + 1] = queried_config
				return state.changes, state.query_error
			end }
			function map:section(class, section_type)
				local section = { class = class, section_type = section_type, tabs = {} }
				function section:tab(name, title)
					self.tabs[#self.tabs + 1] = { name = name, title = title }
				end
				function section:taboption(tab, kind, name)
					local value = option(kind, tab, name)
					map.options[name] = value
					return value
				end
				self.sections[#self.sections + 1] = section
				return section
			end
			return map
		end
	}, { __index = _G })
	local chunk, err = loadfile(model_path)
	assert(chunk, err)
	setfenv(chunk, environment)
	equal(chunk(), map, "model return")
	return map, state
end

local function parse_case(enabled, value, previous, expected_errors, expected_removals, novld)
	local map, state = fixture()
	state.forms.one = { enabled = enabled, db_path = value }
	state.saved.one = { db_path = previous }
	map.options.db_path:parse("one", novld)
	equal(#state.errors, expected_errors, "validation errors")
	equal(#state.removals, expected_removals, "removals")
	equal(map.options.db_path.rmempty, false, "rmempty restored")
	return map, state
end

for _, flag in ipairs({ "1", "true", "0", true, 1 }) do
	local enabled = flag
	for _, empty in ipairs({ "nil", "empty" }) do
		local label = empty
		test("truthy " .. type(enabled) .. " " .. tostring(enabled) .. " requires DB: " .. label, function()
			local value
			if label == "empty" then value = "" end
			local _, state = parse_case(enabled, value, "", 1, 0)
			equal(#state.writes, 0)
			equal(state.errors[1].kind, "missing")
		end)
	end
end

test("enabled missing DB with no saved option", function()
	parse_case("1", nil, nil, 1, 0)
end)
test("unchecked nil permits blank default", function()
	parse_case(nil, "", "", 0, 1)
end)
test("unchecked nil removes old path", function()
	local _, state = parse_case(nil, "", "/data/old", 0, 1)
	equal(state.saved.one.db_path, nil)
end)
test("unchecked nil permits absent field and removes old path", function()
	parse_case(nil, nil, "/data/old", 0, 1)
end)

for _, path in ipairs({ "/data/songloft", "/mnt/music library", "/", "relative", "//data", "/data\nlog", "/data\0log" }) do
	local value = path
	test("DB path " .. string.format("%q", value), function()
		local valid = value == "/data/songloft" or value == "/mnt/music library"
		local _, state = parse_case("1", value, nil, valid and 0 or 1, 0)
		equal(#state.writes, valid and 1 or 0)
		if valid then equal(state.saved.one.db_path, value) end
	end)
end

for _, path in ipairs({ "", "/mnt/music library", "/", "relative", "//music", "/music\nfolder" }) do
	local value = path
	test("music path " .. string.format("%q", value), function()
		local map, state = fixture()
		state.forms.one = { music_path = value }
		state.saved.one = { music_path = "/previous" }
		map.options.music_path:parse("one")
		local valid = value == "" or value == "/mnt/music library"
		equal(#state.errors, valid and 0 or 1, "validation errors")
		if valid then
			equal(state.saved.one.music_path, value ~= "" and value or nil)
		else
			equal(state.saved.one.music_path, "/previous", "invalid path preserves saved setting")
		end
	end)
end

test("unchanged valid path is not rewritten", function()
	local _, state = parse_case("1", "/data", "/data", 0, 0)
	equal(#state.writes, 0)
end)

for _, original in ipairs({ false, true }) do
	local rmempty = original
	test("readonly has no side effects; rmempty=" .. tostring(rmempty), function()
		local map, state = fixture()
		local db = map.options.db_path
		db.readonly, db.rmempty = true, rmempty
		db:parse("one")
		equal(state.reads, 0)
		equal(#state.errors + #state.writes + #state.removals, 0)
		equal(db.rmempty, rmempty)
	end)
	test("disabled parse restores rmempty=" .. tostring(rmempty), function()
		local map, state = fixture()
		map.options.db_path.rmempty = rmempty
		state.forms.one = { db_path = "" }
		map.options.db_path:parse("one")
		equal(map.options.db_path.rmempty, rmempty)
		equal(#state.errors, 0)
		equal(#state.removals, 1)
	end)
end

test("novld skips explicit missing enforcement", function()
	parse_case("1", nil, nil, 0, 0, true)
	parse_case("1", "", "", 0, 0, true)
end)
test("novld skips invalid-path errors without writing invalid data", function()
	local _, state = parse_case("1", "relative", nil, 0, 0, true)
	equal(#state.writes, 0)
end)
test("novld disabled empty removes old path and restores rmempty", function()
	parse_case(nil, "", "/data", 0, 1, true)
end)
test("section-specific enabled flags do not leak", function()
	local map, state = fixture()
	state.forms.enabled = { enabled = "1", db_path = "" }
	state.forms.disabled = { db_path = "" }
	state.saved.disabled = { db_path = "/old" }
	map.options.db_path:parse("enabled")
	map.options.db_path:parse("disabled")
	equal(#state.errors, 1)
	equal(state.errors[1].section, "enabled")
	equal(#state.removals, 1)
	equal(state.removals[1], "disabled")
	equal(map.options.db_path.rmempty, false)
end)

test("model sections, tabs, defaults and templates", function()
	local map = fixture()
	equal(map.config, "songloft")
	local section = map.sections[1]
	equal(section.section_type, "songloft")
	equal(section.anonymous, true)
	equal(section.addremove, false)
	equal(#section.tabs, 3)
	for i, name in ipairs({ "status", "basic", "logs" }) do
		equal(section.tabs[i].name, name)
	end
	for name, spec in pairs({
		_status = { "status", "songloft/songloft_status" },
		_actions = { "status", "songloft/songloft_status" },
		_logs = { "logs", "songloft/songloft_log" }
	}) do
		equal(map.options[name].tab, spec[1])
		equal(map.options[name].template, spec[2])
	end
	equal(map.options.db_path.tab, "basic")
	equal(map.options.enabled.default, 0)
	equal(map.options.enabled.rmempty, false)
	equal(map.options.listen_port.default, "58091")
	equal(map.apply_on_parse, nil, "standard staged apply not forced")
end)

local reload_command = "/etc/init.d/songloft reload >/dev/null 2>&1"
local function callback_case(changes, expected_calls, code, query_error)
	local map, state = fixture()
	state.changes, state.query_error = changes, query_error
	state.reload_code = code or 0
	equal(map.changed, false, "initial map.changed")
	-- Direct model callback unit test, not a simulated Save/Apply lifecycle.
	map:on_after_commit()
	equal(#state.queries, 1)
	equal(state.queries[1], "songloft")
	equal(#state.commands, expected_calls)
	if expected_calls > 0 then equal(state.commands[1], reload_command) end
	return map, state
end

test("callback no deltas reconciles once", function() callback_case({}, 1) end)
test("callback empty SongLoft deltas reconciles once", function()
	callback_case({ songloft = {} }, 1)
end)
test("callback real enabled delta does not reload before actual commit", function()
	callback_case({ songloft = { { "set", "one", "enabled", "1" } } }, 0)
end)
test("callback pending other config only reconciles SongLoft once", function()
	callback_case({ network = { { "set", "lan", "ipaddr", "192.0.2.1" } } }, 1)
end)
test("callback failed nil changes query does not reload", function()
	callback_case(nil, 0, 0, "Connection failed")
end)
test("callback false changes query does not reload", function() callback_case(false, 0) end)
test("callback reload failure sets message", function()
	local map = callback_case({}, 1, 1)
	equal(map.message, "Applying the service settings failed. Check the executable, data directory and system log.")
end)
test("callback successful reload does not report failure", function()
	local map = callback_case({}, 1)
	equal(map.message, nil)
end)

print(string.format("SongLoft CBI model/unit tests: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
