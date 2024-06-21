from pysnmp.hlapi import *
import pandas as pd
import time
from datetime import timedelta

def getsnmptable(ip, community):
	result = []
	global QUERYOK
#	auth = UsmUserData(userName=snmpuser, 															# SNMPv3-User
#					authKey=snmppassword, 															# SNMPv3-Password
#					authProtocol=usmHMACMD5AuthProtocol,											# Authentification Protocoll
#					privKey=snmpprivacy,															# SNMPv3-Encryption Password
#					privProtocol=usmAesCfb128Protocol)												# Enryption Protocoll
	
	
	iterator = nextCmd(																				# Creates iterator with SnmpEngine, Authentification Object and Device Adress.
						SnmpEngine(),
                        CommunityData(community, mpModel=0),
                        UdpTransportTarget((ip, 161)),
                        ContextData(),
                        ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.2')),
						ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.18')),
                        ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.7')),
                        ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.8')),
						ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.9')),
                        lexicographicMode=False, lookupValues=True, lookupNames=True)
		
	
	for (errorIndication, errorStatus, errorIndex, varBinds) in iterator:							# Looping over iterator Object and builts a list of SNMP Objects
		if errorIndication:
			return str(errorIndication)
			break
		elif errorStatus:
			return str('%s at %s' % (errorStatus.prettyPrint(), errorIndex and varBinds[int(errorIndex)-1][0] or '?'))
			break
		else:
			result.append(varBinds)
	 
	
	list = []
	for s in result:																				# Convert SNMP Object to a Pandas Dataframe
		column = []
		for o in s: 
			try:
				print(t)
				t = o[1].prettyPrint()
				if 'No more variables' in t:
					column.append('0')
				else:
					column.append(t)

			except:
				column.append(str(o[1]))
		list.append(column)
	df = pd.DataFrame(list)
	QUERYOK = True
	return df



if __name__=='__main__':
	df = getsnmptable('192.168.10.54', 'ciscosecurero')
	for i in range(len(df.index)):
	#	df.at[i, 4] = time.strftime('%d, %H:%M:%S', time.gmtime(int(df.at[i, 4])))
		df.at[i, 5] = str(timedelta(seconds=int(df.at[i, 4])))
	print(df)