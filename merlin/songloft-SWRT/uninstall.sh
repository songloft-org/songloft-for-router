#!/bin/sh
source /jffs/softcenter/scripts/base.sh

module="songloft"

if [ -f "/jffs/softcenter/scripts/${module}_config.sh" ]; then
	sh /jffs/softcenter/scripts/${module}_config.sh stop >/dev/null 2>&1
fi

rm -f /jffs/softcenter/webs/Module_${module}.asp
rm -f /jffs/softcenter/scripts/${module}_*.sh
rm -f /jffs/softcenter/scripts/uninstall_${module}.sh
rm -f /jffs/softcenter/bin/${module}
rm -f /jffs/softcenter/res/icon-${module}.png
rm -f /jffs/softcenter/init.d/*${module}*.sh  >/dev/null 2>&1
rm -rf /jffs/softcenter/${module}

rm -f /tmp/upload/${module}.log  >/dev/null 2>&1
rm -f /var/run/${module}.pid     >/dev/null 2>&1

values=$(dbus list ${module}_ | cut -d "=" -f 1)
for value in $values; do
	dbus remove "$value"
done

exit 0
