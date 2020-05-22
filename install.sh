#!/usr/bin/env bash

# Official COLMENA Automated Security Script
# ==========================================
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#  OS VERSION supported:
#	Ubuntu 18.04 32bit and 64bit
#	Ubuntu 20.04 64bit
#
#  Official website: http://colmena.bambusoft.com
#
#  Author Mario Rodriguez Somohano, colmena (at) bambusoft.com
#
# Parameters: [revert|clean|status]
#	No parameter means install
#	revert - will try to set the original environment to its initial state (to be done)
#	clean  - removes log and tree files (to be done)
#	status - will show services status

if [[ "$1" = "clean" ]] ; then
	rm -f colmena-*.{log,new,org} > /dev/null
	clear
	echo -e "Cleaned log and temporary files\n"
	exit
fi
