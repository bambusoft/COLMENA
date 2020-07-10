#!/usr/bin/env bash

# Official COLMENA Automated Firewall Installer
# =============================================
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
# Parameters: [revert|clean|status]
#	No parameter means install
#	revert - will try to set the original environment to its initial state (to be done)
#	clean  - removes log and tree files (to be done)
#	status - will show services status
SPATH=$(dirname $0)
export SPATH=$(cd $SPATH && pwd)

. $SPATH/source/globals.sh
. /etc/lsb-release
. $SPATH/source/functions.sh

if [ -z "$GLOBALS_LOADED" ] || [ -z "$FUNCTIONS_LOADED" ] ; then
	echo "Unable to load dependency file"
	exit 1
fi

COLMENA_FILE_ID="colmena-fw-$$"
COLMENA_INSTALL_LOG_FILE="./$COLMENA_FILE_ID.log"
COLMENA_DATA_FILE="./$COLMENA_FILE_ID.dat"

# Default user options values, real values will be asked later
STORE_TREE="false"
SUDO_USER=""
SERVER_FQDN=""
SERVER_IP4=""

oIFS="$IFS"
IFS=' '

if [[ "$1" = "clean" ]] ; then
 clear
 clean "fw"
 rm -rf $COLMENA_INSTALL_BKP_PATH
 exit
fi

#====================================================================================
#--- Display the 'welcome' splash/user warning info..
clean "fw"
echo -e "\n#####################################################"
echo "#   Welcome to COLMENA firewall installation script #"
echo "#####################################################"

#====================================================================================
#--- Advanced mode warning and var set
is_opt "--advanced"
ADVANCED="$ISOPTION"

#====================================================================================
# User is requesting to see services status
if [[ "$1" = "status" ]] ; then
	if [ -d $COLMENA_CFG_PATH ] ; then
		clear
		check_status
	else
		echo -e "$COLOR_RED Execution failed: you must install colmena first. $COLOR_END"
	fi
	# System shows status or error and exit
	exit 0
fi

#====================================================================================
# Check if the administrator is requesting to revert colmena
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
		IPSET_BIN="/usr/sbin/ipset"
	else
	    echo -e "$COLOR_YLW WARNING: OS=$OS $VER is OK but is not being supported by colmena team, continue at your own risk $COLOR_END\n"
		IPSET_BIN="/sbin/ipset"
	fi
else
    echo -e "$COLOR_RED Sorry, this OS is not supported by colmena. $COLOR_END\n"
    ask_user_continue
fi

#====================================================================================
# Tree tool used to store file permissions to compare original and final states
if [[ "$STORE_TREE" = "true" ]] ; then
	if [[ "$REVERT" = "false" ]] ; then
		if [ -f /usr/bin/tree ] ; then
			echo "Tree tool is already installed, nice!"
		else
			echo "Installing tree, required to review file permissions"
			$PACKAGE_INSTALLER tree
		fi
	fi
fi

CHECK_FAIL="false"

#====================================================================================
# Check for some common control security packages that we know will affect the installation/operating of colmena.
echo -e "\nChecking for pre-installed security packages"
if [[ "$OS" = "Ubuntu" ]]; then
	# UFW must be disabled
	if [ -e /usr/sbin/ufw ] ; then
	 UFWstatus=$(ufw status | sed -e "s/Status: //")
	 if [[ "$UFWstatus" != "inactive" ]] ; then
		echo -e "$COLOR_RED Execution failed: you must disable UncomplicatedFirewall (UFW) to proceed. $COLOR_END"
		CHECK_FAIL="true"
	 else
		echo -e "$COLOR_GRN UFW is disabled, OK $COLOR_END"
	 fi
	fi
	# iptables ipv4 must be installed by default in Ubuntu 20.04
	if [ -e /usr/sbin/iptables ] ; then
	 iptables_version=$(iptables --version | sed -e "s/iptables //")
	 if [ -z "$iptables_version" ] ; then
		echo -e "$COLOR_RED Execution failed: iptables is not pre-installed/running on this system. $COLOR_END"
		CHECK_FAIL="true"
	 else
	  echo -e "$COLOR_GRN iptables is enabled, OK $COLOR_END"
	 fi
	fi
	# iptables ipv6 must be installed by default in Ubuntu 20.04
	if [ -e /usr/sbin/ip6tables ] ; then
	 ip6tables_version=$(ip6tables --version | sed -e "s/ip6tables //")
	 if [ -z "$ip6tables_version" ] ; then
		echo -e "$COLOR_RED Execution failed: ip6tables is not pre-installed/running on this system. $COLOR_END"
		CHECK_FAIL="true"
	 else
	  echo -e "$COLOR_GRN ip6tables is enabled, OK $COLOR_END"
	 fi
	fi
	# ipset must not be pre-installed
	if [[ "$REVERT" = "false" ]] ; then
		if [ -e $IPSET_BIN ] ; then
			IPSET=$( ${IPSET_BIN} -v )
			echo -e "$COLOR_RED Execution failed: ipset is pre-installed on this system. $COLOR_END"
			echo " It appears that an IP sets manager is already installed on your server;"
			CHECK_FAIL="true"
		 else
		  echo -e "$COLOR_GRN ipset is not installed, OK $COLOR_END"
		fi
	fi
	# fail2ban must not be pre-installed
	if [[ "$REVERT" = "false" ]] ; then
		if [ -e /etc/init.d/fail2ban ] ; then
			FAIL2BAN=$(/usr/bin/fail2ban-client -V)
			echo -e "$COLOR_RED Execution failed: fail2ban is pre-installed on this system. $COLOR_END"
			echo " It appears that a failure log scanner is already installed on your server;"
			CHECK_FAIL="true"
		 else
		  echo -e "$COLOR_GRN fail2ban is not installed, OK $COLOR_END"
		fi
	fi
	# knockd must not be pre-installed
	if [[ "$REVERT" = "false" ]] ; then
		if [ -e /usr/sbin/knockd ] ; then
			KNOCKD=$(/usr/sbin/knockd -V)
			echo -e "$COLOR_RED Execution failed: knockd is pre-installed on this system. $COLOR_END"
			echo " It appears that a sequence ports manager is already installed on your server;"
			CHECK_FAIL="true"
		else
		  echo -e "$COLOR_GRN knockd is not installed, OK $COLOR_END"
		fi
	fi
	if [ $CHECK_FAIL = "true" ]; then
		echo -e "\n This installer is designed to install and configure colmena firewall on a clean OS installation only!"
		echo " Please re-install your OS before attempting to install colmena firewall using this script."
		ask_user_continue
	fi
else
    echo -e "$COLOR_YLW WARNING: OS=$OS $VER is not being suported by colmena team, packages not checked $COLOR_END\n"
fi
echo ""

#====================================================================================
# Obtain important user input
if [[ "$REVERT" = "false" ]] ; then
	# Current user/group and administrator(sudoer) user/group
	echo "Some installations require more security than others, you may want to"
	echo "have an unprivileged user to change configurations only, or you want to"
	echo "have more than one administrator, all of them belonging to an administration"
	echo "group, so you have three choices to select user/group names below:"
	echo ''
	echo "	adminuser/adminuser (which is in the sudoers list)"
	echo "	adminuser/admingroup (adminuser is in the sudoers list)"
	echo "	root/root (more secure but risky at the same time)"
	echo ''
	echo "In doubt, please use the default values or root/root if you know what you are doing"
	echo ''
	if [ -z "$SUDO_USER" ] ; then
		ADMIN_USR="root"
		ADMIN_GRP="root"
	else
		ADMIN_USR=$SUDO_USER
		ADMIN_GRP=$(id -g -n $ADMIN_USR)
	fi
	ask_data " Please enter administrative user name" "$ADMIN_USR"
	ADMIN_USR="$answer"
	if [ -z "$ADMIN_USR" ] ; then
		ADMIN_USR="root"
	else
		EXIST=$(grep "$ADMIN_USR:" /etc/passwd)
		if [ -z "$EXIST" ] ; then
			echo -e "$COLOR_RED Execution failed: administrative user does not exist. $COLOR_END"
			ask_user_continue
		fi
	fi
	ask_data " Please enter administrative group name" "$ADMIN_GRP"
	ADMIN_GRP="$answer"
	if [ -z "$ADMIN_GRP" ] ; then
		ADMIN_GRP="root"
	else
		EXIST=$(grep "$ADMIN_GRP:" /etc/group)
		if [ -z "$EXIST" ] ; then
			echo -e "$COLOR_RED Execution failed: administrative group does not exist. $COLOR_END"
			ask_user_continue
		fi
	fi
	IS_MEMBER=$(groups "$ADMIN_USR" | grep "$ADMIN_GRP")
	if [ -z "$IS_MEMBER" ]; then
		echo -e "$COLOR_RED Execution failed: User does not belong to group $ADMIN_GRP. $COLOR_END"
		ask_user_continue
	fi
	if [[ "$ADMIN_USR" != "root" ]]; then 
		IS_SUDOER=$(groups "$ADMIN_USR" | grep sudo)
		if [ -z "$IS_SUDOER" ]; then
			echo -e "$COLOR_YLW Warning:$COLOR_END Using $ADMIN_USR : $ADMIN_GRP as the administrative username:groupame, but this user is not in sudoers"
			confirm="true"
		else
			echo -e "Using:$COLOR_GRN $ADMIN_USR : $ADMIN_GRP $COLOR_END as the administrative username:groupame"
		fi
	fi
	echo "ADMIN_USR=$ADMIN_USR" > $COLMENA_DATA_FILE
	echo "ADMIN_GRP=$ADMIN_GRP" >> $COLMENA_DATA_FILE
	echo ""
	# CA root password
	SSL_PASS=$(passwordgen)
    echo ' Please provide a strong password to use with a CA root key to (auto)generate SSL server certificate.'
	ask_data "Enter CA root key passord" "$SSL_PASS"
	SSL_PASS="$answer"
	echo "CA_ROOT=$SSL_PASS" >> $COLMENA_DATA_FILE
	# Server FQDN
    echo ' Please provide the subdomain that you want to use to access colmena panel,'
    echo ' - do not use your main domain (like domain.com)'
    echo ' - use a subdomain, e.g colmena.domain.com'
    echo ' - or use the server hostname, e.g bee01.domain.com'
    echo ' - DNS must already be configured and pointing to the server IP'
    echo '   for this sub-domain'
	if [ -z "$SERVER_FQDN" ]; then
		SERVER_FQDN="$(/bin/hostname)"
	fi
	ask_data "Enter the subdomain you want to access colmena panel" "$SERVER_FQDN"
	SERVER_FQDN="$answer"
	# Checks if the panel domain is a subdomain
	sub=$(echo "$SERVER_FQDN" | sed -n 's|\(.*\)\..*\..*|\1|p')
	if [[ "$sub" == "" ]]; then
		echo -e "$COLOR_YLW WARNING: $SERVER_FQDN is not a subdomain! $COLOR_END"
		confirm="true"
	fi
	# Server IPs
    echo ' Please provide the public IP addresses of this server.'
	if [ -z "$SERVER_FQDN" ]; then
		SERVER_IP4="$(/usr/bin/dig +short $SERVER_FQDN A)"
		SERVER_IP6="$(/usr/bin/dig +short $SERVER_FQDN AAAA)"
	fi
	ask_data " Enter the public IPv4 for this server" "$SERVER_IP4"
	SERVER_IP4="$answer"
	if [[ $SERVER_IP4 == *":"* ]]; then
		IPV="has address"
		POS="-f5"
		cout=$(ip addr show | awk '$1 == "inet6" && $4 == "global" { sub (/\/.*/,""); print $2 }' | sed ':a;N;$!ba;s/\n/ /g')
		sarray=($cout)
		local_ip4=${sarray[0]}
	else
		IPV="IPv6"
		POS="-f4"
		cout=$(ip addr show | awk '$1 == "inet" && $3 == "brd" { sub (/\/.*/,""); print $2 }' | sed ':a;N;$!ba;s/\n/ /g')
		sarray=($cout)
		local_ip4=${sarray[0]}
	fi
	dns_panel_ip4=$(host "$SERVER_FQDN" | grep "address" | egrep -v "$IPV" | cut -d" " "$POS")
	if [[ "$SERVER_IP4" != "$local_ip4" ]]; then
		echo -e "\nThe public IPv4 of the server is $SERVER_IP4.\nIts local IP is $local_ip4"
		echo "  For a production server, the PUBLIC IPv4 must be used."
	fi  
	# Checks if the panel domain is already assigned in DNS, with just IPv4 is fine
	if [[ "$dns_panel_ip4" == "" ]]; then
		echo -e "$COLOR_RED WARNING: $SERVER_FQDN is not defined in your DNS!$COLOR_END"
		echo "  You must add records in your DNS manager (and then wait until propagation is done)."
		echo "  If this is a production installation, set the DNS up as soon as possible."
		confirm="true"
	else
		echo -e "$COLOR_GRN OK: DNS successfully resolves $SERVER_FQDN to $dns_panel_ip4.$COLOR_END"
		# Check if panel domain matches public IP
		if [[ "$dns_panel_ip4" != "$SERVER_IP4" ]]; then
			echo -e -n "$COLOR_YLW WARNING: $SERVER_FQDN DNS record ($dns_panel_ip4) does not point to $SERVER_IP4!$COLOR_END"
			echo "  Colmena will not be reachable from http://$SERVER_FQDN"
			confirm="true"
		fi
	fi
	if [[ "$dns_panel_ip4" != "$SERVER_IP4" && "$SERVER_IP4" != "$local_ip4" ]]; then
		echo -e -n "$COLOR_YLW WARNING: $SERVER_IP4 does not match detected IP !$COLOR_END"
		echo "  Colmena will not work with this IP..."
		confirm="true"
	fi
	SYS_HAS_IP6=$(ip addr show | awk '$1 == "inet6" && $4 == "global" { sub (/\/.*/,""); print $2 }' | sed ':a;N;$!ba;s/\n/ /g')
	if [ -n "$SYS_HAS_IP6" ]; then
		ask_data " Enter the public IPv6 for this server" "$SERVER_IP6"
		SERVER_IP6="$answer"
		if [[ $SERVER_IP6 == *":"* ]]; then
			IPV="has address"
			POS="-f5"
			cout=$(ip addr show | awk '$1 == "inet6" && $4 == "global" { sub (/\/.*/,""); print $2 }' | sed ':a;N;$!ba;s/\n/ /g')
			sarray=($cout)
			local_ip6=${sarray[0]}
		else
			IPV="IPv6"
			POS="-f4"
			cout=$(ip addr show | awk '$1 == "inet" && $3 == "brd" { sub (/\/.*/,""); print $2 }' | sed ':a;N;$!ba;s/\n/ /g')
			sarray=($cout)
			local_ip6=${sarray[0]}
		fi
		dns_panel_ip6=$(host "$SERVER_FQDN" | grep "address" | egrep -v "$IPV" | cut -d" " "$POS")
		if [[ "$SERVER_IP6" != "$local_ip6" ]]; then
			echo -e "\nThe public IPv6 of the server is $SERVER_IP6.\nIts local IP is $local_ip6"
			echo "  For a production server, the PUBLIC IPv6 must be used."
		fi  
		echo ""
		# Checks if the panel domain is already assigned in DNS, with just IPv4 is fine
		if [[ "$dns_panel_ip6" == "" ]]; then
			echo -e "$COLOR_RED WARNING: $SERVER_FQDN is not defined in your DNS!$COLOR_END"
			echo "  You must add records in your DNS manager (and then wait until propagation is done)."
			echo "  If this is a production installation, set the DNS up as soon as possible."
			confirm="true"
		else
			echo -e "$COLOR_GRN OK: DNS successfully resolves $SERVER_FQDN to $dns_panel_ip6.$COLOR_END"
			# Check if panel domain matches public IP
			if [[ "$dns_panel_ip6" != "$SERVER_IP6" ]]; then
				echo -e -n "$COLOR_YLW WARNING: $SERVER_FQDN DNS record ($dns_panel_ip6) does not point to $SERVER_IP6!$COLOR_END"
				echo "  Colmena will not be reachable from http://$SERVER_FQDN"
				confirm="true"
			fi
		fi
		if [[ "$dns_panel_ip6" != "$SERVER_IP6" && "$SERVER_IP6" != "$local_ip6" ]]; then
			echo -e -n "$COLOR_YLW WARNING: $SERVER_IP6 does not match detected IPv6 !$COLOR_END"
			echo "  Colmena will not work with this IPv6..."
			confirm="true"
		fi
	else
		SERVER_IP6='::/128'
	fi
	echo "SERVER_FQDN=$SERVER_FQDN" >> $COLMENA_DATA_FILE
	echo "SERVER_IP4=$SERVER_IP4" >> $COLMENA_DATA_FILE
	echo "SERVER_IP6=$SERVER_IP6" >> $COLMENA_DATA_FILE
else
	ADMIN_USR=$(grep "ADMIN_USR" $COLMENA_DATA_FILE | sed "s@ADMIN_USR:@@")
	ADMIN_GRP=$(grep "ADMIN_GRP" $COLMENA_DATA_FILE | sed "s@ADMIN_GRP:@@")
fi

# if any warning, ask confirmation to continue or propose to change
if [[ "$confirm" != "" ]] ; then
	echo "There are some warnings..."
	echo "Are you really sure that you want to setup colmena firewall with these parameters?"
	ask_user_continue
else
	ask_user_yn "All is ok, do you want to $ACTION colmena firewall" "y"
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

cout=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | sed ':a;N;$!ba;s/\n/ /g')
sarray=($cout)
IFACE=${sarray[0]}

date
echo "colmena version: $COLMENA_VERSION"
echo "Action requested: $ACTION on server: $OS  $VER  $BITS"
echo "Working directory: $SPATH"
uname -a
echo "Distribution Id=$DISTRIB_ID"
echo "Distribution release=$DISTRIB_RELEASE"
echo "Distribution code name=$DISTRIB_CODENAME"
echo "Distribution description=$DISTRIB_DESCRIPTION"
echo "Admin user: $ADMIN_USR"
echo "Admin group: $ADMIN_GRP"
echo "Fully Qualified Domain Name (FQDN): $SERVER_FQDN"
echo "Interface: $IFACE"
echo "Local IPv4: $local_ip4"
echo "Public IPv4: $SERVER_IP4"
echo "Local IPv6: $local_ip6"
echo "Public IPv6: $SERVER_IP6"
echo "Required software:"
echo "- iptables firewall => $iptables_version"
echo "- ip6tables firewall => $ip6tables_version"
echo "- ip sets manager => $IPSET"
echo "- fail2ban failure log scanner => $FAIL2BAN"
echo "- knockd sequence port manager => $KNOCKD"

if [[ "$STORE_TREE" = "true" ]] ; then
	# Store original file permissions
	echo "--Storing original file permissions"
	if [ -f $COLMENA_FILE_ID.1st ] ; then
		truncate -s 0 $COLMENA_FILE_ID.1st
	fi
	save_tree $COLMENA_CFG_PATH 1st
	save_tree $IPTABLES_CONFIG 1st
	save_tree $FAIL2BAN_CONFIG 1st
fi

#--- Get current sshd port to avoid administrative blocking by new firewall rules
echo -e "\n-- Obtaining current sshd port"
SSHD_PORT=$(cat /etc/ssh/sshd_config | grep "Port" | egrep -v "Gate" | sed -e "s/\#*Port //")
if ! [[ "$SSHD_PORT" =~ ^[0-9]+$ ]] ; then
   echo "NOTICE: Could not determine current SSH port number, using default."
   echo "You must configure the SSH port if this is not the port you are using to connect to this server"
   echo "otherwise, you will be blocked to access the server"
   SSHD_PORT=22;
fi
if [[ "$SSHD_PORT" = "22" ]]; then
	echo -e -n "You are encouraged to change the default SSH port."
fi
echo -e "\nSSH Port: $SSHD_PORT"

#====================================================================================
#-- Create directories
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		if [ ! -d $IPTABLES_CONFIG ]; then
			mkdir -vp $IPTABLES_CONFIG
			change "" 770 $ADMIN_USR $ADMIN_GRP $IPTABLES_CONFIG
		fi
		echo -e "\n-- Creating install backup directories"
		mkdir -vp $COLMENA_INSTALL_BKP_PATH/iptables
		change "-R" 750 $ADMIN_USR $ADMIN_GRP $COLMENA_INSTALL_BKP_PATH
		echo -e "\n-- Creating colmena config directory"
		mkdir -vp $COLMENA_CFG_PATH/ssl/{requests,keys,certs}
		change "" 770 $ADMIN_USR $ADMIN_GRP $COLMENA_CFG_PATH/ssl/{,requests,keys,certs}
		echo -e "\n-- Creating colmena log directory"
		mkdir -vp $COLMENA_LOG_PATH
		touch $COLMENA_LOG_PATH/colmena.log
		change "-R" 770 $ADMIN_USR $ADMIN_GRP $COLMENA_LOG_PATH
	fi
fi

#====================================================================================
#--- Stop current security services in every case (revert|install)
echo -e "\n-- Stopping security services"
if [[ "$OS" = "Ubuntu" ]]; then
	if [[ "$UFWstatus" != "inactive" ]] ; then
		ufw disable
	fi
	if [ -n "$iptables_version" ] ; then
		if [[ "$REVERT" = "false" ]] ; then	
			if [ -f $COLMENA_INSTALL_BKP_PATH/iptables/ip4tables.txt ] ; then
				echo "ip4tables rules file already backed up"
			else
				iptables-save > $COLMENA_INSTALL_BKP_PATH/iptables/ip4tables.txt
				echo "ip4tables backed up => $COLMENA_INSTALL_BKP_PATH/iptables/ip4tables.txt"
			fi
		fi
		echo "Cleaning ipv4 firewall rules"
		iptables -X
		iptables -t nat -F
		iptables -t nat -X
		iptables -t mangle -F
		iptables -t mangle -X
		iptables -P INPUT ACCEPT
		iptables -P FORWARD ACCEPT
		iptables -P OUTPUT ACCEPT
	fi
	if [ -n "$ip6tables_version" ] ; then
		if [[ "$REVERT" = "false" ]] ; then
			if [ -f $COLMENA_INSTALL_BKP_PATH/iptables/ip6tables.txt ] ; then
				echo "ip6tables rules file already backed up"
			else
				ip6tables-save > $COLMENA_INSTALL_BKP_PATH/iptables/ip6tables.txt
				echo "ip6tables backed up => $COLMENA_INSTALL_BKP_PATH/iptables/ip6tables.txt"
			fi
		fi
		echo "Cleaning ipv6 firewall rules"
		ip6tables -X
		ip6tables -t mangle -F
		ip6tables -t mangle -X
		ip6tables -P INPUT ACCEPT
		ip6tables -P FORWARD ACCEPT
		ip6tables -P OUTPUT ACCEPT
	fi
	if [ -e /etc/init.d/fail2ban ] ; then
		if [ -d $COLMENA_INSTALL_BKP_PATH/fail2ban ] ; then
			echo "fail2ban configuration already backed up => $COLMENA_INSTALL_BKP_PATH/fail2ban"
		else
			cp -r $FAIL2BAN_CONFIG $COLMENA_INSTALL_BKP_PATH/fail2ban
		fi
		echo "Stopping fail2ban service, please wait"
		/etc/init.d/fail2ban stop
		# Wait to fail2ban stop
		x=$(ps -ef | grep fail2ban-server | grep -v grep | awk '{print $2}' | wc -l)
		while [ $x -ge 1 ]
			do
				ps -ef | grep fail2ban-server | grep -v grep | awk '{print $2}' | xargs kill -SIGTERM
				sleep 3
				x=$(ps -ef | grep fail2ban-server | grep -v grep | awk '{print $2}' | wc -l)
				echo "Wait for: $x fail2ban process(es)"
			done
	fi
	if [ -e /usr/sbin/ipset ] ; then
		echo "Cleaning ip sets"
		/usr/sbin/ipset flush
		/usr/sbin/ipset list | grep "Name"
	fi
	if [ -e /etc/init.d/knockd ] ; then
		/etc/init.d/knockd stop
	fi
fi
change "-R" 770 $ADMIN_USR $ADMIN_GRP $COLMENA_INSTALL_BKP_PATH

# WARNING: At this point firewall is accepting everything and fail2ban is down

#====================================================================================
#--- Install or remove general security packages
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		echo -e "\n-- Downloading and installing required security tools..."
		$PACKAGE_INSTALLER openssl iptables netfilter-persistent fail2ban ipset knockd
	fi
else
	if [[ "$OS" = "Ubuntu" ]]; then
		echo -e "\n-- Removing installed tools..."
		$PACKAGE_REMOVER expect fail2ban knockd
		# Remove iptables is a bad idea, we will set to minimal(required) open ports later
		# Remove ipset is a bad idea we will diasble and flush lists later
	fi
fi

#====================================================================================
#--- Install or restore original configurations
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		# iptables
		cp -v $COLMENA_INSTALL_CFG_PATH/iptables/iptables.firewall.rules $COLMENA_CFG_PATH/iptables.firewall.rules
		sed -i "s@%%SSHDPORT%%@$SSHD_PORT@" $COLMENA_CFG_PATH/iptables.firewall.rules
		ln -sf $COLMENA_CFG_PATH/iptables.firewall.rules $IPTABLES_CONFIG/iptables.firewall.rules
		cp -v $COLMENA_INSTALL_CFG_PATH/iptables/ip6tables.firewall.rules $COLMENA_CFG_PATH/ip6tables.firewall.rules
		sed -i "s@%%SSHDPORT%%@$SSHD_PORT@" $COLMENA_CFG_PATH/ip6tables.firewall.rules
		ln -sf $COLMENA_CFG_PATH/ip6tables.firewall.rules $IPTABLES_CONFIG/ip6tables.firewall.rules
		if [ -d /etc/network ]; then
			ln -sf $COLMENA_CFG_PATH/iptables.firewall.rules /etc/network/iptables.up.rules
			ln -sf $COLMENA_CFG_PATH/ip6tables.firewall.rules /etc/network/ip6tables.up.rules
		fi
		# colmena
		change "-R" "660" $ADMIN_USR $ADMIN_GRP $COLMENA_CFG_PATH
		change "" "770" $ADMIN_USR $ADMIN_GRP $COLMENA_CFG_PATH
		cp -v $COLMENA_INSTALL_CFG_PATH/logrotate-colmena $LOGROTATE_PATH/colmena
		sed -i "s@%%USR%%@$ADMIN_USR@" $LOGROTATE_PATH/colmena
		sed -i "s@%%GRP%%@$ADMIN_GRP@" $LOGROTATE_PATH/colmena
		change "" "644" root root $LOGROTATE_PATH/colmena
		# fail2ban
		FAIL2BAN_INSTALL_CFG_FILE="$COLMENA_INSTALL_CFG_PATH/fail2ban/jail-Ubuntu-${VER}.local"
		cp -v $FAIL2BAN_INSTALL_CFG_FILE  $FAIL2BAN_CONFIG/jail.local
		sed -i "s@%%IGNOREIP%%@$SERVER_IP4@g" $FAIL2BAN_CONFIG/jail.local
		sed -i "s@%%SERVERFQDN%%@SERVER_FQDN@g" $FAIL2BAN_CONFIG/jail.local
		sed -i "s@%%SSHDPORT%%@$SSHD_PORT@g" $FAIL2BAN_CONFIG/jail.local
		change "" "660" $ADMIN_USR $ADMIN_GRP $FAIL2BAN_CONFIG/jail.local
		cp -v $COLMENA_INSTALL_CFG_PATH/fail2ban/filter.d/*.conf $FAIL2BAN_CONFIG/filter.d
		change "" "664" $ADMIN_USR $ADMIN_GRP $FAIL2BAN_CONFIG/filter.d/colmena*
		cp -v $COLMENA_INSTALL_CFG_PATH/fail2ban/logrotate-fail2ban $LOGROTATE_PATH/fail2ban
		change "" "644" root root $LOGROTATE_PATH/fail2ban
		# knockd
		cp -v $COLMENA_INSTALL_CFG_PATH/knockd/knockd.default /etc/default/knockd
		sed -i "s@%%IFACE%%@$IFACE@g" /etc/default/knockd
		echo "NOTICE: Please verify that $IFACE interface is active or change it."
		change "" "664" root $ADMIN_GRP /etc/default/knockd
		cp -v $COLMENA_INSTALL_CFG_PATH/knockd/knockd.conf /etc/knockd.conf
		change "" "664" root $ADMIN_GRP /etc/knockd.conf
	fi
fi

#====================================================================================
#--- Openssl dummy certificate, you need to change this using real data or use a valid certificate
echo -e "\n-- Openssl certificates"
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		if [ -f $COLMENA_CFG_PATH/ssl/certindex.txt ]; then
			rm -f $COLMENA_CFG_PATH/ssl/{certindex.txt*,serial*,requests/*,keys/*,certs/*}
		fi
		cp $COLMENA_INSTALL_CFG_PATH/ssl/ssl.cnf $COLMENA_CFG_PATH/ssl
		touch $COLMENA_CFG_PATH/ssl/certindex.txt
		echo "01" > $COLMENA_CFG_PATH/ssl/serial
		change "" "640" root $ADMIN_GRP $COLMENA_CFG_PATH/ssl/{certindex.txt,serial}
		echo "Creating new CA root"
		openssl genrsa -des3 -passout pass:$SSL_PASS -out $COLMENA_CFG_PATH/ssl/keys/root-ca.key 4096
		echo "Generating root-ca certificate"
		openssl req -new -x509 -passin pass:$SSL_PASS -days 365 -subj "/C=MX/ST=Jalisco/L=Guadalajara/O=Colmena Ltd/OU=colmena.bambusoft.com/CN=colmena/emailAddress=root@${SERVER_FQDN}" -key $COLMENA_CFG_PATH/ssl/keys/root-ca.key -out $COLMENA_CFG_PATH/ssl/certs/root-ca.crt -config $COLMENA_INSTALL_CFG_PATH/ssl/ssl.cnf
		echo "Generating root-ca PEM files please provide previously rootCA password"
		openssl x509 -inform PEM -in $COLMENA_CFG_PATH/ssl/certs/root-ca.crt > $COLMENA_CFG_PATH/ssl/certs/root-ca.pem
		openssl rsa -passin pass:$SSL_PASS -in $COLMENA_CFG_PATH/ssl/keys/root-ca.key -text > $COLMENA_CFG_PATH/ssl/keys/root-ca.pem
		echo "Generating server: $SERVER_FQDN certificate request"
		openssl req -newkey rsa:4096  -subj "/C=MX/ST=Jalisco/L=Guadalajara/O=Colmena Ltd/OU=Colmena Certification Authority/CN=${SERVER_FQDN}/emailAddress=root@${SERVER_FQDN}" -keyout $COLMENA_CFG_PATH/ssl/keys/${SERVER_FQDN}.key -nodes -out $COLMENA_CFG_PATH/ssl/requests/${SERVER_FQDN}.req -config $COLMENA_INSTALL_CFG_PATH/ssl/ssl.cnf
		echo "Generating server: $SERVER_FQDN certificate"
		printf 'y\ny\n' | openssl ca -passin pass:$SSL_PASS -config $COLMENA_INSTALL_CFG_PATH/ssl/ssl.cnf -days 365 -out $COLMENA_CFG_PATH/ssl/certs/${SERVER_FQDN}.crt -infiles $COLMENA_CFG_PATH/ssl/requests/${SERVER_FQDN}.req
		echo "Supressing $SERVER_FQDN certificate password for web server"
		openssl rsa -in $COLMENA_CFG_PATH/ssl/keys/${SERVER_FQDN}.key -out $COLMENA_CFG_PATH/ssl/keys/${SERVER_FQDN}-nophrase.key
		change "-R" "g+rw" root $ADMIN_GRP $COLMENA_CFG_PATH/ssl
		find $COLMENA_CFG_PATH/ssl -type d -exec chmod 750 {} +
		find $COLMENA_CFG_PATH/ssl -type f -exec chmod 640 {} +
		change "" "600" root root $COLMENA_CFG_PATH/ssl/keys/root-ca.*
		change "" "640" root $ADMIN_GRP $COLMENA_CFG_PATH/ssl/keys/${SERVER_FQDN}.key
		change "" "640" root $ADMIN_GRP $COLMENA_CFG_PATH/ssl/keys/${SERVER_FQDN}-nophrase.key
		echo "NOTICE: Self signed certificates for CA and server was created"
	fi
fi

#====================================================================================
#--- ipset to set IP blacklists
echo -e "\n-- ipset security"
if [[ "$REVERT" = "false" ]] ; then
	if [[ "$OS" = "Ubuntu" ]]; then
		#ipv4
	 	ipset destroy BLACKLIST_IP -q
		ipset create BLACKLIST_IP hash:ip hashsize 2048 -q
		ipset flush BLACKLIST_IP
		ipset destroy BLACKLIST_NET -q
		ipset create BLACKLIST_NET hash:net hashsize 1024 -q
		ipset flush BLACKLIST_NET
		ipset add BLACKLIST_IP 64.139.139.20
		ipset add BLACKLIST_NET 64.139.139.20/28
		#ipv6
	 	ipset destroy BLACKLIST_IP6 -q
		ipset create BLACKLIST_IP6 hash:ip family inet6 hashsize 2048 -q
		ipset flush BLACKLIST_IP6
		ipset destroy BLACKLIST_NET6 -q
		ipset create BLACKLIST_NET6 hash:net family inet6 hashsize 1024 -q
		ipset flush BLACKLIST_NET6
		ipset add BLACKLIST_IP6 2a04:4e42::81
		echo "NOTICE: ipset blacklists are set, be aware that this may block legitimate IPs"
	fi
else
	if [[ "$OS" = "Ubuntu" ]]; then
		ipset flush BLACKLIST_IP -q
		ipset flush BLACKLIST_NET -q
		ipset flush BLACKLIST_IP6 -q
		ipset flush BLACKLIST_NET6 -q
	fi
fi

#====================================================================================
#--- Enabling firewall
echo -e "\n-- Setting basic firewall rules"
echo "NOTICE: Allowing ssh port number: $SSHD_PORT in firewall and closing all other ssh ports"
# Check for better firewall rules availability
if [[ "$OS" = "Ubuntu" ]]; then
	if [ -d $COLMENA_CFG_PATH ] ; then
		iptables-restore < $COLMENA_CFG_PATH/iptables.firewall.rules
		ip6tables-restore < $COLMENA_CFG_PATH/ip6tables.firewall.rules
	else
		# Rules are deleted (called revert more than once?), so set basic (colmena required) rules
		# ipv4
		if [ -n "$iptables_version" ] ; then
			iptables --flush
			echo "Set ipv4 firewall with very basic rules"
			iptables -A INPUT -i lo -j ACCEPT
			iptables -A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT
			iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
			iptables -A OUTPUT -j ACCEPT
			iptables -A INPUT -m state --state INVALID -j DROP
			#iptables -A INPUT -p tcp --dport 21 -j ACCEPT
			#iptables -A INPUT -p tcp --dport 25 -j ACCEPT
			#iptables -A INPUT -p tcp --dport 53 -j ACCEPT
			#iptables -A INPUT -p udp --dport 53 -j ACCEPT
			iptables -A INPUT -p tcp --dport 80 -j ACCEPT
			#iptables -A INPUT -p tcp --dport 110 -j ACCEPT
			#iptables -A INPUT -p tcp --dport 115 -j ACCEPT
			#iptables -A INPUT -p tcp --dport 465 -j ACCEPT
			iptables -A INPUT -p tcp --dport 443 -j ACCEPT
			#iptables -A INPUT -p tcp --dport 995 -j ACCEPT
			iptables -A INPUT -p tcp -m state --state NEW --dport $SSHD_PORT -j ACCEPT
			iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT --match limit --limit 30/minute
			iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "colmena ip4 denied: " --log-level 7
			iptables -A INPUT -j REJECT
			iptables -A FORWARD -j REJECT
		fi
		# ipv6
		if [ -n "$ip6tables_version" ] ; then
			ip6tables --flush
			echo "Set ipv6 firewall with very basic rules"
			ip6tables -A INPUT -s ::1 -d ::1 -j ACCEPT
			ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
			ip6tables -A OUTPUT -j ACCEPT
			ip6tables -A INPUT -m state --state INVALID -j DROP
			ip6tables -A INPUT -i eth0 -p ipv6 -j ACCEPT 
			ip6tables -A OUTPUT -o eth0 -p ipv6 -j ACCEPT 
			#ip6tables -A INPUT -p tcp --dport 21 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 25 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 53 -j ACCEPT
			#ip6tables -A INPUT -p udp --dport 53 -j ACCEPT
			ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 110 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 115 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 465 -j ACCEPT
			#ip6tables -A INPUT -p tcp --dport 995 -j ACCEPT
			ip6tables -A INPUT -p tcp -m state --state NEW --dport $SSHD_PORT -j ACCEPT
			ip6tables -A INPUT -p icmpv6 -j ACCEPT
			ip6tables -A FORWARD -j REJECT --reject-with icmp6-adm-prohibited
			ip6tables -A INPUT --protocol icmpv6 --icmpv6-type echo-request -j ACCEPT --match limit --limit 30/minute
			ip6tables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "colmena ip6 denied: " --log-level 7
			ip6tables -A INPUT -j REJECT
			ip6tables -A FORWARD -j REJECT
		fi
	fi
fi

# Save persistant rules
if [[ "$OS" = "Ubuntu" ]]; then
	iptables-save > $IPTABLES_CONFIG/rules.v4
	ip6tables-save > $IPTABLES_CONFIG/rules.v6
	change "" "660" root $ADMIN_GRP $IPTABLES_CONFIG/rules.*
fi

#====================================================================================
#--- colmena persistent
if [[ "$OS" = "Ubuntu" ]]; then
	if [[ "$REVERT" = "false" ]] ; then
		cp -v $COLMENA_INSTALL_SRC_PATH/colmena /usr/sbin/colmena
		change "" "750" root $ADMIN_GRP /usr/sbin/colmena
		cp -v $COLMENA_INSTALL_SRC_PATH/netfilter/netfilter-persistent /usr/sbin/netfilter-persistent
		change "" "755" root $ADMIN_GRP /usr/sbin/netfilter-persistent
		cp -v $COLMENA_INSTALL_SRC_PATH/netfilter/plugins/* /usr/share/netfilter-persistent/plugins.d/
		change "-R" "755" root $ADMIN_GRP /usr/share/netfilter-persistent/plugins.d
		cp -v $COLMENA_INSTALL_SRC_PATH/init.d/fail2ban-${VER} /etc/init.d/fail2ban
		change "" "755" root $ADMIN_GRP /etc/init.d/fail2ban
	fi
fi

#====================================================================================
#--- Restart firewall (ipset+iptables+fail2ban+knockd)
if [[ "$REVERT" = "false" ]] ; then
	if [ -f /usr/sbin/colmena ]; then
		echo "Starting colmena via installer"
		/usr/sbin/colmena start
	fi
fi

if [[ "$STORE_TREE" = "true" ]] ; then
	# Store final file permissions
	echo "--Storing final file permissions"
	if [ -f sentora-paranoid-$$.2nd ] ; then
		truncate -s 0 sentora-paranoid-$$.2nd
	fi
	save_tree $COLMENA_CFG_PATH 1st
	save_tree $IPTABLES_CONFIG 1st
	save_tree $FAIL2BAN_CONFIG 1st
fi

# Validate replacements
echo -e "\n-- Validating replacements"
if [[ "$REVERT" = "false" ]] ; then
	# iptables
	if [ -f $COLMENA_CFG_PATH/iptables.firewall.rules ] ; then
		validate_replacement %%SSHDPORT%%	$COLMENA_CFG_PATH/iptables.firewall.rules
	fi
	# ip6tables
	if [ -f $COLMENA_CFG_PATH/ip6tables.firewall.rules ] ; then
		validate_replacement %%SSHDPORT%%	$COLMENA_CFG_PATH/ip6tables.firewall.rules
	fi
	# logrotate
	if [ -f $LOGROTATE_PATH/colmena ] ; then
		validate_replacement %%USR%%	$LOGROTATE_PATH/colmena
		validate_replacement %%GRP%%	$LOGROTATE_PATH/colmena
	fi
	# fail2ban
	if [ -f $FAIL2BAN_CONFIG/fail2ban/jail.local ] ; then
		validate_replacement %%IGNOREIP%%	$FAIL2BAN_CONFIG/jail.local
		validate_replacement %%SERVERFQDN%%	$FAIL2BAN_CONFIG/jail.local
		validate_replacement %%SSHDPORT%%	$FAIL2BAN_CONFIG/jail.local
	fi
fi

# Check if all services are running
echo -e "\n-- Checking services status"
if [[ "$OS" = "Ubuntu" ]]; then
	check_status
fi

CURRENT_DIR=$(pwd)	
echo ""	
echo "#########################################################"
if [[ "$REVERT" = "false" ]] ; then
	#--- Advise the admin that colmena is now installed and accessible.
	echo " Congratulations colmena firewall has been installed "
	echo " on your server. Please review the log file for any error"
	echo " encountered during installation."
	echo ""
	echo " Log file is located at:"
	echo " $COLMENA_INSTALL_LOG_FILE"
	if [[ "$STORE_TREE" = "true" ]] ; then
		echo " Tree files are located at: $CURRENT_DIR"
	fi
	echo ""
	echo " OpenSSL: CAroot certificate password is stored"
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

# Wait until the user have read before restarts the server...
if [[ "$OS" = "Ubuntu" ]]; then
    while true; do
        read -e -p "Restart your server now to complete the install (Y/n)? " -i 'y' answer
        case $answer in
            [Yy]* ) break;;
            [Nn]* ) exit;;
        esac
    done
    shutdown -r now
fi

###################################################
