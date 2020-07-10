#!/usr/bin/env bash
# Official COLMENA global config script
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

export GLOBALS_LOADED=1

if [ -z "$SPATH" ]; then
	SPATH="."
fi

export vlog="/var/log"
export COLMENA_VERSION="1.0.0"
export COLMENA_FILE_ID="colmena-fw-$$"
export COLMENA_INSTALL_BKP_PATH="$SPATH/backup"
export COLMENA_INSTALL_CFG_PATH="$SPATH/config"
export COLMENA_INSTALL_SRC_PATH="$SPATH/source"
export COLMENA_INSTALL_LOG_FILE="$SPATH/$COLMENA_FILE_ID.log"
export COLMENA_DATA_FILE="$SPATH/$COLMENA_FILE_ID.dat"
export COLMENA_CFG_PATH="/etc/colmena"
export COLMENA_LOG_PATH="$vlog/colmena"
export COLMENA_BIN_PATH="/usr/sbin"
export COLMENA_SHR_PATH="/usr/share/colmena"
export IPTABLES_CONFIG="/etc/iptables"
export FAIL2BAN_CONFIG="/etc/fail2ban"
export LOGROTATE_PATH="/etc/logrotate.d"
export COLMENA_LOG_FILE="$COLMENA_LOG_PATH/colmena.log"

export COLOR_RED="\e[1;31m"
export COLOR_GRN="\e[1;32m"
export COLOR_YLW="\e[1;33m"
export COLOR_END="\e[0m"
export oIFS="$IFS"
export IFS=' '

# Triggers
export vlogt="/tmp/test"
export AUTH_LOG="$vlog/auth.log"
export FAIL2BAN_LOG="$vlog/fail2ban.log"
export SYS_LOG="$vlog/syslog"
export APACHE_LOG="$vlog/apache2"
export NGINX_LOG="$vlog/nginx"
export POSTFIX_LOG="$vlog/mail.log"
export DOVECOT_INFO="$vlog/dovecot-info.log"
