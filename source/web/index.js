#!/usr/bin/env node
// Official COLMENA web script
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

var process = require('process');
const http = require('http');
var fs = require('fs');
var lib= require('./lib.js');
var out=new lib.OUT(process.pid);
const mysql = require('mysql');
var dbConfig={
	file: '/etc/colmena/colmena.db.cfg',
};
var debug=true;

var options = {
	host: '127.0.0.1',
//	key: fs.readFileSync('%%SERVER_KEY%%'),
//	cert: fs.readFileSync('%%SERVER_PUB%%'),
	timeout: 15,
};

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
			// Do not callback
			console.log('Web index: database aquired');
		});
	} else console.log('File '+dbConfig.file+' not found');
} catch(err) {
	throw err;
}

http.createServer(options, function (request, response) {
	var state=new lib.state();

	var isPOSTRequest=new Promise(function(resolve, reject) {
		out.log(state,'Recieved connection with method='+request.method);
		if (request.method=='POST') {
			out.log(state,'Reading POST request');
			var formidable = require('formidable'),
			util = require('util');
			var form = new formidable.IncomingForm();
			//form.encoding = 'utf8';
			form.parse(request, function(err, fields, files) {
				var postData={
					fields: fields,
					files: files,
				}
				if (!err) {
					state.queryData=cleanInput(postData);
					out.log(state,'POST data fields=>',state.queryData);
					resolve(true);
				} else reject (err);
			});
		} else {
			out.log(state,'Processing GET request');
			resolve(false);
		}
	});

	isPOSTRequest.then(
		function (wasPOST) {
			var errParam;
			if (!wasPOST) {
				var url  = require('url');
				try {
					state.queryData = cleanInput(url.parse(request.url, true).query);
					errParam=false;
				} catch (err) {
					out.log(state,'ERROR: Reading request params: '+err);
					errParam=true;
				}
			} else {
				state.files=(typeof state.queryData.files!='undefined') ? state.queryData.files : undefined;
				state.queryData=(typeof state.queryData.fields!='undefined') ? state.queryData.fields : undefined;
			}
			state.debug=debug;
			state.ip=getClientIp(request);
			state.database=new Database(dbConfig);
			state.task=getTask(state);
			out.log(state,'Performing task='+state.task);
			switch (state.task) {
				case 'add': sets (response, state); break;
				case 'del': sets (response, state); break;
				case 'status': sets (response, state); break;
				case 'set': scan (response, state); break;
				case 'validate': scan (response, state); break;
				case 'ping': ping (response, state); break;
				default:
					// To be Done Show homepage
					if (errParam) state.set(400,'ERROR: Reading request params');
					else state.set(412, 'Missing task');
					out.send(response, state);
			}
		},
		function (err) {
			throw err;
		}
	);

	isPOSTRequest.catch(function(err) {
		throw err;
	});
}).listen(%%WEBPORT%%);

// Console will print the message
out.log('Server running at http://127.0.0.1:%%WEBPORT%%/');

function getTask(state) {
	var result='unknown';
	if (typeof state.queryData!='undefined') {
		if (typeof state.queryData.task!='undefined') result=state.queryData.task;
		else {
			if (typeof state.queryData.del!='undefined') result='del';
			if (typeof state.queryData.add!='undefined') result='add';
			if (typeof state.queryData.find!='undefined') result='find';
			if (typeof state.queryData.set!='undefined') result='set';
			if (typeof state.queryData.validate!='undefined') result='validate';
			if (typeof state.queryData.ping!='undefined') result='ping';
		}
	}
	return result;
}

function cleanInput(params, itera=0) {
	if (typeof params=='object') {
		for (var i in params) {
			if (debug) out.log('['+itera+'] Cleaning object item ('+typeof params[i]+') '+i+'='+params[i]);
			// No reemplazar datos internos
			if (i=='path') params[i]=sanitizeStr(params[i],0);
			if ((i!='data')&&(i!='path')) {
				switch (typeof params[i]) {
					case 'object':
					case 'array':	params[i]=cleanInput(params[i], ++itera); break;
					case 'string':  if (isJSON(params[i])) params[i]=cleanInput(JSON.parse(params[i]), ++itera);
									else {
										var stoa=StringAsArray(params[i]);
										if (stoa.length>0) params[i]=cleanInput(stoa, ++itera);
										else params[i]=sanitizeStr(params[i],1);
									}
									break;
				}
			}
		}
	} else if (typeof params=='array') {
		for (var i=0; i<params.length; i++) {
			if (debug) out.log('['+itera+'] Cleaning array item ('+typeof params[i]+')'+i+'='+params[i]);
			params[i]=cleanInput(params[i], ++itera);
		}
	} else { // is primitive type
		if (debug) out.log('['+itera+'] Sanitizing =>'+params);
		params=sanitizeStr(params,1);
	}
	return params;
}

function StringAsArray (str) {
	var pc1=str.indexOf('[');
	var pc2=str.indexOf(']');
	if ((pc1>=0)&&(pc2>=0)) {
		var str=str.substring(pc1+1,pc2);
		return str.split(',');
	} else return [];
}

function isJSON(str) {
    try {
        JSON.parse(str);
    } catch (e) {
        return false;
    }
    return true;
}

function sanitizeStr (val, level=1) { // 0=soft(path) 1=hard(anithing else)
	if (typeof val!='undefined') {
		if (typeof val=='string') { // Not bool, num, obj or array?
			if (level>=1) {
				val=val.replace(/[\x00-\x1F\x80-\xFF]/gi, '');
				val=val.replace(/\.{2,}/gi, '.');
				val=val.replace(/\-{2,}/gi, '-');
				val=val.replace(/[#="´'\(\)\*\$\|<>;]/gi, '');
				val=val.replace(/(eval|exec|spawn|String.fromCharCode|require|function|request|response|readdirSync|writeFile)/gi,'');
			} else {
				val=val.replace(/\.{2,}/gi, '.');
				val=val.replace(/\-{2,}/gi, '-');
				val=val.replace(/[#="´'\(\)\*\$\|<>;]/gi, '');
			}
		}
		if (typeof val=='string') {
			if (val=='true') val=true;
			if (val=='false') val=false;
			if (val.toLowerCase()=='null') val=null;
			if ((val!='') && !isNaN(val)) val=Number(val);
		}
	}
	return val;
}

function scan (response, state) {
	var scanner=require('./scanner.js');
	scanner.start(out, response, state)
}

function sets (response, state) {
	var manager=require('./sets.js');
	manager.start(out, response, state)
}

function ping(response, state) {
	state.set(200,'OK Pong');
 	out.send(response, state);
}

function getClientIp(req) {
  var ipAddress;
  var customHeader=(typeof req.headers['X-Forwarded-For'] != 'undefined') ? req.headers['X-Forwarded-For'] : false;
  // The request may be forwarded from local web server.
  var forwardedIpsStr =  req.headers['x-forwarded-for'] || customHeader;
  if (forwardedIpsStr) {
    // 'x-forwarded-for' header may return multiple IP addresses in
    // the format: "client IP, proxy 1 IP, proxy 2 IP" so take the
    // the first one
    var forwardedIps = forwardedIpsStr.split(',');
    ipAddress = forwardedIps[0];
  }
  if (!ipAddress) {
	customHeader=(typeof req.headers['X-RemoteAddress'] != 'undefined') ? req.headers['X-RemoteAddress'] : false;
	if (!customHeader) customHeader=(typeof req.headers['x-remoteaddress'] != 'undefined') ? req.headers['x-remoteaddress'] : false;
    // If request was not forwarded
    ipAddress = customHeader || req.connection.remoteAddress;	// this one always 127.0.0.1 behind a proxy
  }
  // Set by trusted application caller (client->colmena.web)
  // if (typeof req.headers['x-remote-ip']!='undefined') ipAddress=req.headers['x-remote-ip'];
  return ipAddress;
};

class Database {
    constructor( config ) {
        this.connection = mysql.createConnection( config );
    }
    query( sql, args ) {
        return new Promise( ( resolve, reject ) => {
			try {
				this.connection.query( sql, args, ( err, rows ) => {
					if ( err ) return reject( err );
					resolve( rows );
				} );
			} catch (error) {
				console.log('Database query catched error => '+error);
			}
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
