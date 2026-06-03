# RayLite

[中文说明](./README.zh-CN.md)

**RayLite** is a one-click Linux deployment helper for **VMess + WebSocket + TLS + camouflage domain + optional Cloudflare reverse proxy**.

It targets small VPS instances such as **1 vCPU / 512 MB RAM**. The server exposes only one WebSocket route, `/ray`, through Nginx. All other ordinary paths behave like a minimal static website, which makes the domain look like a normal HTTPS site.

```text
Client
  -> Cloudflare reverse proxy, optional
  -> https://your-domain.example/ray
  -> Nginx :443
  -> 127.0.0.1:10086
  -> V2Ray Core VMess inbound
```


## Simple usage

RayLite is meant to be used in the simplest possible way:

```text
1. Create a Cloudflare DNS record and point your domain/subdomain to your VPS IP.
2. SSH into the VPS.
3. Run one command.
4. Import the generated VMess client link.
```

Example:

```bash
git clone https://github.com/your-name/RayLite.git
cd RayLite
chmod +x setup-raylite.sh
sudo env DOMAIN=v1.example.com bash setup-raylite.sh --yes
```

That is all for the default setup. The UUID is generated automatically by the script, so you do **not** need to prepare one manually. After installation, the importable client link is written to:

```bash
cat /root/raylite/client/v1.example.com.vmess.txt
```

Default stack:

```text
VMess + WebSocket + TLS + /ray + Nginx camouflage page + optional Cloudflare reverse proxy
```

For most users, the only required manual step before running the script is DNS setup:

```text
Cloudflare DNS:
A record -> your VPS public IP
SSL/TLS -> Full or Full (strict)
Network -> WebSockets -> On
```

Advanced options, troubleshooting, generated file paths, and manual configuration notes are documented below.

## Features

- Installs V2Ray Core through the official V2Fly FHS installation script.
- Detects common Linux distributions and package managers.
- Generates a UUID automatically for server/client authentication.
- Deploys VMess over WebSocket with TLS.
- Uses `/ray` as the default WebSocket forwarding route.
- Writes Nginx camouflage site and WebSocket reverse proxy config.
- Requests a Let's Encrypt certificate with Certbot standalone mode.
- Writes Certbot renewal hooks for standalone renewal.
- Adds optional swap for small-memory VPS instances.
- Adds optional TCP/BBR tuning.
- Configures UFW or firewalld when available.
- Generates directly importable client files.
- Prints a final summary of every generated or modified file.

## Supported systems

RayLite supports **systemd-based Linux distributions**.

| Family | Distributions |
|---|---|
| Debian family | Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin, Kali |
| Fedora family | Fedora |
| RHEL family | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux |
| Arch family | Arch Linux, Manjaro, EndeavourOS |
| SUSE family | openSUSE Leap, openSUSE Tumbleweed, SLES |

Supported package managers:

```text
apt, dnf, yum, pacman, zypper
```

Not recommended:

```text
Alpine Linux, OpenWrt, non-systemd systems, containers without real systemd, shared hosting
```

## Default deployment

```text
Protocol:          VMess
Transport:         WebSocket
TLS:               enabled
Public port:       443
WebSocket path:    /ray
Nginx route:       location = /ray
V2Ray listen:      127.0.0.1
V2Ray local port:  10086
alterId:           0
Security:          auto
```

Default public behavior:

```text
https://your-domain.example/       -> camouflage homepage
https://your-domain.example/ray    -> WebSocket reverse proxy to V2Ray
other missing paths                -> 404/static behavior
```

## Cloudflare setup before installation

Create a DNS record first:

```text
Type: A
Name: v1, proxy, ray, or any subdomain you prefer
Value: your VPS public IPv4 address
```

Recommended Cloudflare settings:

```text
SSL/TLS -> Overview -> Full or Full (strict)
Network -> WebSockets -> On
```

RayLite uses HTTP-01 certificate validation through Certbot standalone mode. During certificate issuance, Certbot needs TCP port `80` on the VPS.

If certificate issuance fails behind Cloudflare, check:

```text
1. The domain points to the VPS.
2. TCP 80 and 443 are open in the VPS firewall and cloud security group.
3. Cloudflare "Always Use HTTPS" is disabled during issuance.
4. If proxied mode fails, temporarily switch the DNS record to DNS only, rerun the script, then switch it back to Proxied.
```

## Quick start

```bash
git clone https://github.com/your-name/RayLite.git
cd RayLite
chmod +x setup-raylite.sh
sudo env DOMAIN=v1.example.com EMAIL=admin@example.com bash setup-raylite.sh --yes
```

Minimal command without email:

```bash
sudo env DOMAIN=v1.example.com bash setup-raylite.sh --yes
```

Custom WebSocket path and local V2Ray port:

```bash
sudo env DOMAIN=v1.example.com \
  WS_PATH=/ray \
  V2_PORT=10086 \
  EMAIL=admin@example.com \
  bash setup-raylite.sh --yes
```

Generate client files only:

```bash
bash setup-raylite.sh \
  --client-only \
  --domain v1.example.com \
  --uuid xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Preview without touching the system:

```bash
bash setup-raylite.sh \
  --dry-run \
  --root-dir /tmp/raylite-preview \
  --domain v1.example.com \
  --cert-mode none \
  --yes
```

## Script options

```text
--domain DOMAIN          Required domain, for example v1.example.com
--email EMAIL            Optional Let's Encrypt email
--ws-path PATH           WebSocket path, default: /ray
--v2-port PORT           Local V2Ray port, default: 10086
--uuid UUID              Optional custom UUID. If empty, one is generated.
--ps NAME                Client profile name
--output-dir DIR         Output directory, default: /root/raylite
--web-root DIR           Static camouflage website root. Default: /var/www/raylite/DOMAIN
--ssh-port PORT          SSH port allowed by firewall, default: 22
--no-firewall            Do not touch ufw/firewalld
--no-swap                Do not create swap
--no-bbr                 Do not write TCP/BBR sysctl tuning
--staging                Use Let's Encrypt staging environment
--force-cert-renew       Re-issue certificate even if cert path exists
--cert-mode MODE         standalone or none, default: standalone
--dry-run                Print intended actions without changing system
--root-dir DIR           With --dry-run, write preview files under DIR
--client-only            Only generate client JSON and vmess:// link; no root needed
-y, --yes                Non-interactive confirmation
-h, --help               Show help
```

Environment variables are also supported:

```text
DOMAIN, EMAIL, WS_PATH, V2_PORT, UUID, PS, OUTPUT_DIR, WEB_ROOT, SSH_PORT,
ENABLE_FIREWALL, ADD_SWAP, SWAP_SIZE, ENABLE_BBR, CERT_STAGING,
FORCE_CERT_RENEW, CERT_MODE, V2RAY_INSTALL_URL, DRY_RUN, ROOT_DIR,
CLIENT_ONLY, ASSUME_YES
```

## Generated and modified files

Typical server-side files:

```text
/usr/local/etc/v2ray/config.json
/etc/systemd/system/v2ray.service.d/20-raylite-user.conf
/etc/nginx/conf.d/00-raylite-websocket-map.conf
/etc/nginx/conf.d/raylite-your-domain.conf
/etc/sysctl.d/99-raylite.conf
/var/www/raylite/your-domain/index.html
/etc/letsencrypt/renewal-hooks/pre/raylite-stop-nginx.sh
/etc/letsencrypt/renewal-hooks/post/raylite-start-nginx.sh
```

Typical client-side files:

```text
/root/raylite/client/your-domain.json
/root/raylite/client/your-domain.vmess.txt
/root/raylite/client/your-domain.v2ray-client.json
/root/raylite/install-report-your-domain-YYYYMMDD-HHMMSS.txt
```

The script prints all generated and modified files at the end of the run.

## Client import

After installation, print the VMess import link:

```bash
cat /root/raylite/client/v1.example.com.vmess.txt
```

Import it into a VMess-compatible client.

Equivalent client settings:

```text
Protocol:       VMess
Address:        your domain
Port:           443
UUID:           generated by the script
alterId:        0
Security:       auto
Transport:      WebSocket
Path:           /ray
Host:           your domain
TLS:            enabled
SNI:            your domain
Allow insecure: false
```

`your-domain.v2ray-client.json` can be used with V2Ray Core as a local client config. It exposes:

```text
SOCKS: 127.0.0.1:10808
HTTP:  127.0.0.1:10809
```

## Verification

Check services:

```bash
nginx -t
systemctl status nginx
/usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
systemctl status v2ray
```

Check ports:

```bash
ss -lntp
```

Expected result:

```text
0.0.0.0:80        nginx
0.0.0.0:443       nginx
127.0.0.1:10086   v2ray
```

Test homepage:

```bash
curl -I https://v1.example.com/
```

Test WebSocket route:

```bash
curl -v --http1.1 \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://v1.example.com/ray
```

Notes:

```text
101 Switching Protocols -> ideal WebSocket upgrade result
400/405 from /ray       -> often means the request reached V2Ray/WebSocket, but the test is not a real VMess session
timeout                 -> check DNS, firewall, Cloudflare, Nginx, VPS security group
```

## Manual configuration checklist

Before running the script:

```text
1. Configure DNS A record for the domain.
2. Open TCP 80 and 443 in the cloud provider security group.
3. Keep SSH reachable.
4. If using Cloudflare, enable WebSockets.
5. If using Cloudflare, set SSL/TLS to Full or Full (strict).
```

After running the script:

```text
1. Import /root/raylite/client/your-domain.vmess.txt into your client.
2. Check that client Host and SNI both equal your domain.
3. Check that WebSocket path is exactly /ray unless you customized it.
4. If Certbot failed, try Cloudflare DNS only mode and rerun.
5. If Nginx cannot load files in /etc/nginx/conf.d/, inspect /etc/nginx/nginx.conf manually.
```

## Troubleshooting

Show recent logs:

```bash
journalctl -u nginx -n 100 --no-pager
journalctl -u v2ray -n 100 --no-pager
```

Show Nginx config:

```bash
nginx -T | sed -n '1,260p'
```

Show V2Ray config:

```bash
sed -n '1,220p' /usr/local/etc/v2ray/config.json
```

Test certificate renewal:

```bash
certbot renew --dry-run
```

## Security notes

- Keep the generated UUID private.
- Do not publish generated client files.
- Prefer SSH key authentication.
- Keep your VPS updated.
- Use a dedicated subdomain.
- Do not run unrelated heavy services on 512 MB VPS instances.

## Disclaimer

This project is intended for lawful personal networking, private infrastructure access, and educational server configuration practice. Users are responsible for complying with local laws, service provider terms, and network policies.

## Acknowledgements

Special thanks to:

- [V2Fly / V2Ray Core](https://github.com/v2fly/v2ray-core)
- [fhs-install-v2ray](https://github.com/v2fly/fhs-install-v2ray)
- [Nginx](https://nginx.org/)
- [Let's Encrypt](https://letsencrypt.org/)
- [Certbot](https://certbot.eff.org/)
- [Debian](https://www.debian.org/)
- [Ubuntu](https://ubuntu.com/)
- [Fedora](https://fedoraproject.org/)
- [Arch Linux](https://archlinux.org/)
- [openSUSE](https://www.opensuse.org/)
- [Cloudflare](https://www.cloudflare.com/)
- The open-source community

## License

RayLite is licensed under the [GNU General Public License v3.0](./LICENSE) (GPL-3.0-only).
