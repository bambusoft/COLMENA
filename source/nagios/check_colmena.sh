#!/usr/bin/env bash
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

STATUS_OK="0"
STATUS_WARNING="1"
STATUS_CRITICAL="2"
STATUS_UNKNOWN="3"
ps_state=$(/bin/ps aux | /bin/grep "colmena/web/index.js" | /bin/grep -v grep | /usr/bin/wc -l)
USE_SUDO="sudo"
COLMENA="/sbin/colmena"
PROGPATH=`/usr/bin/dirname $0`

print_usage() {
echo "
Usage:

  $PROGPATH/check_colmena.sh -h for help (this messeage)

                -wb <ban warnlevel>
                -cb <ban critlevel>
                -ws <set warnlevel>
                -cs <set critlevel>
                -wp <scan port warnlevel>
                -cp <scan port critlevel>
                -wr <rules warnlevel>
                -cr <rules critlevel>
        example :
  $PROGPATH/check_colmena.sh -wb 100 -cb 200

"
}

if [ ! -f "$COLMENA" ];then
        echo "    ++++ colmena executable not found ++++"
        exit $STATUS_UNKNOWN
fi

if [ "$ps_state" -lt "1" ]; then
        echo "   ++++ Web process is not running ++++"
        exit $STATUS_UNKNOWN
fi

while test -n "$1"; do
    case "$1" in
        -wb)
            warnb=$2
            shift
            ;;
        -cb)
            critb=$2
            shift
            ;;
        -ws)
            warns=$2
            shift
            ;;
        -cs)
            crits=$2
            shift
            ;;
        -wp)
            warnp=$2
            shift
            ;;
        -cp)
            critp=$2
            shift
            ;;
        -wr)
            warnr=$2
            shift
            ;;
        -cr)
            critr=$2
            shift
            ;;
        -h)
            print_usage
            exit $STATUS_UNKNOWN
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit $STATUS_UNKNOWN
            ;;
    esac
  shift
done

# Banned default limits
if [ -z ${warnb} ]; then
	warnb=100
fi

if [ -z ${critb} ]; then
        critb=200
fi

#  Black list set default limits
if [ -z ${warns} ]; then
        warns=1000
fi

if [ -z ${crits} ]; then
        critb=2000
fi

# Port scan banned IP limits
if [ -z ${warnp} ]; then
        warnp=10
fi

if [ -z ${critp} ]; then
        critp=20
fi

# Defined rules limits
if [ -z ${warnr} ]; then
        warnr=10
fi

if [ -z ${critr} ]; then
        critr=5
fi

banCnt=$($USE_SUDO $COLMENA list-ban | /bin/sed -e 's/.*Ban //' | /bin/sort -u | /bin/wc -l)
setCnt=$($USE_SUDO $COLMENA list-set | /bin/sed ':a;N;$!ba;s/\nNumber/ /g' | /bin/grep "BLACKLIST" | /bin/sed -e 's/.*: //' | paste -sd+ | bc)
rulCnt=$($USE_SUDO /usr/sbin/iptables -S | /bin/egrep "\s(INPUT|OUTPUT|FORWARD)\s" | /bin/wc -l)
psdCnt=$(/usr/bin/find /var/log/psad -mindepth 1 -maxdepth 1 -type d -mtime 0 | /bin/egrep -v "errs" | /bin/wc -l)

State="Ok"

# Number of fail2ban banned IPs
if [ "$banCnt" -ge ${warnb} ] && [ "$banCnt" -lt ${critb} ]; then
        State="Warning"
elif [ "$banCnt" -ge ${warnb} ]; then
        State="Critical"
fi

# Number of banned IPs in BLACKLIST sets
if [ "$setCnt" -ge ${warns} ] && [ "$setCnt" -lt ${crits} ]; then
        State="Warning"
elif [ "$setCnt" -ge ${warns} ]; then
        State="Critical"
fi

# Number of port scan banned IPs 
if [ "$psdCnt" -ge ${warnp} ] && [ "$psdCnt" -lt ${critp} ]; then
        State="Warning"
elif [ "$psdCnt" -ge ${warnp} ]; then
        State="Critical"
fi

# Number of expected firewall rules
if [ "$rulCnt" -le ${critr} ]; then
        State="Critical"
elif [ "$rulCnt" -le ${warnr} ]; then
        State="Warning"
fi

OUTPUT=$(echo "Colmena state --- ${State}: ${banCnt} banned IP(s) ${setCnt} blacklist item(s) ${psdCnt} scan IP(s) ${rulCnt} fw rules | ban=${banCnt};${warnb};${critb};; set=${setCnt};${warns};${crits};; scn=${psdCnt};${warnp};${critp};; rul=${rulCnt};${warnr};${critr};;")

echo $OUTPUT

if [ ${State} == "Warning" ];then 
        exit ${STATUS_WARNING}
elif [ ${State} == "Critical" ];then 
        exit ${STATUS_CRITICAL}
elif [ ${State} == "Unknown" ];then 
        exit ${STATUS_UNKNOWN}
else
        exit ${STATUS_OK}
fi
