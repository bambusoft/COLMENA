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

exports.OUT = function (pid) {
	this.pid=pid;
	/* *** */
	/* LOG */
	/* *** */
	this.log= function (state, msg) { // puede ser llamado log(state,msg) o log (msg)
		var str='colmenad: ';
		if ((arguments.length>1)&&(typeof state!='undefined')) {
			str+=state.tid+':';
			str+=(typeof state.task!='undefined') ? state.task+':' : '';
		} else msg=state;
		if (typeof msg=='object') {
			console.log(str+'=>');
			console.log(msg);
		} else console.log(str+' '+msg);
	}
	/* **** */
	/* SEND */
	/* **** */
	this.send = function (response, state) {
		var headers={
			'Content-Type': 'application/json',
			//'Cache-Control': 'public, max-age=1296000'	// 15 días
		}
		var json;
		if (typeof state.result!='undefined') {
			json=JSON.stringify(state.result);
			response.writeHead(state.result.status, headers);
		} else {
			json=JSON.stringify({status: 500, msg: 'Mising result'});
			response.writeHead(500, headers);
		}
		response.end(json);
		this.log(state, json);
	}
}

exports.state = function () {
	this.tid=Math.floor(Math.random() * Math.floor(1000)), // Riesgo de colisión que aumenta si hay más de 1000 usuarios simultáneos
	this.task=undefined;
	this.queryData=undefined;
	this.result={
		status: 0,
		msg: 'unknown',
	}
	/* *** *
	 * SET *
	 ***** */
	this.set = function (estatus, message) {
		this.result={
			status: estatus,
			msg: message
		}
	}
}
