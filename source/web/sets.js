// Official COLMENA web sets manager script
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
//
// This tool creates an acl.dat file in the colmena share web path
// acl.dat format
//		add bl ipv4|ipv6
//		add wl ipv4|ipv6 proto port [timeout]
//		del bl ipv4|ipv6
//		del wl ipv4|ipv6 proto port

const validLists=['BL','GL','WL','UK'];

exports.start = function (out, response, state) {
	if ((typeof response=='undefined')||(typeof state=='undefined'))
		throw 'SETS: Requires a valid response and state params';
	var debug=state.debug;
	var today=new Date();
	if ((typeof state.queryData!='undefined')&&(typeof state.queryData.sid!='undefined')) {
		state.mod='SETS';
		state.response=response;
		out.log(state,'Library Started: '+state.mod+' at '+ today);
		if (debug) out.log(state.queryData);
		state.source=isValidSource(state.queryData.sid);
		if (state.source.authorized) {
			switch (state.task) {
				case 'add': addel (out, response, state); break;
				case 'del': addel (out, response, state); break;
				case 'status': status (out, response, state); break;
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

function addel (out, response, state) { // NOK
	if (typeof state.ip!='undefined') {
		out.log(state.queryData);
		var aclFile='/etc/bind/acl.clients';
		
		
var aclUpdate='/srv/dns/acl.update';
var body='acl clients {'+"\n";
for (var b=0; b<rows2.length; b++) {
	body+="\t"+rows2[b].lastIP+";\n";
}
body+="};\n";
var fs = require('fs');
fs.writeFile(aclFile, body, function (err3) {
	if (!err3) {
		console.log('Updating aclFile');
		result.allowed=true;
		result.ip=data.ip;
		sendOutput(resp, result);
	} else {
		conn.release();
		result.err=err3.code+' geting list';
		sendOutput(resp, result);								
	}
});
fs.writeFile(aclUpdate, now, function (err4) {
	if (!err4) console.log('Creating aclUpload');
	else console.log('Unable to create aclUpload');
});		

		// Construir acl.dat row
		// APPEND to acl.dat
		state.set(501,'Not implemented');
		out.send(response, state);
	} else {
		state.set(400,'Bad request, unknown client IP');
		out.send(response, state);		
	}
	
}

function status (out, response, state) { // NOK
	out.log(state.queryData);
	state.set(501,'Not implemented');
	out.send(response, state);
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

function isValidSource(sid) {
	var result={
		// [FALTA] verificar certificado del cliente
		ip: 'fe80::96de:80ff:fef9:7c00', // puede ser ipv4 o ipv6
		authorized: true,
	}
	return result;
}
