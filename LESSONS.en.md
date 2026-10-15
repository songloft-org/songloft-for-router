# Development lessons

## LOG-001: File logging and service-manager log collection are separate paths

- Scope: SongLoft runtime logs on OpenWrt.
- Evidence: On 2026-10-15, the user reported repeated `msg=access` entries in syslog. The init script at baseline `2f1a21620677877593960112fd685fa323c2063c` set `stdout 1` / `stderr 1`, while the backend wrote to both stdout and files.
- Rule and fix: To retain runtime logs only in the working directory, disable procd stdout collection, retain stderr collection into syslog, and keep backend files in `<db_path>/data/logs/` and the LuCI log reader. Do not raise the global log level to remove duplicate output: that also removes INFO entries from files. Treat init-script validation and service-control errors separately from backend runtime logs: retain `logger -t songloft` for syslog and command-line stderr output. The initial change mistakenly removed logger; it was restored after the user clarified the scope. Disabling backend log collection must not also disable service-management error reporting.
- Validation: Local shell syntax checks and the existing host test suite; see this delivery for results. Not run: OpenWrt device restart and syslog verification, since no device was connected.
- Seen 1× (2026-10-15). Status: lesson.
