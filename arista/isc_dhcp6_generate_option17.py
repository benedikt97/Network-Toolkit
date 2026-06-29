#!/usr/bin/env python3
"""Generate ISC DHCPv6 Option 17 hex string for Arista AP ZTP."""

import argparse

ENTERPRISE_NUMBER = 16901
MAGIC_STRING = "SPECTRATALK"


def to_hex(text):
    return "".join(f"\\x{ord(c):02x}" for c in text)


def build_suboption_hex(code, value):
    return f"\\x00\\x{code:02x}\\x00\\x{len(value):02x}{to_hex(value)}"

def build_suboption(code, value):
    return f"\\x00\\x{code:02x}\\x00\\x{len(value):02x}{value}"

def build_option17(server):
    enterprise = f"\\x00\\x00\\x{ENTERPRISE_NUMBER >> 8:02x}\\x{ENTERPRISE_NUMBER & 0xff:02x}"
    sub1 = build_suboption(1, server)
    sub4 = build_suboption(4, MAGIC_STRING)
    return enterprise + sub1 + sub4


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate DHCPv6 Option 17 for Arista AP ZTP")
    parser.add_argument("server", help="CV-CUE server IPv6 address (e.g. fd12:3456:789a:40::100)")
    args = parser.parse_args()

    option17 = build_option17(args.server)
    print(f'option dhcp6.vendor-opts "{option17}";')
