#!/usr/bin/env python3
"""List monitored devices and lifecycle data from an Arista CloudVision instance."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any
from urllib.parse import urlparse

import grpc
import arista.inventory.v1
import arista.lifecycle.v1
from google.protobuf.json_format import MessageToDict


RPC_TIMEOUT = 30  # seconds


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--server",
        default=os.environ.get("CVAAS_SERVER"),
        help="CloudVision server in host:port format (or set CVAAS_SERVER)",
    )
    parser.add_argument(
        "--url",
        help="Deprecated CloudVision URL; use --server host:port instead",
    )
    parser.add_argument(
        "--token-file",
        required=True,
        type=argparse.FileType("r"),
        help="File containing the CloudVision service-account token",
    )
    parser.add_argument("--cert-file", type=argparse.FileType("rb"), help="Root CA certificate")
    parser.add_argument("--json", action="store_true", help="Print the complete API device records as JSON")
    return parser.parse_args()


def server_from_args(args: argparse.Namespace) -> str:
    """Return a host:port server string, retaining --url compatibility."""
    server = args.server
    if not server and args.url:
        parsed_url = urlparse(args.url)
        server = parsed_url.netloc or parsed_url.path
    if not server:
        raise RuntimeError("specify --server or --url")
    return server if ":" in server else f"{server}:443"


def get_devices(channel: grpc.Channel) -> list[dict[str, Any]]:
    """Retrieve monitored inventory devices through the Inventory gRPC service."""
    stub = arista.inventory.v1.services.DeviceServiceStub(channel)
    request = arista.inventory.v1.services.DeviceStreamRequest()
    records = [MessageToDict(response) for response in stub.GetAll(request, timeout=RPC_TIMEOUT)]
    return [
        record for record in records
        if record.get("value", record).get("streamingStatus") in ("STREAMING_STATUS_ACTIVE", "active", 2)
    ]


def get_lifecycle_summaries(channel: grpc.Channel) -> list[dict[str, Any]]:
    """Retrieve lifecycle summaries through the Lifecycle gRPC service."""
    stub = arista.lifecycle.v1.services.DeviceLifecycleSummaryServiceStub(channel)
    request = arista.lifecycle.v1.services.DeviceLifecycleSummaryStreamRequest()
    return [MessageToDict(response) for response in stub.GetAll(request, timeout=RPC_TIMEOUT)]


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
        if not isinstance(summary, dict):
            continue
        device = record.get("value", record)
        device.update({name: value for name, value in summary.items() if name != "key"})


def logic_monitor_print(records: list[dict[str, Any]]) -> None:
    """Print all inventory fields in the logic-monitor ``device.field`` format."""
    def print_value(device_id: str, path: str, field_value: Any) -> None:
        if isinstance(field_value, dict):
            for key, child in field_value.items():
                print_value(device_id, f"{path}.{key}", child)
            return
        if isinstance(field_value, (list, tuple)):
            for index, child in enumerate(field_value):
                print_value(device_id, f"{path}.{index}", child)
            return
        if isinstance(field_value, bool):
            field_value = str(field_value).lower()
        elif field_value is None:
            field_value = ""
        print(f"{device_id}.{path}: {field_value}")

    for record in records:
        device = record.get("value", record)
        key = device.get("key", record.get("key", {}))
        device_id = str(key.get("deviceId", device.get("deviceId", "unknown")))

        for name, field_value in device.items():
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
                print_value(device_id, "eosVersion", field_value)
            print_value(device_id, name, field_value)


def main() -> int:
    args = parse_args()
    token = args.token_file.read().strip()
    if not token:
        print("error: token file is empty", file=sys.stderr)
        return 2

    try:
        call_creds = grpc.access_token_call_credentials(token)
        root_cert = args.cert_file.read() if args.cert_file else None
        channel_creds = grpc.ssl_channel_credentials(root_certificates=root_cert)
        connection_creds = grpc.composite_channel_credentials(channel_creds, call_creds)
        with grpc.secure_channel(server_from_args(args), connection_creds) as channel:
            devices = get_devices(channel)
            merge_lifecycle_summaries(devices, get_lifecycle_summaries(channel))
    except (RuntimeError, grpc.RpcError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(devices, indent=2, sort_keys=True))
    else:
        logic_monitor_print(devices)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
