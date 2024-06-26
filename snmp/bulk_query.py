from pysnmp.hlapi import *
import time
import pandas as pd

def getColumn(oid):
    N, R = 0, 21
    errorIndication, errorStatus, errorIndex, varBinds = bulkCmd(SnmpEngine(),
        CommunityData('ciscosecurero'),
        UdpTransportTarget(("192.168.10.54", 161)),
        ContextData(),
        N, R,
        ObjectType(ObjectIdentity(oid)),
        ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.2')),
    #    ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.3')),
    #    ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.4')),
    #    ObjectType(ObjectIdentity('1.3.6.1.2.1.2.2.1.5')),
        )
    result = []
    for var in varBinds:
        result.append(var[0][1].prettyPrint()) 
    return result

oids = ['1.3.6.1.2.1.2.2.1.1', '1.3.6.1.2.1.2.2.1.2', '1.3.6.1.2.1.2.2.1.3', '1.3.6.1.2.1.2.2.1.4', '1.3.6.1.2.1.2.2.1.5']

ifIndex = getColumn('1.3.6.1.2.1.2.2.1.1')
ifDescr = getColumn('1.3.6.1.2.1.2.2.1.2')
ifAlias = getColumn('1.3.6.1.2.1.2.2.1.2')
ifAdminStatus = getColumn('1.3.6.1.2.1.2.2.1.7')
ifOperStatus = getColumn('1.3.6.1.2.1.2.2.1.8')

data = {'ifIndex': ifIndex, 'ifDescr': ifDescr, 'ifAdminStatus': ifAdminStatus, 'ifOperStatus': ifOperStatus}
print(data)
df = pd.DataFrame.from_dict(data)
print(df.to_markdown())



