#!/usr/bin/env node
// Official COLMENA collector script
// ================================================
// This file is part of colmena security project
// Copyright (C) 2010-2022, Mario Rodriguez < colmena (at) bambusoft.com >
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// OS VERSIONS tested:
//	Ubuntu 18.04 32bit and 64bit
//	Ubuntu 20.04 64bit
//
//  Official website: http://colmena.bambusoft.com

const now=parseInt(Math.floor(Date.now() / 1000));
const days=2, daysWL=5, daysXL=90, maxDays=120;
const daysInSecs=days*24*60*60;
const fs = require('fs');
var dns = require('dns');
const mysql = require( 'mysql' );
var dbConfig={
	file: '/etc/colmena/colmena.db.cfg',
};
var database = null;
var parts2='0.0',	limit2=6500,
	parts3='0.0.0',	limit3=25;
var exceptions=['0.0.0.0','192.168.0.0/16','192.168.0.0/24'];
var allowUpdateHostname=false;	// Some DNS resolvers limit or block to many PTR requests
var debug=false;

try {
	if (fs.existsSync(dbConfig.file)) {
		const readline = require('readline');
		const readInterface = readline.createInterface({
			input: fs.createReadStream(dbConfig.file),
		});

		readInterface.on('line', function (line) {
			if ((line.indexOf(']')<0)&&(line.length>0)) {
				harry=line.split('=');
				dbConfig[harry[0]]=harry[1];
			}
		});

		readInterface.on('close', function () {
			database=new Database(dbConfig);
			resetWhiteList();
			resetOlderList();
			removeOldest();
			stingIPs();
		});
	} else console.log('File '+dbConfig.file+' not found');
} catch(err) {
	throw err;
}

function resetWhiteList() {
	// Each IP must gain WL, so we clean the WL older than days
	var query = "UPDATE ip_fw_list SET last=list, list='UK', blackListed=0, whiteListed=0, events=greyListed, blockDays=0 WHERE whiteListed>0 AND listBlocked=0 AND (lastActivityDate+("+daysWL+"*86400))>=unix_timestamp()";
	database.query(query).then(function (rows) {
		if (debug) console.log('OK cleaning whitelist');
	}).catch(function(err) {
		if (debug) console.log('error cleaning whitelist =>'+err);
	});
}

function resetOlderList() {
	// IPs with to many daysXL without activity are set to UK
	var query = "UPDATE ip_fw_list SET last=list, list='UK', blackListed=0, greyListed=0, whiteListed=0, events=0, blockDays=0 WHERE listBlocked=0 AND ((unix_timestamp()-lastActivityDate)/86400)>="+daysXL;
	database.query(query).then(function (rows) {
		if (debug) console.log('OK reseting older than '+daysXL+' days');
	}).catch(function(err) {
		if (debug) console.log('error reseting older list =>'+err);
	});
}

function removeOldest() {
	// Delete IP ports without activity in maxDays 
	var query = "DELETE FROM ip_port WHERE ((unix_timestamp()-lastUpdate)/86400)>="+maxDays;
	database.query(query).then(function (rows) {
		if (debug) console.log('OK deleteing ip-port older than '+maxDays+' days');
			// Delete IP triggers without activity in maxDays 
			query = "DELETE FROM ip_trigger WHERE ((unix_timestamp()-lastUpdate)/86400)>="+maxDays;
			database.query(query).then(function (rows) {
				if (debug) console.log('OK cleaning oldest triggers, '+maxDays+' days');
					// Delete IPs without activity in maxDays 
					query = "DELETE IGNORE FROM ip_fw_list WHERE listBlocked=0 AND ((unix_timestamp()-lastActivityDate)/86400)>="+maxDays;
					database.query(query).then(function (rows) {
						if (debug) console.log('OK cleaning oldest, '+maxDays+' days');
					}).catch(function(err) {
						if (debug) console.log('error cleaning oldest =>'+err);
					});
			}).catch(function(err) {
				if (debug) console.log('error cleaning oldest triggers=>'+err);
			});
	}).catch(function(err) {
		if (debug) console.log('error deleting ip-port older list =>'+err);
	});
}

function stingIPs() {
	var promisesArray=[];
	// What about -> AND whiteListed=0, because list=BL + whiteListed>0 means block it, but list=WL + blacklisted>0 maybe a legtimate user
	var query="SELECT ip, cidr, hostname from ip_fw_list WHERE blackListed>0 AND whiteListed=0 AND (lastActivityDate+(blockDays*86400))>=unix_timestamp() order by blackListed DESC, lastActivityDate DESC";
	database.query(query).then(function (rows) {
		if (typeof rows[0]!='undefined') {
			for (var i=0; i<rows.length; i++) {
				var cidr='';
				if ((typeof rows[i].cidr!='undefined')
					&&(rows[i].cidr!='null')
					&&(!isNaN(rows[i].cidr))
					&&(rows[i].cidr>0)) cidr='/'+rows[i].cidr;
				console.log(rows[i].ip+cidr);
				// Update hostname
				promisesArray.push(updateHostname(rows[i].ip, rows[i].hostname));
			}
			Promise.all(promisesArray).then(
				function (values) {
					stingNETs();
					// [FALTA] Write to logfile not console
				}
			);
		} else stingNETs(); // No ips to sting
	}).catch(function(err) {
		database.close();
		throw err;
	});
}

// [FALTA] Handle network exceptions (servers, local ips, gateways, whitelists)
// var exceptions=['w.x.y.z', 'w.x.y.z/dd'] ip or ip/cidr
function stingNETs() {
	var lastip='0.0.0.0',
		lastTime=0,
		lastnet='0.0.0.0/0',
		c2=0, c3=0;
	var subnet={
		start: '', startNum: 0,
		end: '', endNum: 0,
	}
	var query="SELECT ip, cidr, lastActivityDate, whiteListed, blockDays FROM `ip_fw_list` ORDER BY ip";
	database.query(query).then(function (rows) {
		if (typeof rows[0]!='undefined') {
			var IpSubnetCalculator = require( 'ip-subnet-calculator' );
			var hasWL=false, wl2=false, wl3=false, noBlock=false;
			var numlast, numthis;
			for (var i=0; i<rows.length; i++) {
				var net='';
				var thisip=rows[i].ip;
				var lastActivityDate=rows[i].lastActivityDate;
				var blockDays=(rows[i].blockDays>0) ? rows[i].blockDays : 1;
				var wl=rows[i].whiteListed;
					hasWL=(wl>0);
				var wlStr=(hasWL) ? ' wl='+wl : '' ;
				var timeLimit=lastActivityDate+blockDays*(24*60*60);
				if (timeLimit>lastTime) lastTime=timeLimit;
				var igual=ip_equal(lastip, thisip);
				if (igual==3) { c3++; wl3=(hasWL); } else { c3=0; wl3=false; }
				if (igual>=2) { c2++; wl2=(hasWL); } else { c2=0; wl2=false; }
				if ((lastip.indexOf(':')>-1)||(thisip.indexOf(':')>-1)) { // [FALTA] Calcular valor numerico de intervalo en IPv6
					numlast=0;
					nuthis=0;
				} else {
					numlast=IpSubnetCalculator.toDecimal(lastip);
					numthis=IpSubnetCalculator.toDecimal(thisip);
				}
				if (numthis<subnet.startNum) {
					subnet.start=thisip;
					subnet.startNum=numthis;
				}
				if (numthis>subnet.endNum) {
					subnet.end=thisip;
					subnet.endNum=numthis;
				}
				if ((c2==1)||(c3==1)) { // [FALTA] Si c2=x cuando c3=1 se reinicia en /16
					subnet.start=lastip; subnet.startNum=numlast;
					subnet.end=thisip; subnet.endNum=numthis;
				}
				if (debug) console.log(lastip+' - '+thisip+' ('+c2+','+c3+')'+wlStr);
				if (c3>=limit3) net=parts3+'.0/24';		// Block 253 ips network
				if (c2>=limit2) net=parts2+'.0.0/16';	// Block 65025 ips network
				if ( ( net!='' ) && (!exceptions.includes(net)) ) {
					if (debug) {
						console.log('Compare if ['+now+' < '+lastTime+']['+lastnet+' net '+net+']');
					}
					if (now<lastTime) {
						var equity=ip_equal(lastnet, net);
						if (equity<=2) {	// 3 son la misma red /24 pero 2 es /24 vs /16 hay que bloquear ambas y 1 es un segmento diferente hay que bloquear
							//Se va a bloquear la red
							var subnets=IpSubnetCalculator.calculate(subnet.start, subnet.end);
							noBlock=(wl2 || wl3);
							if (noBlock) {
								if (debug) console.log(' eq='+equity+' Selected for Blocking denied (whitelist) '+net);
							} else {
								if (debug) {
									console.log(' eq='+equity+' Blocking '+net+' from '+subnet.start+' to '+subnet.end);
									console.log(subnets);
								}
								// write net to cache
							}
							if (subnets.length>0) {
								for (var s=0; s<subnets.length; s++) {
									var sn=subnets[s];
									console.log(sn.ipLowStr+'/'+sn.prefixSize);
								}
							} else console.log(net);
							noBlock=false;
							hasWL=false;
							lastnet=net;
						} else {
							if (debug) console.log(' eq='+equity);
						}
					}
				}
				hasWL=false;
				if (igual<=1)  lastTime=0;
				lastip=thisip;
			}
			database.close();
		} else database.close(); // No networks to sting
	}).catch(function(err) {
		database.close();
		throw err;
	});
}

function ip_equal (ant, act) {
	result=0;
	var listP, listC;
	var areIPv4=((ant.indexOf('.')>-1)&&(act.indexOf('.')>-1));
	var areIPv6=((ant.indexOf(':')>-1)&&(act.indexOf(':')>-1));
	if (areIPv4) {
		listP=ant.split('.');
		listC=act.split('.');
		if (listP[0]==listC[0]) result=1;
		if ( (listP[0]==listC[0])&&(listP[1]==listC[1]) ) { result=2; parts2=listC[0]+'.'+listC[1]; }
		if ( (listP[0]==listC[0])&&(listP[1]==listC[1])&&(listP[2]==listC[2]) ) { result=3; parts3=listC[0]+'.'+listC[1]+'.'+listC[2]; }
	} else if (areIPv6) {
		// [FALTA]
	}
	return result;
}

function updateHostname(ip, curHostName) {
	return new Promise(function(resolve, reject) {
		if (debug) console.log('requested update hostname('+curHostName+') for ip='+ip);
		var result={
			ip: ip,
			hostname: '',
			flag: false,
		}
		if ((typeof curHostName=='undefined')
			||(curHostName=='')
			||(curHostName=='NULL')
			||(curHostName==null)) {
				if (allowUpdateHostname) {
					if (debug) console.log('Requesting DNS resolution for ip='+ip);
					dns.reverse(ip, function(err, hostnames) {
						if (err) {
							if (err.code==dns.ENOTFOUND) result.hostname="'ENOTFOUND'";
							else if (err.code==dns.NXDOMAIN) result.hostname="'NXDOMAIN'";
							else result.hostname='NULL';
						} else {
							result.hostname=(typeof hostnames[0]!='undefined') ? '"'+hostnames[0]+'"' : 'NULL';
							if (debug) console.log('obtained '+hostnames.length+' hostnames, taking => ['+result.hostname+']');
						}
						if (result.hostname!='NULL') {
							var sql='UPDATE ip_fw_list SET hostname='+result.hostname+' WHERE ip="'+result.ip+'"';
							if (debug) console.log('sql ='+sql);
							database.query(sql).then(function (rows) {
								if (debug) console.log('stored hostname='+result.hostname+' for ip='+result.ip);
								result.flag=true;
								resolve(result);
							}).catch(function(err) {
								if (debug) console.log('error storing hostname =>'+err);
								result.flag=false;
								result.msg=err;
								reject(result);
							});
						} else {
							if (debug) console.log('can not store hostname is null for ip='+result.ip);
							result.flag=false;
							result.msg='Can not resolve hostname for ip='+result.ip;
							resolve(result);
						}
					});
				} else {
					if (debug) console.log('Disabled DNS resolution for ip='+result.ip);
					result.flag=false;
					result.msg='Denied hostname resolution for ip='+result.ip+' by allowUpdateHostname';
					resolve(result);
				}
			} else {
				if (debug) console.log('preserving current hostname='+curHostName);
				result.hostname=curHostName;
				result.flag=true;
				result.msg='OK';
				resolve(result);
			}
	});
}

class Database {
    constructor( config ) {
        this.connection = mysql.createConnection( config );
    }
    query( sql, args ) {
        return new Promise( ( resolve, reject ) => {
            this.connection.query( sql, args, ( err, rows ) => {
                if ( err )
                    return reject( err );
                resolve( rows );
            } );
        } );
    }
    close() {
        return new Promise( ( resolve, reject ) => {
            this.connection.end( err => {
                if ( err )
                    return reject( err );
                resolve();
            } );
        } );
    }
}
