#!/bin/sh
# Colmena Portscan
# ================================================
# This file is part of colmena security project
# Copyright (C) 2010-2022, Mario Rodriguez < colmena (at) bambusoft.com >
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# OS VERSIONS tested:
#	Ubuntu 18.04 32bit and 64bit
#	Ubuntu 20.04 64bit
#
#  Official website: http://colmena.bambusoft.com

IAM=$(/usr/bin/whoami)
COLMENA_LOG="/var/log/colmena/colmena.log"
IPSET_BIN="/usr/sbin/ipset"

if [ ${IAM} != "root" ]; then
	/usr/bin/echo "You must be root to use this utility"
	exit 1
fi

if [ ! -f $COLMENA_LOG ]; then
	/usr/bin/touch $COLMENA_LOG
	/usr/bin/chmod 660 $COLMENA_LOG
fi

TODAY=$(/usr/bin/date)
/usr/bin/echo "$TODAY Running portscan $1" >> $COLMENA_LOG

if [ -n "$1" ]; then
	# Add or update IP activity
	SCRIPT_NAME=$(/usr/bin/basename "$0")
	/usr/bin/echo -e "# Trigger: [psad] $SCRIPT_NAME\n# List: [BL]\n$1" | /usr/bin/node /usr/share/colmena/triggers/collector.js --quit

	FOUND=$(/usr/sbin/ipset list | /usr/bin/grep -F "$1")
	if [ -n "$FOUND" ]; then
		/usr/bin/echo "$1 already in BLACKLIST found ($FOUND)" | tee -a $COLMENA_LOG_FILE
	else
		IPv4=$(/usr/bin/expr index "$1" .)
		if [ "$IPv4" -gt 0 ]; then
			NET4=$(/usr/bin/expr index "$1" /)
			if [ "$NET4" -gt 0 ]; then
				$IPSET_BIN add BLACKLIST_NET $1 >> $COLMENA_LOG 2>&1
			else
				$IPSET_BIN add BLACKLIST_IP $1 >> $COLMENA_LOG 2>&1
			fi
		fi
		IPv6=$(/usr/bin/expr index "$1" :)
		if [ "$IPv6" -gt 0 ]; then
			NET6=$(/usr/bin/expr index "$1" /)
			if [ "$NET6" -gt 0 ]; then
				$IPSET_BIN add BLACKLIST_NET6 $1 >> $COLMENA_LOG 2>&1
			else
				$IPSET_BIN add BLACKLIST_IP6 $1 >> $COLMENA_LOG 2>&1
			fi
		fi
	fi
else
	/usr/bin/echo "Please provide IP" | tee -a $COLMENA_LOG
fi
