local fs = require "nixio.fs"

m = Map("songloft", translate("SongLoft"),
	translate("SongLoft is a lightweight self-hosted music server.")
	.. [[ <a href="https://github.com/songloft-org/songloft" target="_blank">]]
	.. translate("Project Homepage")
	.. [[</a>]]
)

m:section(SimpleSection).template = "songloft/songloft_status"

s = m:section(TypedSection, "songloft", translate("Basic Settings"))
s.anonymous = true
s.addremove = false

enabled = s:option(Flag, "enabled", translate("Enable"))
enabled.default = 0
enabled.rmempty = false

port = s:option(Value, "listen_port", translate("Listening Port"))
port.datatype = "port"
port.default = "58091"
port.rmempty = false

db_path = s:option(Value, "db_path", translate("Data Directory"),
	translate("Choose a writable persistent directory before enabling SongLoft. SongLoft stores its data here and reads music from the music subdirectory. To use an existing music folder, bind mount it to this subdirectory before starting the service."))
db_path.rmempty = false
function db_path.validate(self, value)
	if value and value:match("^/[^/]") then
		return value
	end
	return nil, translate("Enter an absolute path for the data directory")
end

base_path = s:option(Value, "base_path", translate("URL Base Path"),
	translate("Used when SongLoft is served behind a reverse proxy under a sub-path, e.g. /songloft"))
base_path.optional = true

username = s:option(Value, "admin_username", translate("Admin Username"),
	translate("Leave empty to keep the current setting unchanged"))
username.optional = true

password = s:option(Value, "admin_password", translate("Admin Password"),
	translate("Leave empty to keep the current setting unchanged"))
password.password = true
password.optional = true

bin_path = s:option(Value, "bin_path", translate("Binary Path"),
	translate("Leave empty to use the default path /usr/bin/songloft"))
bin_path.optional = true
bin_path.placeholder = "/usr/bin/songloft"

function m.on_after_commit(map)
	luci.sys.call("/etc/init.d/songloft reload >/dev/null 2>&1")
end

return m
