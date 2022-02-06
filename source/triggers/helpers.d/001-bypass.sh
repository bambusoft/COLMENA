#!/usr/bin/env bash

# Official COLMENA helper Script
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
#
# This is a colmena helper example
# Some atackers are trying to bypass fail2ban scan time window,
# they can send maxretry-1 login attempts from one IP to make a bruteforce attack
# and change between IPs using Tor. Yes, I know, it will take A LOT of time to
# match the real password, but some times this things happen.
# This script get a count of how many times an IP is getting user
# unknown or password mismatchs in a dovecot info log and send it
# to a javascript helper script to send a trigger to fail2ban.

SCRIPT_NAME=$(/usr/bin/basename "$0")
DOVECOT_INFO='/var/log/dovecot-info.log'
MAIL_LOG='/var/log/mail.log'
SYSLOG='/var/log/syslog'
NGINX_LOG='/var/log/nginx'
COLMENA_EVENTS_LOG='/var/log/colmena/events.log'
COLMENA_EVENTS_IP='/var/log/colmena/ip'

if [ ! -f "$COLMENA_EVENTS_LOG" ]; then
	/usr/bin/touch $COLMENA_EVENTS_LOG
fi

if [ -n "$COLMENA_EVENTS_IP" ]; then
	if [ -d "$COLMENA_EVENTS_IP" ]; then
		if [ "$(ls -A $COLMENA_EVENTS_IP)" ]; then
			/usr/bin/find $COLMENA_EVENTS_IP/*.blk -mtime +1 -exec /bin/rm -f {} \;
		fi
	else
		/bin/mkdir -p $COLMENA_EVENTS_IP
	fi
fi

if [ -z "$1" ]; then
	LOG_FILE="$DOVECOT_INFO"
else
	LOG_FILE="$1"
fi

# Dovecot - Brute Force Attack (bypassing fail2ban) and no authentications
if [ -f "$LOG_FILE" ]; then
	/bin/grep "sql(" $LOG_FILE | /bin/sed -e 's@.*sql(@@g' | /bin/sed -e 's@).*$@@g' | /bin/sed -e 's@,<.*$@@g' | /usr/bin/sort | /usr/bin/uniq -c
	# The next comand is experimental and may block legitimate pop3 users
	#/bin/grep "no auth" $LOG_FILE | /bin/egrep -v "rip=::1" | /bin/sed -e 's@.*rip=@noauth @g' | /bin/sed -e 's@, lip=.*$@@g' | /usr/bin/sort | /usr/bin/uniq -c
fi

# Postfix - Too many connections
if [ -f "$MAIL_LOG" ]; then
	:
	# The next command is experimental and may block mail gateways
	#/bin/grep "\bconnect from" $MAIL_LOG | /bin/egrep -v localhost | /bin/sed -e 's@.* from.*\[@connect @g' | /bin/sed -e 's@\].*$@ @g' | /usr/bin/sort | /usr/bin/uniq -c
fi

# Syslog - Port Scan (bypassing psad)
if [ -f "$SYSLOG" ]; then
	/bin/grep "colmena.*denied" $SYSLOG | /bin/egrep -v "CRON" | /bin/sed -e 's@.*SRC=@scan @' | /bin/sed -e 's@ DST.*$@@' | /bin/sed -e 's@ LEN.*$@@' | /usr/bin/sort | /usr/bin/uniq -c
fi

# Nginx - HTTP Auth Basic Brute Force Attack (bypassing fail2ban)
if [ -d "$NGINX_LOG" ]; then
	# The next command is experimental and may block legitimate HTTP clients
	/bin/grep "401" $NGINX_LOG/*access.log | /bin/sed -e 's/\:/ /' | /usr/bin/awk '{print $2}' | /usr/bin/sort | /usr/bin/uniq -c
fi
