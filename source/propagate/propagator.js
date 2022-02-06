#!/usr/bin/env node

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

const crypto = require('crypto');
const fs = require('fs');
const mysql = require( 'mysql' );
var dbConfig={
	file: '/etc/colmena/colmena.db.cfg',
};
const rowLimit=50;
var database = null;
var quiet=(typeof process.argv!='undefined') ? process.argv.includes('--quiet') : false;
var valida=(typeof process.argv!='undefined') ? process.argv.includes('--validate') : false;
var debug=true;

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
			propagate();
		});
	} else console.log('File '+dbConfig.file+' not found');
} catch(err) {
	throw err;
}

function propagate() {
	var servers=[];
	var query;
	var hasPeer=false;
	// 1) [FALTA] Obtener credenciales server actual y server de propagación
	var sid='unknown';
	var task=(valida) ? 'validate' : 'set=UK';
	query="SELECT id, fqdn, ip6, vpn6, hive_peer, privateKey, publicKey, sharedSecret FROM server WHERE fqdn='"+dbConfig.fqdn+"' OR (hive_peer>0 AND active>0) ORDER BY RAND()"
	database.query(query).then(function (rows) {
		if (typeof rows[0]!='undefined') {
			console.log (new Date()+' Propagator Found '+rows.length+' servers');
			var server;
			for (var r=0; r<rows.length; r++) {
				server=JSON.parse(JSON.stringify(rows[r]));
				if (server.fqdn==dbConfig.fqdn) server.remote=false;
				else {
					server.remote=true;
					hasPeer=true;
				}
				servers.push(server);
			}
			if (!quiet) console.log(servers);
			if (hasPeer) {
				// 2) [FALTA] Construir identificador con sharedsecret (sid)
				// 3) OK Seleccionar registros para enviar
				query="SELECT * FROM `ip_fw_list` WHERE propagated=0 AND list<>'UK' ORDER BY  RAND() LIMIT "+rowLimit;
				database.query(query).then(function (rows) {
					if (typeof rows[0]!='undefined') {
						var record={
							ip: '',
							bl: 0, gl: 0, wl: 0,
							fad: '', lad: '',
							hostname: 'NULL',
							ori: ''
						}
						var list={
							BL: [],
							GL: [],
							WL: [],
							UK: []
						}
						for (var r=0; r<rows.length; r++) {
							record={
								ip: rows[r].ip,
								bl: rows[r].blackListed,
								gl: rows[r].greyListed,
								wl: rows[r].whiteListed,
								fad: rows[r].firstActivityDate,
								lad: rows[r].lastActivityDate,
								hostname: ((typeof rows[r].hostname=='undefined')||(rows[r].hostname=='')||(rows[r].hostname=='NULL')||(rows[r].hostname==null)) ? 'NULL': rows[r].hostname,
								ori: rows[r].origin_ip,
								updated: false
							}
							// [FALTA] UnhandledPromiseRejectionWarning: TypeError: Cannot read property 'push' of undefined
							list[rows[r].list].push(record);
						}
						if (typeof list.BL[0]=='undefined') delete list.BL;
						if (typeof list.GL[0]=='undefined') delete list.GL;
						if (typeof list.WL[0]=='undefined') delete list.WL;
						// 4) construir post
						var data=task+'&sid='+sid+'&list='+JSON.stringify(list);
						// 5) Enviar por cada peer
						for (var s=0; s<servers.length; s++) {
							if (servers[s].remote) {
								const https = require('https');
								const options = {
								  hostname: servers[s].fqdn,
								  port: 443,
								  path: '/colmena',
								  method: 'POST',
								  headers: {
									'Content-Type': 'application/x-www-form-urlencoded',
									'Content-Length': data.length
								  }
								}
								if (!quiet) console.log('Sending POST data to server: '+options.hostname);
								const req = https.request(options, function (res) {
									var result='';
									if (!quiet) {
										console.log(`Response from: ${res.client.servername}`);
										console.log(`status: ${res.statusCode}`);
										console.log(`Message: ${res.statusMessage}`);
									}
									// 6) esperar respuesta
									res.on('data', function (chunk) {
										result+=chunk;
									})
									res.on('end', function() {
										try {
											result=JSON.parse(result);
											if (result.status==200) {
												// Update propagated records (just need one confirmation)
												var query2="UPDATE ip_fw_list SET propagated=1 WHERE ip IN (";
												var items=0; 
												for (var i in list) {
													for (var l=0; l<list[i].length; l++) {
														if (!list[i][l].updated) {
															items++;
															list[i][l].updated=true;
															console.log('Propagated: '+list[i][l].ip);
															query2+="'"+list[i][l].ip+"',";
														}
													}
												}
												if (items>0) {
													query2+="'0.0.0.0')";
													database.query(query2).then(function (result) {
														if (debug) console.log(query2+' affected rows='+result.affectedRows);
														database.close();
													}).catch(function(err) {
														if (!quiet) console.log('Error updating => '+err);
													});
												}
												console.log('Propagation updated');
											} // Can fail on any server db close is not conditioned here
										} catch (error) {
											if (!quiet) {
												console.log(result);
												//console.log(error);
											}
										}
									});
								})
								req.on('error', function (error) {
									console.log(error);
									database.close();
								})
								req.write(data);
								req.end();
							} else if (!quiet) console.log('Skipping POST to myself: '+servers[s].fqdn);
						}
					}
				});
			} else {
				database.close();
				console.log('DB1: No peers found in table server, please add propagation servers');
			}
		} else {
			database.close();
			throw 'DB0: FQDN or peers not found in table server';
		}
	}).catch(function(err) {
		if (!quiet) console.log(err);
		database.close();
		throw err;
	});
}

function getServerSharedSecret(server) {
const private_key = fs.readFileSync('private.pem', 'utf-8')
const public_key = fs.readFileSync('public.pem', 'utf-8')
const message = fs.readFileSync('message.txt', 'utf-8')

const signer = crypto.createSign('sha256');
signer.update(message);
signer.end();

const signature = signer.sign(private_key)
const signature_hex = signature.toString('hex')

const verifier = crypto.createVerify('sha256');
verifier.update(message);
verifier.end();

const verified = verifier.verify(public_key, signature);

console.log(JSON.stringify({
    message: message,
    signature: signature_hex,
    verified: verified,
}, null, 2));
/*
darwin:	5kzqFB8pPifJgzYnj07fJAcWRNEbaT2dGfKjK12bJNoRjJVkGgslJvTBE9HIp46oCFke9vzBJwTy4sg8tgUvzmcf9s82t4b1X1ZJYfHpvi81dMvdKbYRHeK9MxwzdY0s
cassini:NVdiFG5YGckRm5BqfBeFsB0thprCZhvwiZWRDSqVS1lNYbTmLTx0ltDjOCO2XJJu522YrFGqDdSlVC46kT272oyvNvqfR9HxHmohkasbsJ3S6VCwDJy6Qy35OhuOYJGv
ciclope:dAWzZgjz2Dai8MKy5yrhUGfQfy4s9BXiW7wN1Zph80zdBtJ9nJimA83KMslQFq3KQ356iXuKhzcq07zO7W8OairJ9nYkkM60nigt42okX4gZhDKwIWXuGQFKUBPphKzS
*/

}

class Database {
    constructor( config ) {
        this.connection = mysql.createConnection( config );
    }
    query( sql, args ) {
        return new Promise( ( resolve, reject ) => {
            this.connection.query( sql, args, ( err, rows ) => {
                if ( err ) return reject( err );
                resolve( rows );
            } );
        } );
    }
    close() {
        return new Promise( ( resolve, reject ) => {
			this.connection.end( err => {
				if ( err ) return reject( err );
				resolve();
			} );
        } );
    }
}
