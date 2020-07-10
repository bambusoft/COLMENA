#!/usr/bin/env bash
# Official COLMENA global functions script
# ================================================
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
#  OS VERSIONS tested:
#	Ubuntu 18.04 32bit and 64bit
#	Ubuntu 20.04 64bit
#
#  Official website: http://colmena.bambusoft.com
#
#  Author Mario Rodriguez Somohano, colmena (at) bambusoft.com
#

export FUNCTIONS_LOADED=1

#====================================================================================
# Check if the user is 'root' before allowing any modification
if [ $UID -ne 0 ]; then
	echo -e "$COLOR_RED Execution failed: you must be logged in as 'root' to proceed. $COLOR_END"
	echo "Use command 'sudo -i', then enter root password and then try again."
	exit 1
fi

clean() {
	# $1=fw|bee
	clear
	if [ -z "$1" ]; then
		echo -e "Error cleaning files, no app specified\n"
		exit 1
	fi
	rm -f "$SPATH"/colmena-$1-*
	echo -e "Cleaned log and temporary files\n"
}

change() {
	# $1=[-R|blank] $2=permissions $3=usr $4=grp $5=[file|path]
	if [ -z $1 ] ; then
		symbol="-"
	else
		symbol=$1
	fi
	if [ -n "$5" ] && [ "$5" != "/" ]; then
		echo "[$symbol] $2 $3:$4 => $5"
		chown $1 $3:$4 $5
		chmod $1 $2 $5
	else
		echo "functions: change: file path not specified"
		exit 1
	fi
}

check_status() {
	status=$(ipset -v | grep "protocol")
	echo "ipset: $status"
	status=$(iptables -L -nv | grep "INPUT")
	echo "ip4tables: $status"
	status=$(ip6tables -L -nv | grep "INPUT")
	echo "ip6tables: $status"
	status=$(service fail2ban status | grep "Active")
	echo "fail2ban: $status"
	status=$(/etc/init.d/knockd status | grep "Active")
	echo "knockd: $status"
}

save_tree() {
	# $1 path to save $2 ext
	if [ -d $1 ] ; then
		echo "Writing file permissions for: $1"
		/usr/bin/tree -pugfal $1 >> $COLMENA_FILE_ID.$2
	fi
}

ask_data () {
	# $1 msg, $2 default
	answer=""
	while [ -z "$answer" ]; do
		read -e -p "$1: " -i "$2" answer
	done
}

ask_user_yn() {
	# $1 msg, $2 default
	RESULT=""
	while true; do
		read -e -p "$1: (y/n)? " -i "$2" answer
		case $answer in
			[Yy]* ) RESULT="yes"
					break
					;;
			[Nn]* ) RESULT="no"
					break
					;;
		esac
	done	
}

ask_user_continue() {
	END_SCRIPT=""
	if [ $ADVANCED = "true" ];then
		while true; do
			read -e -p "`echo -e "$COLOR_YLW WARNING: $COLOR_END Step FAIL. Continuing could break your system.
Would you like to continue anyway? $COLOR_RED (NOT RECOMENDED) $COLOR_END  (y/N): "`" -i "N" END_SCRIPT
			case $END_SCRIPT in
				[Yy]* ) echo -e "$COLOR_YLW WARNING: $COLOR_END Continuing even though it could potentially break your system. Press Ctrl+C to exit now (If you changed your mind)"
					sleep 3
					break
					;;
				[Nn]* ) exit 1;
					break
					;;
			esac
		done
	else 
		echo -e "$COLOR_RED ERROR: $COLOR_END Step FAIL. Give command line option '--advanced' to have the ability to ignore this. Exiting..."
		exit 1;
	fi
}

passwordgen() {
    l=$1
    [ "$l" == "" ] && l=16
    tr -dc A-Za-z0-9 < /dev/urandom | head -c ${l} | xargs
}

validate_replacement() {
	# $1 string to validate  $2 file
	if [ -f $2 ]; then
		found=$(grep "$1" $2)
		if [ -n "$found" ]; then
			echo "ERROR: <$1> was not replaced correctly in file $2"
		fi
	else
		echo "WARNING: <$1> was not validated correctly: file $2 does not exist"
	fi
}

# Check if var is in OPTIONS
OPTIONS="+($1|$2|$3|$4|$5)" # Shouldn't be more than 5 parameters
is_opt() {
	shopt -s extglob         # enables pattern lists like +(...|...)
	case "$1" in
        $OPTIONS) ISOPTION="true"
        ;;
        *) ISOPTION="false"
    esac
	shopt -u extglob # puts it back to normal
}

