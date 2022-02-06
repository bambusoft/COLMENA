// Official COLMENA web scanner script
// Colmena Propagator
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

/*
	sid:	Crypted shared secret server identification
			sid=base64string
	set:	xL where xL is one of the lists BL|GL|WL|UK
	ip:		Valid single ipv4 or ipv6
			ip=192.0.2.1
	ips:	Array of vaild ipv(4,6) values (or array of a single ip)
			ips={["192.0.2.11","::1","192.0.2.32"]}
	list:	JSON object {"xL":[records]} where xL is one of the lists BL|GL|WL|UK
			list={"BL":["record1", "record2"], "GL":["record3", "record4"], "WL":["record"]
			record:	{ "ip":"", "bl":"", "gl":"", "wl":"", "fad":"", "lad":"", "ori":"" }
*/
const validLists=['BL','GL','WL','UK'];

exports.start = function (out, response, state) {
	if ((typeof response=='undefined')||(typeof state=='undefined'))
		throw 'SCANNER: Requires a valid response and state params';
	var debug=state.debug;
	var today=new Date();
	if ((typeof state.queryData!='undefined')&&(typeof state.queryData.sid!='undefined')) {
		state.mod='SCANNER';
		state.response=response;
		out.log(state,'Library Started: '+state.mod+' at '+ today);
		if (debug) out.log(state.queryData);
		state.source=isValidServerId(state.queryData.sid);
		if (state.source.authorized) {
			switch (state.task) {
				case 'set': set (out, response, state); break;
				case 'validate': validate (out, response, state, true); break;
				default: 
					state.set(405,'Invalid state.task param');
					out.send(state.response, state);				
			}
		} else {
			state.set(500,'Please provide a valid server identification');
			out.send(response, state); // state puede llegar mal formado aqui
		}
	} else {
		state.set(500,'Please provide server identification');
		out.send(response, state); // state puede llegar mal formado aqui
	}
};

function set (out, response, state) {
	var resultSet={ // Este objeto no se usa
		records: [],
		result: false,
	}
	var set=state.queryData.set.toUpperCase();
	if (validLists.includes(set)&&validate (out, response, state, false).result) {
		var ipArray=[];
		if (typeof state.queryData.ips!='undefined') { // multiple ips
			ipArray=state.queryData.ips;
		}
		if (typeof state.queryData.ip!='undefined') { // one or more ips
			// Covert single ip to an array of ips
			if (!Array.isArray(state.queryData.ip)) {
				var tmp=[state.queryData.ip];
				state.queryData.ip=(state.queryData.ip.indexOf(',')>0) ? state.queryData.ip.split(',') : tmp;
			}
			for (var i=0; i<state.queryData.ip.length; i++) {
				ipArray.push(state.queryData.ip[i]);
			}
		}
		var list;
		if (typeof state.queryData.list!='undefined') list=state.queryData.list;
		var setL=set.toLowerCase();
		if (!list.hasOwnProperty(setL)) list[setL]=[];
		for (var i=0; i<ipArray.length; i++) {
			var record=new Record({
				ip: ipArray[i],
				list: set,
				blackListed: (set=='BL') ? 1 : 0,
				greyListed: (set=='GL') ? 1 : 0,
				whiteListed: (set=='WL') ? 1 : 0,
				origin_ip: state.source.ip
			});
			list[setL].push({
				ip: record.ip,
				bl: record.blackListed,
				gl: record.greyListed,
				wl: record.whiteListed,
				fad: record.firstActivityDate,
				lad: record.lastActivityDate,
				src: record.src_ip,
				ori: record.origin_ip
			});
			if (state.debug) out.log ('Added to list ip='+record.ip);
		}
		if (state.debug) out.log ('Starting update...');
		// Start update process
		var promisesArray=[];
		state.database.query('START TRANSACTION;')
			.then(function(dontCare) {
				for (var l in list) {
					var lst=l.toUpperCase();
					for (var i=0; i<list[l].length; i++) {
						promisesArray.push(storeRecord(lst, list[l][i], state));
					}
				}
				Promise.all(promisesArray).then(
					function (values) {
						var res=true;
						for (var v=0; v<values.length; v++) {
							if (state.debug) out.log(state,'('+v+') values => '+JSON.stringify(values[v]));
							res=(res && values[v].flag);
							if (!res) state.set(values[v].status,values[v].message,values[v].detail);
						}
						out.log(state,'Global result =>'+res);
						state.result.values=values;
						var sqlCommand, performed;
						if (res) {
							state.set(200,'OK');
							sqlCommand="COMMIT";
							performed='commited';
						} else {
							state.set(406,'xxx Error');
							sqlCommand="ROLLBACK";
							perform='rolled back';
						}
						out.send(response, state);
						state.database.query(sqlCommand).then(function (rows){
							if (typeof rows!='undefined') {			
								out.log(state,'Executed: '+sqlCommand);
							} else {
								out.log(state,'Executed: '+sqlCommand+' with undefined rows');
							}
						});
					}
				);
			}
		)
	} else {
		state.set(400,'Bad request, invalid data set '+state.queryData.set);
		out.send(response, state);		
	}
}

function storeRecord(lst, r, state) {
	return new Promise(function(resolve, reject) {
		var result={
			flag: false,
			status: 300,
			message: 'Unknown',
		};
		var days=Math.pow(r.bl, 2);
		var events=r.bl+r.gl+r.wl;
		// [FALTA] Manejo de listBlocked
		var hostname='NULL';
		if ((typeof r.hostname=='undefined')||(r.hostname=='')||(r.hostname=='null')||(r.hostname==null)) hostname='NULL';
		else hostname="'"+r.hostname+"'"; 
		var sql="INSERT INTO ip_fw_list (ip, list, last, blackListed, greyListed, whiteListed, events, firstActivityDate, lastActivityDate, hostname, blockDays, propagated, src_ip, origin_ip)";
		sql+=" VALUES ('"+r.ip+"', '"+lst+"', 'UK', "+r.bl+", "+r.gl+", "+r.wl+", "+events+", "+r.fad+", "+r.lad+", '"+r.hostname+"', "+days+", 0, '"+state.source.ip+"', '"+r.ori+"')";
		sql+=" ON DUPLICATE KEY UPDATE";
		sql+=" last = list,";
		sql+=" list = '"+lst+"',"; // Preserve requested, what if is actually BL in destiny? and requested WL?
		sql+=" blackListed = GREATEST("+r.bl+",blackListed),";
		sql+=" greyListed = GREATEST("+r.gl+",greyListed),";
		sql+=" whiteListed = GREATEST("+r.wl+",whiteListed),";
		sql+=" events = blackListed+greyListed+whiteListed,";
		sql+=" firstActivityDate = LEAST("+r.fad+",firstActivityDate),";
		sql+=" lastActivityDate = GREATEST("+r.lad+",lastActivityDate),";
		sql+=" hostname = "+hostname+",";
		sql+=" blockDays=POWER(2,blackListed),";
		sql+=" propagated=0,";
		sql+=" src_ip='"+state.source.ip+"',";
		sql+=" origin_ip='"+r.ori+"'";
		state.database.query(sql)
			.then(function (rows) {
				result={
					flag: true,
					status: 200,
					message: 'OK',
				}
				resolve(result);
			}).catch(function(error) {
				result={
					flag: false,
					status: 500,
					message: error,
				}
				resolve(result);
			});
	});
}

function Record (object) {
	const now=parseInt(Math.floor(Date.now() / 1000));
	this.ip='';
	this.list='UK',
	this.last='UK',
	this.blackListed=0,
	this.greyListed=0,
	this.whiteListed=0,
	this.events=0,
	this.firstActivityDate=now,
	this.lastActivityDate=now,
	this.hostname='NULL',
	this.blockDays=2,
	this.propagated=0,
	this.src_ip='',
	this.origin_ip='';
	if (typeof object!='undefined') {
		for (var item in object) {
			if (typeof this[item]!='undefined') this[item]=object[item];
		}
	}
	this.events=this.blackListed+this.greyListed+this.whiteListed;
}

function validate (out, response, state, dump=false) {
	var validation={
		result: true
	}
	if (typeof state.queryData!='undefined') {
		if (typeof state.queryData.ip!='undefined') {
			// Covert single ip to an array of one
			if (!Array.isArray(state.queryData.ip)) {
				var tmp=[state.queryData.ip];
				state.queryData.ip=(state.queryData.ip.indexOf(',')>0) ? state.queryData.ip.split(',') : tmp;
			}
			validation.ip=isValidIP(state.queryData.ip);
			if (typeof validation.ip.test!='undefined') validation.result=(validation.result && validation.ip.test);
		}
		if (typeof state.queryData.ips!='undefined') {
			// is array?
			if (!Array.isArray(state.queryData.ips)) {
				var tmp=[state.queryData.ips];
				state.queryData.ips=(state.queryData.ips.indexOf(',')>0) ? state.queryData.ips.split(',') : tmp;
			}
			validation.ips=isValidIP(state.queryData.ips);
			if (typeof validation.ips.test!='undefined') validation.result=(validation.result && validation.ips.test);
		}
		if (typeof state.queryData.list!='undefined') {
			// is an object?
			if (typeof state.queryData.list=='object') {
				validation.list=isValidList(state.queryData.list,state.debug);
				if (typeof validation.list.test!='undefined') validation.result=(validation.result && validation.list.test);
			}
		}
		if (state.debug) {
			out.log(state,'validation =>');
			out.log(validation);
		}
		if (dump) {
			state.result={
				status: (validation.result) ? 200 : 400,
				msg: (validation.result) ? 'OK' : 'Bad request',
				validation: validation,
			}
			out.send(response, state);
		} else return validation;
	} else {
		out.log(state,'ERROR: No data received to validate');
		if (dump) {
			state.set(400,'Bad request, missing data');
			out.send(response, state);
		}
		validation.result=false;
		return validation;
	}
}

function isValidList (list, debug=false) { // list parameter
	var result={
		test: true
	}
	for (var i in list) {
		result.test=(validLists.includes(i.toUpperCase()) && hasValidRecords(list[i],debug));
		if (!result.test) break;
	}
	return result;
}

function hasValidRecords (list,debug=false) { // array of objects
	var result=true;
	if (debug) {
		console.log('list received =>');
		console.log(list);
	}
	if (Array.isArray(list)) {
		for (var l=0; l<list.length; l++) {
			if (debug) {
				console.log(' working with record =>');
				console.log(list[l]);
			}
			if  (typeof list[l].ip!='undefined') {
				result=isValidIP([list[l].ip]).test;
				if ((!result)&&(debug)) console.log('ERR: Invalid IP');
			} else {
				result=false;
				if(debug) console.log('ERR: Invalid IP');
			}
			var events=(typeof list[l].bl!='undefined') ? list[l].bl : 0;
			events+=(typeof list[l].gl!='undefined') ? list[l].gl : 0;
			events+=(typeof list[l].wl!='undefined') ? list[l].wl : 0;
			if (events<=0) {
				result=false;
				if (debug) console.log('ERR: Invalid number of events');
			}
			if ((typeof list[l].fad!='undefined')&&(typeof list[l].lad!='undefined')) {
				if (!isValidTimestamp(list[l].fad) || !isValidTimestamp(list[l].lad)) {
					result=false;
					if (debug) console.log('ERR: Invalid first or last activity time stamp(s)');
				}
			} else {
				result=false;
				if (debug) console.log('ERR: Invalid first or last activity date(s)');
			}
			if (typeof list[l].ori!='undefined') {
				if (!isValidIP([list[l].ori]).test) {
					result=false;
					if (debug) console.log('ERR: Invalid origin IP format');
				}
			} else {
				result=false;
				if (debug) console.log('ERR: Invalid origin IP');
			}
		}
	} else {
		if (debug) console.log('ERR: Invalid arrary');
		result=false;
	}
	if (debug) console.log(' valid records result =>'+result);
	return result;
}

function isValidTimestamp (ts) {
	return (new Date(ts)).getTime() > 1573948800; // Nov 17 2019, First confirmed covid-19 case
}

function isValidIP (ipArray) {
	var result={
		ip: 'OK',
		test: true
	}
	const ipRegex = require('ip-regex');
	for (var i=0; i<ipArray.length; i++) {
		if (!ipRegex({exact: true}).test(ipArray[i])) {
			result={
				ip: ipArray[i],
				test: false
			}
			break;
		}
	}
	return result;
}

function isValidServerId(sid) {
	var result={
		ip: 'fe80::96de:80ff:fef9:7c00', // debe ser ipv6 de un server registrado en server (como peer?)
		authorized: true,
	}
	return result;
}
