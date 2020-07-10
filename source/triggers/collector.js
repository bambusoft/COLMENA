#!/usr/bin/env node
// Official COLMENA collector script
// ================================================
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//  OS VERSIONS tested:
//	Ubuntu 18.04 32bit and 64bit
//	Ubuntu 20.04 64bit
//
//  Official website: http://colmena.bambusoft.com
//
//  Author Mario Rodriguez Somohano, colmena (at) bambusoft.com
//
const now=parseInt(Math.floor(Date.now() / 1000));
const days=2;
const daysInSecs=days*24*60*60;
const maxCacheSize=30;
const fs = require('fs');
const mysql = require( 'mysql' );
var dbConfig={
	file: '/etc/colmena/colmena.db.cfg',
};
var server={
		id : 0,
		ip6: '::/128'
}
var database = null;
var ipCache=[], iportCache=[];
var quiet=(typeof process.argv!='undefined') ? process.argv.includes('--quit') : false;

try {
	if (fs.existsSync(dbConfig.file)) {
		const readline = require('readline');
		const readInterface = readline.createInterface({
			input: fs.createReadStream(dbConfig.file),
		});

		readInterface.on('line', function (line) {
			if (line.indexOf(']')<0) {
				harry=line.split('=');
				dbConfig[harry[0]]=harry[1];
			}
		});

		readInterface.on('close', function () {
			database=new Database(dbConfig);
			readInput(parseInput);
		});
	} else console.log('File '+dbConfig.file+' not found');
} catch(err) {
	throw err;
}

// Process STDIN pipe
var readInput = function(callback){
	var input = '';
	process.stdin.setEncoding('utf8');
	process.stdin.on('readable', function() {
		var chunk = process.stdin.read();
		if (chunk !== null) input += chunk;
	});
	process.stdin.on('end', function() {
		callback(input);
	});
}

// Parse input data
var parseInput = function(input){
	var query="SELECT id, ip6 FROM server WHERE fqdn='"+dbConfig.fqdn+"'"; // Must be just one server
	database.query(query).then(function (rows) {
		if (typeof rows[0]!='undefined') {
			server.id=rows[0].id;
			server.ip6=rows[0].ip6;
			var par=[];
			var trigger={};
			var list=null;
			var lines=input.split("\n");
			for (var l=0; l<lines.length; l++) {
				var line=lines[l];
				var type=lineType(line);
				if (type==0) continue;
				if (type==1) { // Trigger tag found
					var ptr=l;
					var tag='generic';
					var s1=line.lastIndexOf("[");
					var s2=line.lastIndexOf("]");
					if ( (s1>0) && (s2>0) ) tag=line.substring(line.lastIndexOf("[") + 1, line.lastIndexOf("]"));
					try {
						database.query('SELECT * FROM trigger_script WHERE name="'+tag+'"')
							.then(function(rows) {
								if (typeof rows[0]!='undefined') {
									trigger.id=rows[0].id;
									trigger.name=rows[0].name;
									trigger.port=rows[0].default_port;
								} else { // Store new trigger tag (no wait)
									database.query("INSERT INTO trigger_script (name,description) VALUES ('"+tag+"', 'Taken from "+tag+" script')");
								}
							}).then(function(rows) {
								// Parse remaining data
								for (var i=(ptr+1); i<lines.length; i++) {
									var lrow=null;
									line=lines[i];
									type=lineType(line);
									switch (type) {
										case 2: list=getList(line); break;
										case 4: lrow=getRow(trigger, list, line, type); break;
										case 6: lrow=getRow(trigger, list, line, type); break;
									}
									if (lrow!=null) {
										if (lrow.ip!=null) par.push(store(lrow));
										else console.log ('* ERROR: Trying to store null ip: '+line);
									}
								}
								Promise.all(par).then(
									function(values) {
										var res=true;
										for (var v=0; v<values.length; v++) {
											res=(res && values[v].flag);
											if (!quiet) {
												if (res) console.log('+ '+values[v].ip+' '+values[v].msg);
												else console.log('- '+values[v].ip+' '+values[v].msg);
											}
										}
										database.close();
									},
									function (err) {
										database.close();
										console.log(err);
									}
								).catch(function(err) {
									database.close();
									console.log(err)
								});
							}).catch(function(err) {
								database.close();
								console.log(err);
							})
					} catch (err) {
						database.close();
						console.log(err);
					}
				}
				if (type>1) break; // No trigger tag found before data
			}
		} else {
			database.close();
			throw 'DB0: FQDN not found in table server';
		}
	}).catch(function(err) {
		database.close();
		throw err;
	});
}

function store(r) {
	return new Promise(function(resolve, reject) {
		var result={
			flag:false,
			ip:r.ip,
			msg:'Unknown error',
		}
		if ( (r.type==4) || (r.type==6) ) {
			var sql;
			if (!ipCache.includes(r.ip)) {
				// ip_fw_list
				sql="INSERT INTO ip_fw_list (ip, list, last, events, firstActivityDate, lastActivityDate, blockDays, propagated, src_ip6)";
				sql+=" VALUES ('"+r.ip+"', '"+r.list+"', 'UK', 1, "+now+", "+now+", "+days+", 0, '"+server.ip6+"')";
				sql+=" ON DUPLICATE KEY UPDATE";
				sql+=" lastActivityDate = CASE WHEN (("+now+"-lastActivityDate)>"+daysInSecs+") THEN "+now+" ELSE lastActivityDate END,";
				sql+=" events = CASE WHEN (("+now+"-lastActivityDate)>"+daysInSecs+") THEN events+1 ELSE events END,";
				sql+=" last = CASE WHEN (("+now+"-lastActivityDate)>"+daysInSecs+") THEN list ELSE last END,";
				sql+=" list = CASE WHEN (("+now+"-lastActivityDate)>"+daysInSecs+") THEN '"+r.list+"' ELSE list END,";
				sql+=" blockDays=POWER(2,events)";
				database.query(sql).then(function (rows) {
					// ip_trigger
					sql="INSERT INTO ip_trigger (ip, trigger_id, events, lastUpdate)";
					sql+=" VALUES ('"+r.ip+"', "+r.trigger.id+", 1, "+now+")";
					sql+=" ON DUPLICATE KEY UPDATE";
					sql+=" lastUpdate = CASE WHEN (("+now+"-lastUpdate)>"+daysInSecs+") THEN "+now+" ELSE lastUpdate END,";
					sql+=" events = CASE WHEN (("+now+"-lastUpdate)>"+daysInSecs+") THEN events+1 ELSE events END";
					database.query(sql).then(function (rows) {
						if (r.port>0) {
							var iport=r.ip+'-'+r.port;
							if (!iportCache.includes(iport)) {
								// port
								sql="INSERT INTO port (id) VALUES ("+r.port+")";
								sql+=" ON DUPLICATE KEY UPDATE id=id"; // Avoid INSERT IGNORE for other kind of errors
								database.query(sql).then(function (rows) {
										var sql2="INSERT INTO ip_port (ip, port, lastUpdate, events)";
										sql2+=" VALUES('"+r.ip+"',"+r.port+","+now+", 1)";
										sql2+=" ON DUPLICATE KEY UPDATE";
										sql2+=" lastUpdate = CASE WHEN (("+now+"-lastUpdate)>"+daysInSecs+") THEN "+now+" ELSE lastUpdate END,";
										sql2+=" events = CASE WHEN (("+now+"-lastUpdate)>"+daysInSecs+") THEN events+1 ELSE events END";
										database.query(sql2).then(function(rows) {
											var sql3="INSERT INTO server_port (server, port, lastUpdate, events)";
											sql3+=" VALUES ("+server.id+","+r.port+", "+now+", 1)";
											sql3+=" ON DUPLICATE KEY UPDATE";
											sql3+=" lastUpdate = CASE WHEN (("+now+"-lastUpdate)>"+daysInSecs+") THEN "+now+" ELSE lastUpdate END,";
											sql3+=" events = CASE WHEN (("+now+"-lastUpdate)>"+daysInSecs+") THEN events+1 ELSE events END";
											database.query(sql3).then(function (rows) {
												result.flag=true;
												result.msg='Server-Port stored';
												resolve(result);															
											}).catch(function (err) {
												result.flag=false;
												result.msg='DB1 err: '+err.toString();
												reject(result);
											});
										}).catch(function(err) {
											result.flag=false;
											result.msg='DB3 err: '+err.toString();
											reject(result);											
										});
								}).catch (function(err) {
									result.flag=false;
									result.msg='DB4 err: '+err.toString();
									reject(result);
								});
								if (iportCache.push(iport)>maxCacheSize) iportCache.shift();
							} else {
								result.flag=true;
								result.msg='Previously processed port, cache hit';
								resolve(result);
							}
						} else {
							result.flag=true;
							result.msg='Processed IP without port';
							resolve(result);
						}
					}).catch(function (err) {
						result.flag=false;
						result.msg='DB5 err: '+err.toString();
						reject(result);
					});
				}).catch(function (err) {
					result.flag=false;
					result.msg='DB6 err: '+err.toString();
					reject(result);
				});
				if (ipCache.push(r.ip)>maxCacheSize) ipCache.shift();
			} else {
				result.flag=false;
				result.msg='Previously processed IP, cache hit';
				resolve(result);
			}
		} else {
			result.flag=false;
			result.msg='Invalid IP';
			resolve(result);
		}
	});	
}

function lineType(str) {
	var result=0;
	const trigger=/^.*#.*Trigger/;
	if (str.search(trigger)>=0) result=1;
	const list=/^.*#.*List/;
	if (str.search(list)>=0) result=2;
	const ipRegex = require('ip-regex');
	if (ipRegex.v4().test(str)) result=4;
	if (ipRegex.v6().test(str)) result=6;
	return result;
}

function getList(str) {
	var result='UK';
	var s1=str.lastIndexOf("[");
	var s2=str.lastIndexOf("]");
	if ( (s1>0) && (s2>0) ) result=str.substring(str.lastIndexOf("[") + 1, str.lastIndexOf("]"));
	return result;
}

function getRow(trigger, list, str, type) {
	var result={
		trigger: trigger,
		list: list,
		ip: null,
		port: trigger.port,
		type: type,
	}
	var par=str.split(' ');
	const isIp = require('is-ip');
	if (isIp(par[0])) result.ip=par[0];
	if (par.length>1) {
		if (!isNaN(par[1])) result.port=par[1];
	}
	return result;
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