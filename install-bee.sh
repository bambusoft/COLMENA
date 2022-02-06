#!/usr/bin/env bash

# Official COLMENA Host IP Manager Security Script
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
# Parameters: [revert]
#	No parameter means install
#	revert - will try to set the original environment to its initial state (to be done)

SPATH=$(dirname $0)
export SPATH=$(cd $SPATH && pwd)

. $SPATH/source/globals.sh
. /etc/lsb-release
. ./source/functions.sh
. $SPATH/config/db.cfg

if [ -z "$GLOBALS_LOADED" ] || [ -z "$FUNCTIONS_LOADED" ] || [ -z "$DB_CFG_LOADED" ] ; then
	echo "Unable to load dependency file"
	exit 1
fi

COLMENA_FILE_ID="colmena-bee-$$"
COLMENA_INSTALL_LOG_FILE="./$COLMENA_FILE_ID.log"
COLMENA_DATA_FILE="./$COLMENA_FILE_ID.dat"
#FW_DATA=$(ls -1 "$SPATH"/colmena-fw*.dat)
FW_DATA=$(ls -1 "$COLMENA_CFG_PATH"/.install.dat)

if [ ! -f "$FW_DATA" ]; then
	echo "Missing required file"
	exit 1
fi

# Default user options values, real values will be asked later
STORE_TREE="false"
SUDO_USER=""
SERVER_FQDN=""
SERVER_IP4=""
SERVER_IP6=""

oIFS="$IFS"
IFS=':'


#====================================================================================
#--- Display the 'welcome' splash/user warning info..
clean "bee"
echo -e "\n################################################################"
echo "#   Welcome to COLMENA IP Manager official installation script #"
echo "################################################################"

#====================================================================================
#--- Advanced mode warning and var set
is_opt "--advanced"
ADVANCED="$ISOPTION"

#====================================================================================
# Check if the administrator is requesting to revert colmena fw
if [[ "$1" = "revert" ]] ; then
	    echo -e "$COLOR_YLW Reversion requested, this will disable security packages installed and set file permissions to its original state. $COLOR_END\n"
		REVERT="true"
		ACTION="revert"
else
		REVERT="false"
		ACTION="install"
fi

#====================================================================================
#  Ensure the OS is compatible with the script
# (CentOS is considered but not tested, feel free to send feedback)
echo -e "\nChecking that minimal requirements are ok"
BITS=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
if [ -f /etc/centos-release ]; then
    OS="CentOs"
    VERFULL=$(sed 's/^.*release //;s/ (Fin.*$//' /etc/centos-release)
    VER=${VERFULL:0:1} # return version
elif [ -f /etc/lsb-release ]; then
    OS=$(grep DISTRIB_ID /etc/lsb-release | sed 's/^.*=//')
    VER=$(grep DISTRIB_RELEASE /etc/lsb-release | sed 's/^.*=//')
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

echo "Detected : $OS  $VER  $BITS"

if [[ "$OS" = "CentOs" && ("$VER" = "6" || "$VER" = "7" ) || 
      "$OS" = "Ubuntu" && ("$VER" = "18.04" || "$VER" = "20.04" ) ]] ; then
	if [[ "$OS" = "Ubuntu" ]] ; then
		PACKAGE_INSTALLER="apt-get -yqq install"
		PACKAGE_REMOVER="apt-get -yqq remove"
	fi
	if [[ "$OS" = "CentOs" ]] ; then
		PACKAGE_INSTALLER="yum -y -q install"
		PACKAGE_REMOVER="yum -y -q remove"
	fi
	if [[ "$OS" = "Ubuntu" && "$VER" = "20.04" ]] ; then
	    echo -e "$COLOR_GRN This OS is supported by colmena team $COLOR_END\n"
	else
	    echo -e "$COLOR_YLW WARNING: OS=$OS $VER is not being supported by colmena team, continue at your own risk $COLOR_END\n"
	fi
else
    echo -e "$COLOR_RED Sorry, this OS is not supported by colmena. $COLOR_END\n"
    ask_user_continue
fi

#====================================================================================
# Check for some software packages
if [[ "$OS" = "Ubuntu" ]]; then
	CHECK_FAIL="false"
	#  Ensure required software is pre-installed (Mysql, Nodejs)
	if [ -f /usr/sbin/nginx ]; then
		NGINX=$(/usr/sbin/nginx -v 2>&1)
		echo -e "$COLOR_GRN Nginx web server installed ($NGINX) $COLOR_END"
	fi
	if [ -f /usr/bin/mysql ]; then
		MYSQL=$(/usr/bin/mysql -V)
		echo -e "$COLOR_GRN MySQL database server installed ($MYSQL) $COLOR_END"
	else
		echo -e "$COLOR_RED MySQL database server not installed . $COLOR_END"
		CHECK_FAIL="true"
	fi
	NODEXE=$(which node)
	if [ -f "$NODEXE" ]; then
		NODE=$( eval "$NODEXE -v" )
		echo -e "$COLOR_GRN NodeJS runtime environment installed ($NODE) $COLOR_END"
	else
		echo -e "$COLOR_RED NodeJS runtime environment not installed. $COLOR_END"
		CHECK_FAIL="true"
	fi
	if [ -f /usr/sbin/colmena ]; then
		COLMENA=$(/usr/sbin/colmena version)
		echo -e "$COLOR_GRN Colmena Firewall installed ($COLMENA) $COLOR_END"
	else
		echo -e "$COLOR_RED Colmena firewall not installed. $COLOR_END"
		CHECK_FAIL="true"
	fi

	if [ $CHECK_FAIL = "true" ]; then
		echo -e "\n This installer is designed to install and configure colmena bee (IP Manager) but some software dependencies are missing!"
		echo " Please re-install requested software before attempting to install colmena bee using this script."
		ask_user_continue
	fi

	if [ -f /etc/systemd/system/colmenad.service ]; then
		service colmenad stop
	fi
else
    echo -e "$COLOR_YLW WARNING: OS=$OS $VER is not being suported by colmena team, packages not checked $COLOR_END\n"
fi
echo ""

#====================================================================================
# Obtain important user input
if [[ "$REVERT" = "false" ]] ; then
	# Ask for db information
	echo "Please provide information about MySQL database to use:"

	# Host
	if [ -z "$DB_HOST" ] ; then
		DB_HOST="localhost"
	fi
	ask_data " Please enter database host: " "$DB_HOST"
	DB_HOST="$answer"
	echo "DB_HOST=$DB_HOST" > $COLMENA_DATA_FILE

	# Port
	if [ -z "$DB_PORT" ] ; then
		DB_PORT="3306"
	fi
	ask_data " Please enter database port: " "$DB_PORT"
	DB_PORT="$answer"
	echo "DB_PORT=$DB_PORT" >> $COLMENA_DATA_FILE

	# Database
	if [ -z "$DB_NAME" ] ; then
		DB_NAME="colmena"
	fi
	ask_data " Please enter database name: " "$DB_NAME"
	DB_NAME="$answer"
	echo "DB_NAME=$DB_NAME" >> $COLMENA_DATA_FILE

	# User
	if [ -z "$DB_USER" ] ; then
		DB_USER="colmenausr"
	fi
	ask_data " Please enter database user name: " "$DB_USER"
	DB_USER="$answer"
	echo "DB_USER=$DB_USER" >> $COLMENA_DATA_FILE

	# Password
	if [ -z "$DB_PASS" ] ; then
		DB_PASS=$(passwordgen)
	fi
	ask_data " Please enter database user password: " "$DB_PASS"
	DB_PASS="$answer"
	echo "DB_PASS=$DB_PASS" >> $COLMENA_DATA_FILE

	if [ -f "$FW_DATA" ]; then
		TEMP=$(grep "ADMIN_USR" "$FW_DATA")
		ADMIN_USR=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "ADMIN_GRP" "$FW_DATA")
		ADMIN_GRP=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "SERVER_FQDN" "$FW_DATA")
		SERVER_FQDN=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "SERVER_IP4" "$FW_DATA")
		SERVER_IP4=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "SERVER_IP6" "$FW_DATA")
		SERVER_IP6=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "SERVER_CERT" "$FW_DATA")
		SERVER_CERT=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "SERVER_KEY" "$FW_DATA")
		SERVER_KEY=$(cut -d'=' -f2 <<<"$TEMP")
		TEMP=$(grep "SERVER_PUB" "$FW_DATA")
		SERVER_PUB=$(cut -d'=' -f2 <<<"$TEMP")
	else
		ADMIN_USR="root"
		ADMIN_GRP="root"
		SERVER_FQDN="localhost"
		SERVER_IP4="127.0.0.1"
		SERVER_IP6="::1"
		SERVER_CERT="undefined"
		SERVER_KEY="undefined"
		SERVER_PUB="undefined"
	fi

	ASK="true"
	while [ $ASK = "true" ]
		do
			# Web Port
			if [ -z "$WEB_PORT" ] ; then
				WEB_PORT=$(shuf -i 1025-65535 -n 1)
			fi
			ask_data " Please enter web port to listen: " "$WEB_PORT"
			WEB_PORT="$answer"
			echo "WEB_PORT=$WEB_PORT" > $COLMENA_DATA_FILE
			IS_IN_USE=$(netstat -natp | grep -F ":$WEB_PORT" | head -1 | sed -e "s@.*\/@@g")
			if [ -n "$IS_IN_USE" ]; then
				echo "Selected port already in use by: $IS_IN_USE, please choose another one"
			else
				ASK="false"
			fi
		done
fi

# if any warning, ask confirmation to continue or propose to change
if [[ "$confirm" != "" ]] ; then
	echo "There are some warnings..."
	echo "Are you really sure that you want to setup colmena with these parameters?"
	ask_user_continue
else
	ask_user_yn "All is ok, do you want to $ACTION colmena bee" "y"
	if [[ "$RESULT" = "no" ]] ; then
		exit
	fi
fi

#====================================================================================
# START INSTALL/REVERT
#====================================================================================
clear
touch $COLMENA_INSTALL_LOG_FILE
exec > >(tee $COLMENA_INSTALL_LOG_FILE)
exec 2>&1

date
echo "colmena version: $COLMENA_VERSION"
echo "Action requested: $ACTION on server: $OS  $VER  $BITS"
echo "Working directory: $SPATH"
uname -a
echo "Admin user: $ADMIN_USR"
echo "Admin group: $ADMIN_GRP"
echo "Database information provided:"
echo "- Database host: $DB_HOST"
echo "- Database port: $DB_PORT"
echo "- Database name: $DB_NAME"
echo "- Database user: $DB_USER"
echo "- Database pass: -hidden-"
echo "Required software:"
#echo "- nginx web server  => $NGINX"
echo "- mysql database server => $MYSQL"
echo "- nodejs runtime environment=> $NODE"

#====================================================================================
#-- Create directories
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		if [ ! -d $COLMENA_SHR_PATH ]; then
			echo "- Creating colmena directory"
			mkdir -vp $COLMENA_SHR_PATH
			change "" 775 root $ADMIN_GRP $COLMENA_SHR_PATH
		fi
		if [ -d ./test ]; then
			echo "- Preparing test area"
			cp -r ./test /tmp
		fi
		mkdir -vp $COLMENA_SHR_PATH/web
		mkdir -vp $COLMENA_EVENTS_IP
		# Protect dat and log files
		echo "- Protecting install files"
		change "" 640 root $ADMIN_GRP $COLMENA_DATA_FILE
		change "" 640 root $ADMIN_GRP $COLMENA_INSTALL_LOG_FILE
		
		# Copy dat file
		cat $COLMENA_DATA_FILE >> $COLMENA_CFG_PATH/.install.dat
		change "" "750" root $ADMIN_GRP $COLMENA_CFG_PATH/.install.dat
	fi
fi

#====================================================================================
#-- Install colmena-bee scripts
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		# Copy general functions
		echo "- Installing $COLMENA_INSTALL_SRC_PATH files"
		cp -v $COLMENA_INSTALL_SRC_PATH/functions.sh $COLMENA_SHR_PATH
		change "" 660 root root $COLMENA_INSTALL_SRC_PATH/functions.sh
		# Make colmena config file
		echo "- Creating colmena config file"
		echo -e "# Official colmena config file\n#" > $COLMENA_CFG_PATH/colmena.cfg
		echo "# Please do not change the following values" >> $COLMENA_CFG_PATH/colmena.cfg
		GLOBVARS=$(grep "=" "$COLMENA_INSTALL_SRC_PATH/globals.sh" | egrep -v "(SPATH|IFS)=" | egrep -v "(SPATH|_FILE_ID)" | sed -e 's@export @@g')
		echo $GLOBVARS >> $COLMENA_CFG_PATH/colmena.cfg
		change "" 660 root $ADMIN_GRP $COLMENA_CFG_PATH/colmena.cfg
		# Triggers
		echo "- Installing triggers"
		cp -vr $COLMENA_INSTALL_SRC_PATH/triggers $COLMENA_SHR_PATH
		change "" 770 root $ADMIN_GRP $COLMENA_SHR_PATH/triggers
		change "-R" 770 root $ADMIN_GRP $COLMENA_SHR_PATH/triggers/plugins.d
		change "-R" 770 root $ADMIN_GRP $COLMENA_SHR_PATH/triggers/helpers.d
		change "" 770 root $ADMIN_GRP $COLMENA_SHR_PATH/triggers/colmena-triggers
		change "" 770 root $ADMIN_GRP $COLMENA_SHR_PATH/triggers/portscan.sh
		sed -i "s@%%COLMENA_SHR_PATH%%@$COLMENA_SHR_PATH@g" /etc/psad/psad.conf
		sed -i "s@ENABLE_EXT_SCRIPT_EXEC N;@ENABLE_EXT_SCRIPT_EXEC Y;@g" /etc/psad/psad.conf
		sed -i "s@EXEC_EXT_SCRIPT_PER_ALERT N;@EXEC_EXT_SCRIPT_PER_ALERT Y;@g" /etc/psad/psad.conf
		mv $COLMENA_SHR_PATH/triggers/package.json $COLMENA_SHR_PATH
		change "" 750 root $ADMIN_GRP $COLMENA_SHR_PATH/triggers/*.js
		# Blockers
		echo "- Installing blockers"
		cp -vr $COLMENA_INSTALL_SRC_PATH/blockers $COLMENA_SHR_PATH
		change "-R" 750 root $ADMIN_GRP $COLMENA_SHR_PATH/blockers
		# Helpers
		touch $COLMENA_EVENTS_IP/dummy.blk
		# Propagator
		echo "- Installing propagator files"
		cp -vr $COLMENA_INSTALL_SRC_PATH/propagate/* $COLMENA_SHR_PATH
		change "" 750 root $ADMIN_GRP $COLMENA_SHR_PATH/propagator.js
		# Cronjob to run triggers and blocker every 2 hours
		echo "- Creating cron jobs"
		R60=$(shuf -i 0-59 -n 1)
		CRON_CT=$(crontab -l | grep "colmena-triggers")
		if [ -z "$CRON_CT" ]; then
			crontab -l | { cat; echo "$R60 */2 * * * /usr/bin/nice -n 15 $COLMENA_SHR_PATH/triggers/colmena-triggers start --quiet >> $COLMENA_LOG_FILE 2>&1 && /bin/node $COLMENA_SHR_PATH/blockers/stinger.js | /usr/bin/nice -n 15 $COLMENA_SHR_PATH/blockers/venom.sh"; } | crontab -
		fi
		CRON_CP=$(crontab -l | grep "propagator")
		if [ -z "$CRON_CP" ]; then
			crontab -l | { cat; echo "$R60 1-23/2 * * * /usr/bin/nice -n 15 /bin/node $COLMENA_SHR_PATH/propagator.js --quiet >> $COLMENA_LOG_FILE 2>&1"; } | crontab -
		fi
		# Packages
		echo "- Installing external packages please wait"
		CUR_DIR=$(pwd)
		trap '' 2 20
		cd $COLMENA_SHR_PATH
		if [ ! -d $COLMENA_SHR_PATH/node_modules/ip-subnet-calculator ]; then
			npm install ip-subnet-calculator@1.1.8 --save
		fi
		if [ ! -d $COLMENA_SHR_PATH/node_modules/ip-regex ]; then
			npm install ip-regex@4.1.0 --save
		fi
		if [ ! -d $COLMENA_SHR_PATH/node_modules/is-ip ]; then
			npm install is-ip@3.1.0 --save
		fi
		if [ ! -d $COLMENA_SHR_PATH/node_modules/cidr-regex ]; then
			npm install cidr-regex@3.0.0 --save
		fi
		if [ ! -d $COLMENA_SHR_PATH/node_modules/is-cidr ]; then
			npm install is-cidr@4.0.0 --save
		fi
		if [ ! -d $COLMENA_SHR_PATH/node_modules/mysql ]; then
			npm install mysql --save
		fi
		if [ ! -d $COLMENA_SHR_PATH/node_modules/formidable ]; then
			npm install formidable@1.2.2 --save
		fi
		trap 2 20
		cd $CUR_DIR
		# Web component
		echo "- Installing web component file"
		cp -rv $COLMENA_INSTALL_SRC_PATH/web/*.js $COLMENA_SHR_PATH/web
		sed -i "s/%%WEBPORT%%/$WEB_PORT/g" $COLMENA_SHR_PATH/web/index.js
		sed -i "s@%%SERVER_KEY%%@$SERVER_KEY@" $COLMENA_SHR_PATH/web/index.js
		sed -i "s@%%SERVER_PUB%%@$SERVER_PUB@" $COLMENA_SHR_PATH/web/index.js
		WEB_USR=$(grep user /etc/nginx/nginx.conf | sed -e "s@;@@" | sed -e "s@user @@")
		if [ -z "$WEB_USR" ]; then
			WEB_USR="www-data"
		fi
		if [ "$WEB_PORT" -le 1024 ]; then
			DAEMON_USR="root"
			echo "NOTICE: Using colmenad service as user: root, this is risky"
		else
			DAEMON_USR="$WEB_USR"
			echo "NOTICE: Using colmenad service as user: $WEB_USR, which has low privileges"
		fi
		cp -rv $COLMENA_INSTALL_SRC_PATH/web/colmenad.service /etc/systemd/system
		sed -i "s/%%DAEMON_USR%%/$DAEMON_USR/g" /etc/systemd/system/colmenad.service
		systemctl daemon-reload
		systemctl enable colmenad
		service colmenad start
		# Web config
		change "-R" 640 $ADMIN_USR $WEB_USR $COLMENA_SHR_PATH/web
		change "" 750 $ADMIN_USR $WEB_USR $COLMENA_SHR_PATH/web
		if [ -f /etc/nginx/sites-available/$SERVER_FQDN ]; then
			cp -v $COLMENA_INSTALL_CFG_PATH/nginx/server.conf /tmp
			sed -i "s@%%WEBPORT%%@$WEB_PORT@" /tmp/server.conf
			SERVER_CT=$(grep "Colmena server" /etc/nginx/sites-available/$SERVER_FQDN)
			if [ -z "$SERVER_CT" ]; then
				echo "- Updating web server configuration block"
				cp /etc/nginx/sites-available/$SERVER_FQDN /etc/nginx/sites-available/$SERVER_FQDN.bak
				change "" 640 $ADMIN_USR $ADMIN_GRP /etc/nginx/sites-available/$SERVER_FQDN.bak
				tac /etc/nginx/sites-available/$SERVER_FQDN | sed '0,/}/s//# Colmena server/' | tac > /etc/nginx/sites-available/$SERVER_FQDN.tmp
				cp /etc/nginx/sites-available/$SERVER_FQDN.tmp /etc/nginx/sites-available/$SERVER_FQDN
				rm -f /etc/nginx/sites-available/$SERVER_FQDN.tmp
				cat /tmp/server.conf >> /etc/nginx/sites-available/$SERVER_FQDN
			else
				echo "NOTICE: Found previous web server configuration at /etc/nginx/sites-available/$SERVER_FQDN, please verify"
			fi
		else
			cp -v $COLMENA_INSTALL_CFG_PATH/nginx/fqdn.conf /tmp
			sed -i "s@%%WEBPORT%%@$WEB_PORT@" /tmp/fqdn.conf
			sed -i "s@%%SERVER_FQDN%%@$SERVER_FQDN@" /tmp/fqdn.conf
			sed -i "s@%%SERVER_CERT%%@$SERVER_CERT@" /tmp/fqdn.conf
			sed -i "s@%%SERVER_KEY%%@$SERVER_KEY@" /tmp/fqdn.conf
			cp /tmp/fqdn.conf /etc/nginx/sites-available/$SERVER_FQDN
			ln -sf ../sites-available/$SERVER_FQDN /etc/nginx/sites-enabled/$SERVER_FQDN
		fi
		nginx -t
		service nginx reload
		# Nagios Plugin
		if [ -d /usr/lib/nagios/plugins ]; then
			cp $COLMENA_INSTALL_SRC_PATH/nagios/check_colmena.sh /usr/lib/nagios/plugins
			echo "NOTICE: Found nagios plugins directory, you can now configure check_colmena.sh nagios plugin to check colmena security services"
		fi
	fi
fi
 
#====================================================================================
#-- Install database
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		echo "- Installing colmena database"
		# Mysql user and db must be created by root first
		cp $COLMENA_INSTALL_CFG_PATH/database/colmena-v${COLMENA_VERSION}-inst.sql /tmp
		sed -i "s/%%PASS%%/$DB_PASS/g" /tmp/colmena-v${COLMENA_VERSION}-inst.sql
		echo "- Creating user and database, please enter your mysql database root password"
		mysql -u root -p < /tmp/colmena-v${COLMENA_VERSION}-inst.sql
		rm -f /tmp/colmena-v${COLMENA_VERSION}-inst.sql
		echo "- Creating default extra file"
		# Colmena db (MySQL default extra file compatible syntax)
		echo "[client]" > $COLMENA_CFG_PATH/colmena.db.cfg
		echo "host=$DB_HOST" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "port=$DB_PORT" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "user=$DB_USER" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "password=$DB_PASS" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "database=$DB_NAME" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "[server]" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "fqdn=$SERVER_FQDN" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "ip4=$SERVER_IP4" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "ip6=$SERVER_IP6" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "admin=$ADMIN_USR" >> $COLMENA_CFG_PATH/colmena.db.cfg
		echo "group=$ADMIN_GRP" >> $COLMENA_CFG_PATH/colmena.db.cfg
		change "" 660 root $ADMIN_GRP $COLMENA_CFG_PATH/colmena.db.cfg
		echo "- Creating tables"
		# Create colmena database
		mysql --defaults-extra-file=$COLMENA_CFG_PATH/colmena.db.cfg < $COLMENA_INSTALL_CFG_PATH/database/colmena-v${COLMENA_VERSION}.sql
		echo "- Preparing and inserting data"
		HOSTNAME=$(hostname)
		cp $COLMENA_INSTALL_CFG_PATH/database/colmena-v${COLMENA_VERSION}-data.sql /tmp
		sed -i "s@%%HOSTNAME%%@$HOSTNAME@g" /tmp/colmena-v${COLMENA_VERSION}-data.sql
		sed -i "s@%%FQDN%%@$SERVER_FQDN@g" /tmp/colmena-v${COLMENA_VERSION}-data.sql
		sed -i "s@%%IPV4%%@$SERVER_IP4@g" /tmp/colmena-v${COLMENA_VERSION}-data.sql
		sed -i "s@%%IPV6%%@$SERVER_IP6@g" /tmp/colmena-v${COLMENA_VERSION}-data.sql
		# Insert predefined data
		mysql --defaults-extra-file=$COLMENA_CFG_PATH/colmena.db.cfg < /tmp/colmena-v${COLMENA_VERSION}-data.sql
		# Upload servers info
		if [ -f ./colmena-servers.sql ] || [ -L ./colmena-servers.sql ]; then
			echo "- Uploading colmena servers data"
			mysql --defaults-extra-file=$COLMENA_CFG_PATH/colmena.db.cfg < ./colmena-servers.sql
		fi
		echo "- Updating server keys"
		SHARED_SECRET=$(passwordgen 128)
		echo "use colmena; UPDATE server SET privateKey='${COLMENA_CFG_PATH}/ssl/keys/${SERVER_FQDN}-nophrase.key', publicKey='${COLMENA_CFG_PATH}/ssl/keys/${SERVER_FQDN}.pub', sharedSecret='${SHARED_SECRET}' WHERE fqdn='${SERVER_FQDN}';" > /tmp/colmena-v${COLMENA_VERSION}-update.sql
		mysql --defaults-extra-file=$COLMENA_CFG_PATH/colmena.db.cfg < /tmp/colmena-v${COLMENA_VERSION}-update.sql
	fi
fi

# Validate replacements
echo -e "\n-- Validating replacements"
if [[ "$REVERT" = "false" ]] ; then
	# nginx fqdn conf
	if [ -f /etc/nginx/sites-available/$SERVER_FQDN ] ; then
		validate_replacement "%%WEBPORT%%" 	/etc/nginx/sites-available/$SERVER_FQDN
	fi
	if [ -f $COLMENA_INSTALL_CFG_PATH/nginx/fqdn.conf ]; then
		validate_replacement "%%WEBPORT%%" 	/etc/nginx/sites-available/$SERVER_FQDN
		validate_replacement "%%SERVER_FQDN%%" 	/etc/nginx/sites-available/$SERVER_FQDN
		validate_replacement "%%SERVER_CERT%%" 	/etc/nginx/sites-available/$SERVER_FQDN
		validate_replacement "%%SERVER_KEY%%" 	/etc/nginx/sites-available/$SERVER_FQDN
	fi
	if [ -f $COLMENA_SHR_PATH/web/index.js ] ; then
		validate_replacement "%%WEBPORT%%" 	$COLMENA_SHR_PATH/web/index.js
		validate_replacement "%%SERVER_KEY%%"	$COLMENA_SHR_PATH/web/index.js
		validate_replacement "%%SERVER_PUB%%"	$COLMENA_SHR_PATH/web/index.js
	fi
	if [ -f /etc/systemd/system/colmenad.service ] ; then
		validate_replacement "%%DAEMON_USR%%"	/etc/systemd/system/colmenad.service
	fi
	# database
	if [ -f /tmp/colmena-v${COLMENA_VERSION}-inst.sql ] ; then
		validate_replacement "%%PASS%%"	/tmp/colmena-v${COLMENA_VERSION}-inst.sql
		validate_replacement "%%HOSTNAME%%"	/tmp/colmena-v${COLMENA_VERSION}-data.sql
		validate_replacement "%%FQDN%%"	/tmp/colmena-v${COLMENA_VERSION}-data.sql
		validate_replacement "%%IPV4%%"	/tmp/colmena-v${COLMENA_VERSION}-data.sql
		validate_replacement "%%IPV6%%"	/tmp/colmena-v${COLMENA_VERSION}-data.sql
	fi
	# psad
	if [ -f $PSAD_CONFIG/psad.conf ] ; then
		validate_replacement "%%COLMENA_SHR_PATH%%"	$PSAD_CONFIG/psad.conf
	fi
fi

# Check if all services are running
echo -e "\n-- Checking services status"
if [[ "$OS" = "Ubuntu" ]]; then
	$COLMENA_SHR_PATH/triggers/colmena-triggers start
fi

echo ""	
echo "#########################################################"
if [[ "$REVERT" = "false" ]] ; then
	#--- Advise the admin that colmena-bee is now installed and accessible.
	echo " Congratulations colmena bee has been installed "
	echo " on your server. Please review the log file for any error"
	echo " encountered during installation."
	echo ""
	echo " Log file is located at:"
	echo " $COLMENA_INSTALL_LOG_FILE"
	if [[ "$STORE_TREE" = "true" ]] ; then
		echo " Tree files are located at: $CURRENT_DIR"
	fi
	echo ""
	echo " colmena database password is stored"
	echo ""
	echo " For relevant information about security changes please"
	echo " take a look for the NOTICE messages in log file or using"
	echo " the following command:"
	echo "  grep \"NOTICE:\" $COLMENA_INSTALL_LOG_FILE"
	echo ""
else
	#--- Advise the admin that colmena is now uninstalled
	echo " Congratulations colmena has been uninstalled"
	echo ""
	echo " Log file is located at:"
	echo " $COLMENA_INSTALL_LOG_FILE"
fi
echo "#########################################################"
echo ""

IFS="$oIFS"
unset oIFS

###################################################
