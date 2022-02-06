#!/usr/bin/env node
// Official COLMENA helper script
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

const COLMENA_EVENTS_LOG='/var/log/colmena/events.log';
const COLMENA_EVENTS_IP='/var/log/colmena/ip';
const maxtries=5;
const fs = require('fs');
var months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
var quiet=(typeof process.argv!='undefined') ? process.argv.includes('--quiet') : false;
var debug=false;

try {
	readInput(parseSTDIN);
} catch (err) {
	throw err;
}

// Process STDIN pipe
function readInput (callback) {
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

function parseSTDIN (input){
	var lines=input.split("\n");
	var auxArray=[], aCount=0, invalids=0, maxAttempts=maxtries;
	for (var l=0; l<lines.length; l++) {
		var line=lines[l];
		line=line.trim();
		var harry=line.split(/[\s,]+/);
		if ((harry.length==0)||(harry.length>3)) {
			console.log('Invalid array size, skipping line '+l);
			invalids++;
			if (invalids<=5) continue;
			else {
				console.log('Failed, too many invalid elements');
				break;
			}
		}
		if (debug) console.log ('Line ['+l+'] =>',harry);
		// Dovecot: attempts, account@domain, IP
		// Postfix: attempts, connect, IP
		// Syslog: attempts, scan, IP
		if (typeof harry[2]!=='undefined') {
			if (debug) console.log ("\tconverted to => "+harry);
			// if email, then check for multiple IPs trying to guess, one emails pass
			switch (harry[1]) {
				case 'scan':
				case 'noauth': maxAttempts=maxtries; break;
				case 'connect': maxAttempts=50; break;
				default: // count emails 
					maxAttempts=maxtries;
					var account=harry[1].split('@');
					harry[1]=account[0];
					if (auxArray.length==0) {
						aCount=addToAux(harry, auxArray, aCount);
					} else {
						if ((typeof auxArray[0][1]!='undefined')&&(auxArray[0][1]==harry[1])) {
							aCount=addToAux(harry, auxArray, aCount);
						} else {
							processAux(auxArray,aCount)
							auxArray=[]; aCount=0;
							aCount=addToAux(harry, auxArray, aCount);
						}
					}
					break;
			}
			if (!isNaN(harry[0])) {
				if (harry[0]>=maxAttempts) tagIP(harry);
			} 
		}
	}
	if (auxArray.length>0) processAux(auxArray,aCount);
}

function addToAux(harry, auxArray, aCount) {
	auxArray.push(harry);
	if (typeof harry[0]!='undefined') harry[0]=parseInt(harry[0]);
	aCount+=(isNaN(harry[0])) ? 1 : harry[0];
	if (debug) console.log ("\tadding to auxArray => "+auxArray+' cant='+aCount);
	return aCount;
}

function processAux(auxArray,aCount) {
	if (debug) console.log ("\t Processing auxArray with "+auxArray.length+' elements');
	for (var a=0; a<auxArray.length; a++) {
		if ((auxArray[0][0]>=maxtries)||(aCount>=maxtries)) {
			tagIP(auxArray[a]);
		}
	}	
}

function tagIP (harry) {
	var date=new Date();
	var m=date.getMonth()
	var month = ("0" + ( m + 1)).slice(-2);
	var day = ("0" + date.getDate()).slice(-2);
	var hours = ("0" + date.getHours()).slice(-2);
	var minutes = ("0" + date.getMinutes()).slice(-2);
	var seconds = ("0" + date.getSeconds()).slice(-2);
	var time=hours+':'+minutes+':'+seconds;
	var msg=months[m]+' '+day+' '+ time + ' bypass SECURITY ALERT '+ harry[2]+ ' ' + harry[1] + ' too many failure attempts ('+harry[0]+')' + "\n";
	if (!quiet) console.log ("\tTagging =>"+harry[2]);
	var ipFile=COLMENA_EVENTS_IP+'/'+harry[2]+'.blk';
	fs.access(ipFile, fs.F_OK, function (err) {
		if (err) {
			fs.writeFile(ipFile, msg, function (err) {
				if (err) msg+=' ERROR: Can not write '+ipFile;
				fs.appendFile(COLMENA_EVENTS_LOG, msg, function (err) {
					if (err) throw err;
				});			
			}); 
		}
		// ip already tagged
	});  
}
