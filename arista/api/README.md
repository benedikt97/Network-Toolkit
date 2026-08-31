# CloudVision API helpers

## List monitored CVaaS devices

`list_cvaas_devices.py` queries CloudVision's Inventory and Lifecycle gRPC
services, filters for devices with `streamingStatus: 2`, and merges lifecycle
data by device ID. It requires the CloudVision Python API packages and `grpcio`.

Create a CloudVision service account with permission to read Inventory and
Lifecycle data, then use its token file:

```bash
python3 arista/api/list_cvaas_devices.py \
  --server www.arista.io:443 \
  --token-file /path/to/cvaas-token
```

Keep the service-account token in a file with restricted permissions. Its
contents are stripped of surrounding whitespace, so a trailing newline is fine:

```bash
chmod 600 /path/to/cvaas-token
python3 arista/api/list_cvaas_devices.py \
  --server www.arista.io:443 \
  --token-file /path/to/cvaas-token
```

Use `--json` to print the unmodified device records for scripting:

```bash
python3 arista/api/list_cvaas_devices.py --json > devices.json
```

The default output is flattened, dot-separated logic-monitor data:

```text
WTW25421179.hostname: leaf1
WTW25421179.softwareVersion: 4.36.1F
```

## HTTP-only version

`list_cvaas_devices_http.py` is a separate implementation that uses only the
CloudVision Resource REST endpoints. It has no gRPC, generated Arista API, or
`grpcurl` dependency. It queries both Inventory and Lifecycle resources and
merges them by device ID:

```bash
python3 arista/api/list_cvaas_devices_http.py \
  --url https://www.arista.io \
  --token-file /path/to/cvaas-token
```

For a private CA, add `--ca-file /path/to/ca.crt`. Use `--insecure` only for
temporary testing against an untrusted certificate.
