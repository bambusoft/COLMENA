#!/usr/bin/env bash

# Official COLMENA BEE Update Script
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

CUID=`id -u`
if [ $CUID -ne 0 ]; then
        echo "Need to be root"
        exit 1
fi

if [ ! -f /etc/colmena/colmena.cfg ]; then
	echo "Can not find /etc/colmena/colmena.cfg"
	exit 1
fi

DAT_FILE=$(ls -1 /etc/colmena/.install.dat)
if [ ! -f "$DAT_FILE" ]; then
	FW_DATA_FILE=$(ls -1 ../colmena-fw-*.dat)
	if [ -f "$FW_DATA_FILE" ]; then
		cp "$FW_DATA_FILE" /etc/colmena/.install.dat
	fi
	BEE_DATA_FILE=$(ls -1 ../colmena-bee-*.dat)
	if [ -f "$BEE_DATA_FILE" ]; then
		cat "$BEE_DATA_FILE" >> /etc/colmena/.install.dat
	fi
fi

if [ ! -f "$DAT_FILE" ]; then
	echo "Can not find $DAT_FILE"
	exit 1
fi


. /etc/colmena/colmena.cfg
. $DAT_FILE

if [ -z "$GLOBALS_LOADED" ]; then
	echo "Can not find /etc/colmena/colmena.cfg"
	exit 1
fi

if [ -n "$COLMENA_VERSION" ]; then
	OIFS=$IFS
	IFS=.
	components=(${COLMENA_VERSION##*-})
	major=${components[0]}
	minor=${components[1]}
	micro=${components[2]}
	build=${components[3]}
	IFS=$OIFS
	#echo "Version => Major $major, Minor $minor, Micro $micro, Build $build"
	OK="true"
	if [ "$major" -gt "1" ]; then
		OK="false"
	 fi
	if [ "$minor" -gt "0" ]; then
		 OK="false"
	fi
	if [ "$micro" -gt "0" ]; then
		OK="false"
	fi
	if [ -n "$build" ] && [ "$build" -gt "0" ]; then
		OK="false"
	fi
	if [ "$OK" == "false" ]; then
		echo "Installed version is not compatible with this utiity"
		exit 1
	fi
fi

echo "Update utility for colmena v$COLMENA_VERSION"

# Download source code
CPATH="colmena-v${COLMENA_VERSION}"
TPATH="/tmp/$CPATH"
SOURCE="$TPATH/source"
ZIP_FILE="${CPATH}.zip"

HASPERM="true"
if [ ! -w "/usr/sbin/colmena" ]; then
	HASPERM="false"
fi
if [ ! -w "/usr/share/netfilter-persistent" ]; then
        HASPERM="false"
fi
if [ ! -w "$COLMENA_SHR_PATH" ]; then
        HASPERM="false"
fi
if [ "$HASPERM" == "false" ]; then
	echo "You as $ADMIN_USR:$ADMIN_GRP do not have write permissions in one or all of the following directories:"
	echo "	/usr/sbin/colmena"
	echo "	/usr/share/netfilter-persistent"
	echo "	$COLMENA_SHR_PATH"
	exit 1
fi

if [ ! -d "/usr/share/netfilter-persistent/fwrules/" ]; then
	mkdir -vp /usr/share/netfilter-persistent/fwrules
fi

rm -f "/tmp/$ZIP_FILE" 2>/dev/null
rm -rf "$TPATH" 2>/dev/null
URL="https://colmena.bambusoft.com/download/releases/$ZIP_FILE"
wget -P /tmp --no-check-certificate -4 $URL

if [ -f "/tmp/$ZIP_FILE" ]; then
	# Uncompress zip file
	unzip -q "/tmp/$ZIP_FILE" -d /tmp
	if [ -d "$TPATH" ]; then
		# Stop colmena
		echo "Stoping colmena"
		colmena stop
		sleep 5
		# Copy to local dir
		echo "Copying files"
		cp $TPATH/install*.sh ./
		cp -r $SOURCE ./source
		# Copy to locations
		cp -v $SOURCE/colmena /usr/sbin/colmena
		cp -v $SOURCE/netfilter/netfilter-persistent /usr/sbin/netfilter-persistent
		cp -v $SOURCE/netfilter/plugins/* /usr/share/netfilter-persistent/plugins.d/
		cp -v $SOURCE/netfilter/fwrules/* /usr/share/netfilter-persistent/fwrules/
		cp -v $SOURCE/functions.sh $COLMENA_SHR_PATH
		cp -vr $SOURCE/triggers $COLMENA_SHR_PATH
		cp -vr $SOURCE/blockers $COLMENA_SHR_PATH
		cp -vr $SOURCE/propagate/* $COLMENA_SHR_PATH
		# To be done: Update npm packages
		cp -rv $SOURCE/web/*.js $COLMENA_SHR_PATH/web
		sed -i "s/%%WEBPORT%%/$WEB_PORT/g" $COLMENA_SHR_PATH/web/index.js
		sed -i "s@%%SERVER_KEY%%@$SERVER_KEY@" $COLMENA_SHR_PATH/web/index.js
		sed -i "s@%%SERVER_PUB%%@$SERVER_PUB@" $COLMENA_SHR_PATH/web/index.js
		if [ -d /usr/lib/nagios/plugins ]; then
			cp $SOURCE/nagios/check_colmena.sh /usr/lib/nagios/plugins
		fi
		# Restart colmena services
		echo "Starting colmena"
		colmena start
	else
		echo "Unabe to find /tmp/$CPATH path"
	fi
else
	echo "Unable to find $ZIP_FILE file"
fi
