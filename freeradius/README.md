# FreeRADIUS EAP-TLS for wired 802.1X

This is an Ubuntu/FreeRADIUS 3 deployment for certificate-based wired 802.1X (EAP-TLS). It deliberately permits no password EAP methods.

## Install

The **RADIUS client** is the switch that receives EAPOL and forwards EAP to this server (the authenticator). It is not normally the Arista switch using its front-panel port as an 802.1X supplicant.

```bash
cd freeradius
sudo ./install.sh --nas-ip 192.0.2.10 --nas-secret 'use-a-long-random-shared-secret' --server-name radius.example.net
```

The installer installs `freeradius`, `freeradius-utils`, `openssl`, and `gettext-base` (for `envsubst`); saves replaced configuration files in `/etc/freeradius/3.0/.network-toolkit-backup-*`; creates a private CA; and starts the service. Allow UDP/1812 from the authenticator to the server in the firewall.

For more authenticators, add one `client` block to `/etc/freeradius/3.0/clients.d/network-toolkit.conf`, then run `sudo systemctl reload freeradius`.

## Endpoint certificates

Create a bundle for an EOS endpoint:

```bash
sudo freeradius-certctl issue arista-eos-01
```

It produces the endpoint certificate, private key, and an encrypted PKCS#12 bundle in `/etc/freeradius/3.0/certs/network-toolkit/endpoints/`. Securely copy the `.p12` bundle and CA certificate to the endpoint/provisioning system. The export password is prompted by OpenSSL and is intentionally never stored.

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
