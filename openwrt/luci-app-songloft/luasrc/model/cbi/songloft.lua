m = Map("songloft", translate("SongLoft"),
	translate("SongLoft is a lightweight self-hosted music server.")
	.. [[ <a href="https://github.com/songloft-org/songloft" target="_blank" rel="noopener noreferrer">]]
	.. translate("Project Homepage")
	.. [[</a>]]
)

-- Use LuCI's normal staged apply flow. ucitrack reloads after commit,
-- including for changes applied later through the global pending-changes UI.

s = m:section(TypedSection, "songloft")
s.anonymous = true
s.addremove = false
s:tab("status", translate("Status and actions"))
s:tab("basic", translate("Basic Settings"))
s:tab("logs", translate("Logs"))

enabled = s:taboption("status", Flag, "enabled", translate("Enable"))
enabled.default = 0
enabled.rmempty = false

status = s:taboption("status", DummyValue, "_status", translate("Current status"))
status.template = "songloft/songloft_status"

controls = s:taboption("status", DummyValue, "_actions", translate("Service control"))
controls.template = "songloft/songloft_status"
controls.description = translate("Service actions use saved settings without changing Enable. Save & Apply starts or stops the service according to Enable.")

port = s:taboption("basic", Value, "listen_port", translate("Listening Port"))
port.datatype = "port"
port.default = "58091"
port.rmempty = false

db_path = s:taboption("basic", Value, "db_path", translate("Data Directory"),
	translate("Choose a writable persistent directory before enabling SongLoft. SongLoft stores its data here and reads music from the music subdirectory. To use an existing music folder, bind mount it to this subdirectory before starting the service."))
db_path.rmempty = false
function db_path.validate(self, value)
	if value and value:match("^/[^/]") and not value:find("%c") then
		return value
	end
	return nil, translate("Enter an absolute path for the data directory")
end

function db_path.parse(self, section, novld)
	if self.readonly then return end
	local required = not not enabled:formvalue(section)
	local value = self:formvalue(section)
	-- CBI skips validate() for an unchanged empty string. Explicitly reject
	-- it when enabled, but permit empty settings for a disabled service.
	if required and (value == nil or value == "") and not novld then
		self:add_error(section, "missing", translate("Enter an absolute path for the data directory"))
		return
	end
	local rmempty = self.rmempty
	self.rmempty = not required
	Value.parse(self, section, novld)
	self.rmempty = rmempty
end

base_path = s:taboption("basic", Value, "base_path", translate("URL Base Path"),
	translate("Used when SongLoft is served behind a reverse proxy under a sub-path, e.g. /songloft"))
base_path.optional = true

username = s:taboption("basic", Value, "admin_username", translate("Admin Username"),
	translate("Leave empty to keep the current setting unchanged"))
username.optional = true

password = s:taboption("basic", Value, "admin_password", translate("Admin Password"),
	translate("Leave empty to keep the current setting unchanged"))
password.password = true
password.optional = true

bin_path = s:taboption("basic", Value, "bin_path", translate("Binary Path"),
	translate("Leave empty to use the default path /usr/bin/songloft"))
bin_path.optional = true
bin_path.placeholder = "/usr/bin/songloft"

logs = s:taboption("logs", DummyValue, "_logs")
logs.template = "songloft/songloft_log"
logs.description = translate("Shows the most recently modified regular file in data/logs under the saved data directory, regardless of its name. Large logs show only the last 128 KiB.")

function m.on_after_commit(map)
	local changes = map.uci:changes("songloft")
	-- No delta means rpcd emits no config.change event. Still reconcile a
	-- temporary manual start/stop when Save & Apply is explicitly requested.
	-- For real changes, let ucitrack reload only after the actual commit.
	if type(changes) == "table" and not next(changes.songloft or {}) then
		if luci.sys.call("/etc/init.d/songloft reload >/dev/null 2>&1") ~= 0 then
			map.message = translate("Applying the service settings failed. Check the executable, data directory and system log.")
		end
	end
end

return m
