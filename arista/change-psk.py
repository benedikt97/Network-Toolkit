#!/usr/bin/env python3
"""Login to Launchpad and query accessible WM services.

Requires environment variables:
    LAUNCHPAD_KEY_ID
    LAUNCHPAD_KEY_VALUE
    LAUNCHPAD_BASE_URL
"""

import json
import os
import sys
import requests
import argparse

LAUNCHPAD_BASE = "https://launchpad.wifi.arista.com"
BASE_URL = os.environ.get("WM_BASE_URL")
KEY_ID = os.environ.get("LAUNCHPAD_KEY_ID")
KEY_VALUE = os.environ.get("LAUNCHPAD_KEY_VALUE")

def login_launchpad() -> requests.Session:
    key_id = os.environ.get("LAUNCHPAD_KEY_ID")
    key_value = os.environ.get("LAUNCHPAD_KEY_VALUE")
    base_url = os.environ.get("WM_BASE_URL")

    if not key_id or not key_value or not base_url:
        print("Error: LAUNCHPAD_KEY_ID, LAUNCHPAD_BASE_URL and LAUNCHPAD_KEY_VALUE must be set.", file=sys.stderr)
        sys.exit(1)

    session = requests.Session()
    resp = session.post(
        f"{LAUNCHPAD_BASE}/api/v2/session",
        json={
            "type": "apiKeyCredentials",
            "keyId": key_id,
            "keyValue": key_value,
            "timeout": 3600,
        },
    )
    if not resp.ok:
        print(f"LAUNCHPAD Login failed: {resp.status_code} {resp.text}", file=sys.stderr)
    else:
        print("LAUNCHPAD Login successful.")
    return session

def login_wm() -> requests.Session:
    session = requests.Session()
    resp = session.post(
        f"{BASE_URL}/session",
        json={
            "type": "apikeycredentials",
            "keyId": KEY_ID,
            "keyValue": KEY_VALUE,
            "timeout": 3600,
            "clientIdentifier": "script"
        }
    )
    if not resp.ok:
        print(f"WM Login failed: {resp.status_code} {resp.text}", file=sys.stderr)
    else:
        print(f"{BASE_URL}: Login successful!")
    return session


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Arista CV-CUE PSK change Script")
    parser.add_argument("--ssid", help="The SSID of which the psk should be changed", required=True)
    parser.add_argument("--location", help="The location of the SSID", required=True)
    parser.add_argument("--newpsk", help="The new psk to be set", required=True)
    args = parser.parse_args()

    SSID = args.ssid
    NEW_PSK = args.newpsk 
    LOCATION = args.location



# Creat a authenticated session in wireless manager
    wm_session = login_wm()

# Fetch Locations
    resp = wm_session.get(f"{BASE_URL}/locations")
    locations = resp.json()
    if locations['name'] == LOCATION:
        location_id = locations['id']
    else:
        location_id = next((d["id"] for d in locations["children"] if d['name'] == LOCATION), None)

    if location_id:
        print(f"{LOCATION}: Location found with ID {location_id['id']}!")
    else:
        print(f"{LOCATION}: Location not found!")
        sys.exit(1)


# Fetch SSID Profiles
    query_params={"locationid": location_id['id']}
    resp = wm_session.get(f"{BASE_URL}/deviceconfiguration/ssidprofiles", params=query_params)
    if not resp.ok:
        print(f"Failed to fetch services: {resp.status_code} {resp.text}", file=sys.stderr)
        sys.exit(1)
    ssidprofiles = resp.json()


# Extract the profile matching to a specific SSID
    ssid_profile = next((d for d in ssidprofiles if (d['ssid'] == SSID and d['createdAtLocationId']['id'] == location_id['id'])), None)
    if not ssid_profile:
        print(f"{SSID}: SSID not found!")
        sys.exit(1)
    else:
        print(f"{SSID}: SSID found in location id={ssid_profile['createdAtLocationId']['id']}!")


# Overwrite the PSK
    ssid_profile["wirelessProfile"]["securityMode"]["pskPassphrase"] = NEW_PSK
    resp = wm_session.put(f"{BASE_URL}/deviceconfiguration/ssidprofiles", json=ssid_profile)
    if not resp.ok:
        print(f"Failed to fetch services: {resp.status_code} {resp.text}", file=sys.stderr)
        sys.exit(1)
    if resp.ok:
        print(f"{SSID}: PSK changed succesfully!")



