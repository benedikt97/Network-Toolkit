# FreeRADIUS EAP-TLS for wired 802.1X

This is an Ubuntu/FreeRADIUS 3 deployment for certificate-based wired 802.1X (EAP-TLS). It deliberately permits no password EAP methods.

## Install

The **RADIUS client** is the switch that receives EAPOL and forwards EAP to this server (the authenticator). It is not normally the Arista switch using its front-panel port as an 802.1X supplicant.

```bash
cd freeradius
sudo ./install.sh --nas-ip 192.0.2.10 --nas-secret 'use-a-long-random-shared-secret' --server-name radius.example.net
```

The installer installs `freeradius`, `freeradius-utils`, `openssl`, and `gettext-base` (for `envsubst`); saves replaced configuration files in `/etc/freeradius/3.0/.eap-tls-backup-*`; creates a private CA; and starts the service. Certificate material is stored under `/etc/freeradius/3.0/certs/<hostname>/`, using the server's short hostname. Allow UDP/1812 from the authenticator to the server in the firewall.

For more authenticators, add one `client` block to `/etc/freeradius/3.0/clients.d/eap-tls.conf`, then run `sudo systemctl reload freeradius`.

## RadSec (optional)

Add `--radsec` during installation to enable RADIUS-over-TLS (RadSec) on TCP port 2083:

```bash
sudo ./install.sh --nas-ip 192.0.2.10 --nas-secret 'use-a-long-random-shared-secret' --server-name radius.example.net --radsec
```

RadSec requires the switch to present a certificate issued by this server's CA. Create one with `sudo freeradius-certctl issue access-switch-01`, install its `.p12` bundle and the CA certificate on the switch, and configure the switch to use RadSec on TCP/2083. Keep the switch's `client` block in `eap-tls.conf`; it identifies the permitted switch source address and shared secret. Allow TCP/2083 through the firewall in addition to UDP/1812 when both transports are in use.

## Endpoint certificates

Create a bundle for an EOS endpoint:

```bash
sudo freeradius-certctl issue arista-eos-01 --vlan 120
```

It produces the endpoint certificate, private key, and an encrypted PKCS#12 bundle in `/etc/freeradius/3.0/certs/<hostname>/endpoints/`. Securely copy the `.p12` bundle and CA certificate to the endpoint/provisioning system. The export password is prompted by OpenSSL and is intentionally never stored. `--vlan` is optional; when supplied, it creates a CN-to-VLAN entry in `/etc/freeradius/3.0/certs/<hostname>/cn-vlan` and reloads FreeRADIUS.

During EAP-TLS, FreeRADIUS requires an endpoint certificate issued by this CA, checks it against the current CRL, and requires the EAP identity to match the certificate Common Name. After successful certificate validation, it looks up that validated certificate CN in the CN-to-VLAN file and returns the standard VLAN tunnel attributes (`Tunnel-Type`, `Tunnel-Medium-Type`, and `Tunnel-Private-Group-ID`). Revoking an endpoint certificate also removes its VLAN entry.

Useful commands:

```bash
sudo freeradius-certctl list
sudo freeradius-certctl revoke arista-eos-01
sudo freeradius-certctl issue-server radius.example.net
```

Revocation updates the CRL and reloads the service. Do not copy the CA private key from the RADIUS server.

## Arista EOS note

EOS configuration syntax and certificate import commands vary by EOS release and platform. Configure the applicable Ethernet interface as an `802.1X supplicant`, select EAP-TLS, import the endpoint key/certificate and CA certificate, and make its EAP identity match the certificate identity (`arista-eos-01` above). The upstream authenticator must trust this CA only through this FreeRADIUS server; it communicates with FreeRADIUS using the RADIUS shared secret supplied at installation.

## Validate and troubleshoot

```bash
sudo freeradius -XC
sudo journalctl -u freeradius -f
sudo systemctl status freeradius
```

For an authentication failure, the live journal normally identifies whether it is an untrusted CA, a revoked certificate, an identity mismatch, or a RADIUS-client/shared-secret issue.
