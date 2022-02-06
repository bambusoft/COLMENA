-- Table provider
INSERT INTO provider (name) VALUES ('GENERIC');
-- Table owner
INSERT INTO owner (name,client_fk) VALUES ('GENERIC',0);
-- Table server
INSERT INTO server (hostname,fqdn,ip4,ip6,vpn4,vpn6,provider,owner,active,hive_hierarchy,privateKey,publicKey)
VALUES('%%HOSTNAME%%','%%FQDN%%','%%IPV4%%','%%IPV6%%','%%IPV4%%','%%IPV6%%',1,1,1,'B','%%privatekey','%%publickey%%');
-- Triggers
INSERT INTO trigger_script (name,description,default_port) VALUES
('bee','Colmena bee server peer',0),
('psad','Port Scan Atack Detector',0),
('colmena','Colmena trigger',0),
('auth','Authorization system',22),
('fail2ban','Failure log scanner',0),
('syslog','System logs (Colmena firewall IP denied logs)',0),
('apache','Apache web server',80),
('nginx','NGINX web server',80),
('postfix','Mail Transport Agent (MTA)',25),
('dovecot','Mail Delivery Agent (MDA)',110);
-- Standard ports
INSERT INTO port (id,IANA_assignment) VALUES
(20,'FTP Data Transfer'),
(21,'FTP Control command'),
(22,'SSH Secure shell'),
(23,'Telnet'),
(25,'SMTP Simple Mail Transfer Protocol'),
(53,'DNS Domain Name System'),
(80,'HTTP Hypertext Transfer Protocol'),
(110,'POP3 Post Office Protocol v3'),
(115,'SFTP Simple File Transfer Protocol'),
(123,'NTP Network Time Protocol'),
(161,'SNMP Simple Network Management Protocol'),
(389,'LDAP Lightweight Directory Access Protocol'),
(443,'HTTP Hypertext Transfer Protocol over SSL/TLS'),
(631,'IPP Internet Printing Protocol'),
(636,'LDAP Lightweight Directory Access Protocol over SSL/TLS'),
(655,'Tinc VPN'),
(853,'DNS Over SSL/TLS'),
(995,'POP3 Post Office Protocol v3 over SSL/TLS'),
(1293,'IPSec Internet Protocol Security'),
(1443,'Microsoft SQL Server'),
(1723,'PPTP Point-to-Point Tunneling Protocol'),
(3306,'MySQL Database System'),
(3389,'Windows Remote Desktop and Remote Assistance'),
(4500,'IPSec NAT Traversal'),
(5060,'SIP Session Initiation Protocol'),
(5432,'PostreSql Database system'),
(5666,'NRPE Nagios Remote Plugin Executor'),
(6379,'RESP REdis Serialization Protocol'),
(8080,'Alternate HTTP Hypertext Transfer Protocol'),
(8443,'Alternate HTTP Hypertext Transfer Protocol over SSL/TLS'),
(9530,'Xiongmai Cameras Backdoor');
