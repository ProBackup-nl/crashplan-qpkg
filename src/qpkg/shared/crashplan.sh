#!/bin/sh

QPKG_NAME="CrashPlan"
QPKG_BASE=""
CONFFILE=/etc/config/qpkg.conf
QPKG_DIR="$(/sbin/getcfg "${QPKG_NAME}" Install_Path -f ${CONFFILE})"
WEB_SHARE=`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`
NASCFGFILE="/mnt/HDA_ROOT/.config/uLinux.conf"
PIDFILE="${QPKG_DIR}/${QPKG_NAME}.pid"

case "$1" in
	start)
		ENABLED=$(/sbin/getcfg "${QPKG_NAME}" Enable -u -d FALSE -f "${CONFFILE}")
		if [ "$ENABLED" != "TRUE" ]; then
			/bin/echo "$QPKG_NAME is disabled."
			if [ "$2" != "force" ]; then
				exit 1
			else
				/bin/echo "Forcing startup..."
			fi
		fi

		# Lock to avoid running service twice (seems there's a bug on ARM when run from web interface)
		if [ -f /var/run/CrashPlan.lock ]; then
			/bin/echo "Lock file exists!"
			exit 1
		else
			touch /var/run/CrashPlan.lock
		fi

		# PID management
		if [ -f $PIDFILE ]; then
			PID=`/bin/cat $PIDFILE`
			if [ -f /proc/$PID/cmdline ] && [ `/bin/grep "app=CrashPlanService" /proc/$PID/cmdline` ] && ( /bin/kill -0 $PID 2> /dev/null ); then
				/bin/echo "$QPKG_NAME is already running with pid $PID!"
				exit 1
			else
				# PID file exists but it is not CrashPlan running!
				/bin/rm -f $PIDFILE
			fi
		fi

		if [[ -f $QPKG_DIR/crashplan.vars ]]; then
			. $QPKG_DIR/crashplan.vars
		else
			/bin/echo "Did not find $QPKG_DIR/crashplan.vars file."
			exit 1
		fi

		# So CrashPlan can read Java max heap size
		#[ ! -h $QPKG_DIR/bin/run.conf ] && /bin/ln -sf $QPKG_DIR/crashplan.vars $QPKG_DIR/bin/run.conf

		/bin/echo "Cleaning /tmp/*.jna files..."
                /bin/rm -f /tmp/jna*.tmp
		/bin/echo "Cleaning $QPKG_DIR/tmp/ files..."
                /bin/rm -f $QPKG_DIR/tmp/*

                /bin/echo "Starting ${QPKG_NAME}... "

		# Avoid sed'ing file on first launch (package installation)
		if [ -f $QPKG_DIR/conf/my.service.xml ]; then

			# Configure interface and port on which service will listen and memory size allocated
			if [[ -f $QPKG_DIR/htdocs/config.conf ]]; then
				SYS_INTERFACE=`/bin/cat $QPKG_DIR/htdocs/config.conf | /bin/grep interface | /bin/cut -f2 -d=`
				if [[ -n "$SYS_INTERFACE" ]]; then /bin/echo -n "Using network interface defined in ${QPKG_DIR}/htdocs/config.conf: ${SYS_INTERFACE}"; fi
				SYS_MEMORY=`/bin/cat $QPKG_DIR/htdocs/config.conf | /bin/grep memory | /bin/cut -f2 -d=`
			fi

			# Discovery of interface to use 1/2
			if [[ -z "$SYS_INTERFACE" ]]; then
				SYS_INTERFACE=$(/sbin/getcfg Network "Default GW Device" -f $NASCFGFILE)
				if [[ -n "$SYS_INTERFACE" ]]; then /bin/echo -n "Using network interface defined as default gateway in NAS configuration: ${SYS_INTERFACE}"; fi
			fi

			# Discovery of interface to use 2/2
			if [[ -z "$SYS_INTERFACE" ]]; then
				SYS_INTERFACE="$(for iface in $(find /sys/class/net/ -type l | grep -iv "/lo"); do iface=$(/usr/bin/basename $iface); if ifconfig $iface | grep -i inet >/dev/null 2>&1; then echo $iface; fi; done)"
				if [[ -n "$SYS_INTERFACE" ]]; then /bin/echo -n "Using network interface self-discovered: ${SYS_INTERFACE}"; fi
			fi

			# Failure
			if [[ -z "$SYS_INTERFACE" ]]; then
				/bin/echo "Can't find any interface on which to listen!"
				exit 1
			fi

			# Config IP from interface
			SYS_IP=`/sbin/ifconfig $SYS_INTERFACE | /bin/awk '/addr:/{print $2}' | /bin/cut -f2 -d:`
			/bin/echo " (${SYS_IP}) - This can be changed in the web interface"
			/bin/sed -ri "s/<serviceHost(\s*\/)?>.*/<serviceHost>${SYS_IP}<\/serviceHost>/" $QPKG_DIR/conf/my.service.xml

			# If no memory information has been found in config file
			if [[ -z "$SYS_MEMORY" ]]; then
				SYS_MEMORY="512"
			fi

			# Set memory information
			SRV_JAVA_OPTS=`/bin/echo $SRV_JAVA_OPTS | /bin/sed -e "s/-Xms20m/-Xms${SYS_MEMORY}m/"`
			SRV_JAVA_OPTS=`/bin/echo $SRV_JAVA_OPTS | /bin/sed -e "s/-Xmx1024m/-Xmx${SYS_MEMORY}m/"`

			# Configure port on which service will listen for remote backups
			REMOTE_PORT=`/bin/grep "<location>.*</location>" $QPKG_DIR/conf/my.service.xml | /bin/cut -f2 -d: | /bin/cut -f1 -d'<'`
			/bin/sed -i "s/<location>.*<\/location>/<location>${SYS_IP}:${REMOTE_PORT}<\/location>/" $QPKG_DIR/conf/my.service.xml

			# Avoid update / upgrade too quickly
                        /bin/sed -i 's/<upgradePath>.*<\/upgradePath>/<upgradePath>\/dev\/null<\/upgradePath>/' $QPKG_DIR/conf/my.service.xml
                        /bin/sed -i 's/<upgradeDelay>.*<\/upgradeDelay>/<upgradeDelay>150000000<\/upgradeDelay>/' $QPKG_DIR/conf/my.service.xml
		fi

		# Symlink identity and increment max_user_watches
		/bin/rm -rf /var/lib/crashplan
		/bin/ln -sf $QPKG_DIR/var /var/lib/crashplan
		/bin/chmod o+r $QPKG_DIR/var
		/bin/echo 1048576 > /proc/sys/fs/inotify/max_user_watches

		if [[ ${LC_ALL} ]]; then
			LOCALE=`/bin/sed 's/\..*//g' <<< ${LC_ALL}`
			export LC_ALL="${LOCALE}.UTF-8"
		elif [[ ${LC_CTYPE} ]]; then
			LOCALE=`/bin/sed 's/\..*//g' <<< ${LC_CTYPE}`
			export LC_CTYPE="${LOCALE}.UTF-8"
		elif [[ ${LANG} ]]; then
			LOCALE=`/bin/sed 's/\..*//g' <<< ${LANG}`
			export LANG="${LOCALE}.UTF-8"
		else
			export LANG="en_US.UTF-8"
		fi

		TIMEZONE=`/sbin/getcfg System "Time Zone" -f /etc/config/uLinux.conf`
		QPKG_JAVA_OPTS="-Duser.timezone=${TIMEZONE}"
		FULL_CP="$QPKG_DIR/lib/com.backup42.desktop.jar:$QPKG_DIR/lang"
		# If device is ARM
		if [[ `uname -m` == armv[5-7]* ]]; then
			FULL_CP="$QPKG_DIR/lib/jna-3.2.7.jar:${FULL_CP}"
			export LD_LIBRARY_PATH=$QPKG_DIR/lib
		fi

		# If CrashPlan share exists then symlink it to backupArchives
		CrashPlan_Share=`/sbin/getcfg CrashPlan path -f /etc/config/smb.conf`
		if [ "$CrashPlan_Share" ]; then
			[ -d $QPKG_DIR/backupArchives ] && /bin/rm -rf $QPKG_DIR/backupArchives
			/bin/ln -sf $CrashPlan_Share $QPKG_DIR/backupArchives
		else
			[ -d $QPKG_DIR/backupArchives ] || /bin/mkdir $QPKG_DIR/backupArchives
		fi

		# Set JAVA tmp directory
		TMP_JAVA_OPTS="-Djava.io.tmpdir=$QPKG_DIR/tmp"

		cd $QPKG_DIR
		$JAVACOMMON $SRV_JAVA_OPTS $QPKG_JAVA_OPTS $TMP_JAVA_OPTS -classpath $FULL_CP com.backup42.service.CPService > $QPKG_DIR/log/engine_output.log 2> $QPKG_DIR/log/engine_error.log &
		if [[ $! -gt 0 ]]; then
			/bin/echo $! > $PIDFILE

			# Create symlink to CrashPlan web interface
			/bin/chown -R httpdusr:administrators $QPKG_DIR/htdocs
			/bin/chmod -R u+rwx,g-rwx,o-rwx $QPKG_DIR/htdocs
			# If this isn't set then web interface says: Forbidden
			/bin/chmod o+x $QPKG_DIR
			# Create symlink
			[ ! -d /share/$WEB_SHARE/crashplan ] && /bin/ln -sf $QPKG_DIR/htdocs /share/$WEB_SHARE/crashplan

			exit 0
		else
			exit 1
		fi
                ;;

	stop)
                /bin/echo "Stopping ${QPKG_NAME}... "
		/bin/rm -f /var/run/CrashPlan.lock
		if [[ -f $PIDFILE ]] ; then
			/bin/kill `/bin/cat $PIDFILE`
			/bin/sleep 4
			/bin/rm -f $PIDFILE
			/bin/sleep 6
		else
			/bin/echo "No PID found!"
			exit 1
		fi

		# Remove backupArchives directory if symbolic link
		[ -h $QPKG_DIR/backupArchives ] && /bin/rm -f $QPKG_DIR/backupArchives

		# Remove symlink to CrashPlan web interface
		[ -d /share/$WEB_SHARE/crashplan ] && /bin/rm -f /share/$WEB_SHARE/crashplan

		exit 0
                ;;

        restart)
                $0 stop
		/bin/echo "Sleeping 10 seconds..."
		/bin/sleep 10
                $0 start
		exit 0
                ;;
	status)
		if [ -f $PIDFILE ]; then
			PID=`/bin/cat $PIDFILE`
			if [ -f /proc/$PID/cmdline ] && [ `/bin/grep "app=CrashPlanService" /proc/$PID/cmdline` ] && ( /bin/kill -0 $PID 2> /dev/null ); then
				/bin/echo "$QPKG_NAME (pid $PID) is running."
			else
				# Most likely ghost PID (since not CrashPlan)
				/bin/rm -f $PIDFILE
			fi
		else
			/bin/echo "$QPKG_NAME is stopped."
		fi
		exit 0
		;;
	*)
                /bin/echo "Usage: $0 {start|stop|restart|status}"
                exit 1
esac
