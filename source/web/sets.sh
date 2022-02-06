#!/bin/sh
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

# This tool reads an acl.dat file with the following format
#	add bl ipv4|ipv6
#	add wl ipv4|ipv6 proto port [timeout]
#	del bl ipv4|ipv6
#	del wl ipv4|ipv6 proto port

COLMENA_CFG="/etc/colmena"

. $COLMENA_CFG/colmena.cfg

ACL="$COLMENA_SHR_PATH/web/acl.dat"
IPS_BIN=$(which ipset)

if [ -f  "$ACL" ]; then
	# [FALTA]
	# Read the acl file in a loop
		# CMD = add/del
		# LST = wl/bl
		# IP = ipv4/ipv6
		# PROTO =
		# PORT =
		# TIMEOUT =
		colmena $CMD $LST $PROTO $PORT $TIMEOUT
	# done loop
	rm -f $ACL
	$IPS_BIN list > $COLMENA_CFG/ipset.list 
fi
