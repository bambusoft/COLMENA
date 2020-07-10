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
const fs = require('fs');
const mysql = require( 'mysql' );
var dbConfig={
	file: '/etc/colmena/colmena.db.cfg',
};
var database = null;

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
			stingIPs();
		});
	} else console.log('File '+dbConfig.file+' not found');
} catch(err) {
	throw err;
}

function stingIPs() {
	var query="SELECT ip, cidr from ip_fw_list where list='BL' and (lastActivityDate+(blockDays*86400))>=unix_timestamp() order by lastActivityDate DESC";
	database.query(query).then(function (rows) {
		if (typeof rows[0]!='undefined') {
			for (var i=0; i<rows.length; i++) {
				var cidr='';
				if ((typeof rows[i].cidr!="udefined")
					&&(rows[i].cidr!="null")
					&&(!isNaN(rows[i].cidr))
					&&(rows[i].cidr>0)) cidr='/'+rows[i].cidr;
				console.log(rows[i].ip+cidr);
			}
			database.close();
		} else database.close(); // No ips to sting
	}).catch(function(err) {
		database.close();
		throw err;
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
