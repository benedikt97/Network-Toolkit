#!/usr/bin/env python3
import sys
import time

# Gib der BGP-Session Zeit, sich aufzubauen
time.sleep(10)

# FlowSpec Syntax für ExaBGP:
# Match: Source = Attacker (10.0.1.2), Destination = Victim (10.0.2.2)
# Action: Discard (Traffic verwerfen)
flowspec_rule = (
    "announce flow route { "
    "match { source 10.0.1.2/32; destination 10.0.2.2/32; } "
    "then { discard; } "
    "}"
)

# Regel an ExaBGP senden
sys.stdout.write(flowspec_rule + '\n')
sys.stdout.flush()

# Skript am Leben erhalten
while True:
    time.sleep(60)