#!/usr/bin/env python3
"""List monitored devices and lifecycle data through CloudVision Resource APIs."""

from __future__ import annotations

import argparse
import json
import ssl
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEVICE_RESSOURCE_PATH = "/api/resources/inventory/v1/Device/all"
LIFECYCLE_RESSOURCE_PATH = "/api/resources/lifecycle/v1/DeviceLifecycleSummary/all"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="CloudVision base URL, e.g. https://www.arista.io")
    parser.add_argument(
        "--token-file",
        required=True,
        type=argparse.FileType("r"),
        help="File containing the CloudVision service-account token",
    )
    parser.add_argument("--ca-file", type=argparse.FileType("rb"), help="Root CA certificate")
    parser.add_argument("--insecure", action="store_true", help="Do not validate the server certificate")
    parser.add_argument("--json", action="store_true", help="Print the merged device records as JSON")
    return parser.parse_args()


def request_ressource(
    base_url: str,
    token: str,
    payload: dict[str, Any],
    ressource_path: str,
    context: ssl.SSLContext | None,
) -> list[dict[str, Any]]:
    """Fetch records from a CloudVision Resource API endpoint."""
    request = Request(
        base_url.rstrip("/") + ressource_path,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=30, context=context) as response:
            payload = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"CloudVision returned HTTP {error.code}: {detail}") from error
    except URLError as error:
        raise RuntimeError(f"Could not connect to CloudVision: {error.reason}") from error

    records = payload.get("result", payload.get("devices", []))
    if isinstance(records, dict):
        records = [records]
    if not isinstance(records, list):
        raise RuntimeError(f"Unexpected CloudVision response: {json.dumps(payload)[:500]}")
    return records


def device_id(record: dict[str, Any]) -> str | None:
    """Extract a device ID from either an inventory or lifecycle record."""
    value = record.get("value", record)
    key = value.get("key", record.get("key", {}))
    result = key.get("deviceId", value.get("deviceId", record.get("deviceId")))
    return str(result) if result is not None else None


def merge_lifecycle_summaries(
    devices: list[dict[str, Any]], summaries: list[dict[str, Any]]
) -> None:
    """Merge each lifecycle value into the matching inventory device record."""
    summaries_by_device_id = {
        summary_id: summary.get("value", summary)
        for summary in summaries
        if (summary_id := device_id(summary)) is not None
    }
    for record in devices:
        summary = summaries_by_device_id.get(device_id(record))
        if isinstance(summary, dict):
            record.get("value", record).update(
                {name: value for name, value in summary.items() if name != "key"}
            )


def logic_monitor_print(records: list[dict[str, Any]]) -> None:
    """Print all device fields in the logic-monitor ``device.field`` format."""
    def print_value(device: str, path: str, value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                print_value(device, f"{path}.{key}", child)
        elif isinstance(value, (list, tuple)):
            for index, child in enumerate(value):
                print_value(device, f"{path}.{index}", child)
        else:
            if isinstance(value, bool):
                value = str(value).lower()
            elif value is None:
                value = ""
            print(f"{device}.{path}: {value}")

    for record in records:
        value = record.get("value", record)
        device = device_id(record) or "unknown"
        for name, field_value in value.items():
            if name == "key":
                continue
            if name == "systemMacAddress":
                name = "mac"
            elif name == "streamingStatus":
                name = "status"
                if isinstance(field_value, str):
                    field_value = field_value.removeprefix("STREAMING_STATUS_").lower()
                elif field_value == 2:
                    field_value = "active"
            elif name == "softwareVersion":
                print_value(device, "eosVersion", field_value)
            print_value(device, name, field_value)


def main() -> int:
    args = parse_args()
    token = args.token_file.read().strip()
    if not token:
        print("error: token file is empty", file=sys.stderr)
        return 2
    if args.insecure and args.ca_file:
        print("error: choose either --insecure or --ca-file", file=sys.stderr)
        return 2

    context = ssl._create_unverified_context() if args.insecure else ssl.create_default_context()
    if args.ca_file:
        context.load_verify_locations(cadata=args.ca_file.read().decode("utf-8"))

    try:
        devices = request_ressource(
            args.url, token, {"partialEqFilter": [{"streamingStatus": 2}]}, DEVICE_RESSOURCE_PATH, context
        )
        summaries = request_ressource(args.url, token, {}, LIFECYCLE_RESSOURCE_PATH, context)
        merge_lifecycle_summaries(devices, summaries)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(devices, indent=2, sort_keys=True))
    else:
        logic_monitor_print(devices)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
