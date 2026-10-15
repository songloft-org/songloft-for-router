# 开发经验

## LOG-001：文件落盘与服务管理器日志采集是两条独立路径

- 范围：OpenWrt 的 SongLoft 运行日志。
- 证据：2026-10-15，用户报告 syslog 中持续出现 `msg=access`；基线 `2f1a21620677877593960112fd685fa323c2063c` 的 init 脚本设置 `stdout 1` / `stderr 1`，而后端同时写 stdout 和文件。
- 规则与修复：需要运行日志仅保留在工作目录时，关闭 procd 的 stdout 采集，保留 stderr 写入 syslog，同时保留后端 `<db_path>/data/logs/` 文件及 LuCI 日志读取。不要通过提高全局日志等级来消除重复输出，否则文件中的 INFO 日志也会丢失。启动脚本自身的配置校验、启停错误与后端运行日志应分开处理：保留 `logger -t songloft` 写 syslog 和命令行 stderr 输出。最初误删 logger，用户明确范围后已恢复；关闭后端日志采集不应连带关闭服务管理错误报告。
- 验证：本机 shell 语法检查及既有宿主测试套件；具体结果见本次交付。Not run：OpenWrt 真机重启及 syslog 验证，本次没有连接设备。
- Seen 1× (2026-10-15)。状态：经验。
