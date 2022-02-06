#!/usr/bin/env bash

# Official COLMENA fwrule Script
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

if [ $UID -ne 0 ]; then
        /bin/echo -e "Execuion failed: you must be logged in as 'root' to proceed."
        exit 1
fi

SCRIPT_NAME=$(/usr/bin/basename "$0")
COLMENA_LOG='/var/log/colmena/fwrules.log'
IP_FILE="./web_access.ip"

if [ ! -f "$IP_FILE" ]; then
	[ "$#" -eq 1 ] || exit
	IP=$1
else
	IP=$(/bin/cat $IP_FILE)
	/bin/rm -f $IP_FILE
fi

echo "Giving firewall access to IP=$IP"
/sbin/iptables -I INPUT -p tcp -s $IP -m state --state NEW --dport 1222 -j ACCEPT
/sbin/iptables -I INPUT -p tcp -m tcp -s $IP --dport 8080:8081 -j ACCEPT
