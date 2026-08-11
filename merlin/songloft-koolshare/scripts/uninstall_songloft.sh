#!/bin/sh
source /koolshare/scripts/base.sh

module="songloft"

if [ -f "/koolshare/scripts/${module}_config.sh" ]; then
	sh /koolshare/scripts/${module}_config.sh stop >/dev/null 2>&1
fi

rm -f /koolshare/webs/Module_${module}.asp
rm -f /koolshare/scripts/${module}_*.sh
rm -f /koolshare/scripts/uninstall_${module}.sh
rm -f /koolshare/bin/${module}
rm -f /koolshare/res/icon-${module}.png
rm -f /koolshare/init.d/*${module}*.sh  >/dev/null 2>&1

rm -f /tmp/upload/${module}.log  >/dev/null 2>&1
rm -f /var/run/${module}.pid     >/dev/null 2>&1

values=$(dbus list ${module}_ | cut -d "=" -f 1)
for value in $values; do
	dbus remove "$value"
done

exit 0
