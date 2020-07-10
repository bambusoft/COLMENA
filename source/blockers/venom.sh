#!/bin/sh
# This file is part of colmena security project
# Copyright (C) 2010-2020, Mario Rodriguez < colmena (at) bambusoft.com >
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version.

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
/usr/bin/echo "$TODAY Running venom with $IPSET_BIN" >> $COLMENA_LOG
# Create sets
/usr/bin/echo "Creating BLACKLIST_IP" >> $COLMENA_LOG
$IPSET_BIN flush BLACKLIST_IP >> $COLMENA_LOG 2>&1
$IPSET_BIN destroy BLACKLIST_IP -q >> $COLMENA_LOG 2>&1
$IPSET_BIN create BLACKLIST_IP hash:ip hashsize 65536 -q >> $COLMENA_LOG 2>&1
/usr/bin/echo "Creating BLACKLIST_NET" >> $COLMENA_LOG
$IPSET_BIN flush BLACKLIST_NET >> $COLMENA_LOG 2>&1
$IPSET_BIN destroy BLACKLIST_NET -q >> $COLMENA_LOG 2>&1
$IPSET_BIN create BLACKLIST_NET hash:net hashsize 65536 -q >> $COLMENA_LOG 2>&1
/usr/bin/echo "Creating BLACKLIST_IP6" >> $COLMENA_LOG
$IPSET_BIN flush BLACKLIST_IP6 >> $COLMENA_LOG 2>&1
$IPSET_BIN destroy BLACKLIST_IP6 -q >> $COLMENA_LOG 2>&1
$IPSET_BIN create BLACKLIST_IP6 hash:ip hashsize 65536 -q >> $COLMENA_LOG 2>&1
/usr/bin/echo "Creating BLACKLIST_NET6" >> $COLMENA_LOG
$IPSET_BIN flush BLACKLIST_NET6 >> $COLMENA_LOG 2>&1
$IPSET_BIN destroy BLACKLIST_NET6 -q >> $COLMENA_LOG 2>&1
$IPSET_BIN create BLACKLIST_NET6 hash:net hashsize 65536 -q >> $COLMENA_LOG 2>&1

# Add ips/nets
while read ip; do
	IPv4=$(/usr/bin/expr index "$ip" .)
	if [ "$IPv4" -gt 0 ]; then
		NET4=$(/usr/bin/expr index "$ip" /)
		if [ "$NET4" -gt 0 ]; then
			$IPSET_BIN add BLACKLIST_NET $ip >> $COLMENA_LOG 2>&1
		else
			$IPSET_BIN add BLACKLIST_IP $ip >> $COLMENA_LOG 2>&1
		fi
	fi
	IPv6=$(/usr/bin/expr index "$ip" :)
	if [ "$IPv6" -gt 0 ]; then
		NET6=$(/usr/bin/expr index "$ip" /)
		if [ "$NET6" -gt 0 ]; then
			$IPSET_BIN add BLACKLIST_NET6 $ip >> $COLMENA_LOG 2>&1
		else
			$IPSET_BIN add BLACKLIST_IP6 $ip >> $COLMENA_LOG 2>&1
		fi
	fi
done < /dev/stdin >> $COLMENA_LOG 2>&1
