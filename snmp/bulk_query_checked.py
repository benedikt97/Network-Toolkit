from pysnmp.hlapi import *
import pandas as pd

def getColumn(oid):
    result = []
    start_oid = oid
    while True:
        if str(oid).split('.')[-2] != start_oid.split('.')[-2]:
            break
        errorIndication, errorStatus, errorIndex, varBinds = bulkCmd(SnmpEngine(),
            CommunityData('ciscosecurero'),
            UdpTransportTarget(("192.168.10.54", 161)),
            ContextData(),
            0, 300,
            ObjectType(ObjectIdentity(oid)),)        


        for val in varBinds:
            oid = val[0][0]
            if str(oid).split('.')[-2] != start_oid.split('.')[-2]:
                return result
            result.append(val[0][1].prettyPrint())
            print(val[0][1].prettyPrint())
            oid = val[0][0]
    return result

oids = ['1.3.6.1.2.1.2.2.1.1', '1.3.6.1.2.1.2.2.1.2', '1.3.6.1.2.1.2.2.1.3', '1.3.6.1.2.1.2.2.1.4', '1.3.6.1.2.1.2.2.1.5']

ifIndex = getColumn('1.3.6.1.2.1.2.2.1.1.0')
ifDescr = getColumn('1.3.6.1.2.1.2.2.1.2.0')
ifAlias = getColumn('1.3.6.1.2.1.2.2.1.18.0')
ifAdminStatus = getColumn('1.3.6.1.2.1.2.2.1.7.0')
ifOperStatus = getColumn('1.3.6.1.2.1.2.2.1.8.0')

data = {'ifIndex': ifIndex, 'ifDescr': ifDescr, 'ifAlias': ifAlias, 'ifAdminStatus': ifAdminStatus, 'ifOperStatus': ifOperStatus}
print(data)
df = pd.DataFrame.from_dict(data, orient='index')
print(df.to_markdown())
df = df.transpose()
print(df.to_markdown())





