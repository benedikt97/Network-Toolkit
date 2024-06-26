import asyncio
from pysnmp.hlapi.asyncio import *


async def run(varBinds):
    snmpEngine = SnmpEngine()
    while True:
        errorIndication, errorStatus, errorIndex, varBindTable = await bulkCmd(
            snmpEngine,
            CommunityData('ciscosecurero', mpModel=0),
            UdpTransportTarget(("192.168.10.54", 161)),
            ContextData(),
            0, 1,
            *varBinds,
        )

        if errorIndication:
            print(errorIndication)
            break
        elif errorStatus:
            print(
                f"{errorStatus.prettyPrint()} at {varBinds[int(errorIndex) - 1][0] if errorIndex else '?'}"
            )
        else:
            for varBindRow in varBindTable:
                for varBind in varBindRow:
                    print(" = ".join([x.prettyPrint() for x in varBind]))

        varBinds = varBindTable[-1]
        if isEndOfMib(varBinds):
            break
    return


asyncio.run(
    run([ObjectType(ObjectIdentity("TCP-MIB"))])
)
