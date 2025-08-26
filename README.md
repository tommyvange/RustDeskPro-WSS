# RustDeskPro-WSS

A production-ready wrapper to run RustDesk Server Pro (hbbr/hbbs) behind Caddy with automatic HTTPS, Docker Compose, and a hardened firewall posture.

This repo gives you two paths:
- Automated install with `install.sh` (recommended)
- Manual step-by-step setup (do it yourself, explained in detail)

Works on Linux servers with Docker. Caddy terminates TLS for your domain and safely proxies only the required endpoints to hbbr/hbbs running on the host network.

---

## Quick start (automated install)

Prereqs
- A Linux server with root/sudo
- Docker Engine and Docker Compose Plugin installed
- A DNS A/AAAA record pointing your domain to this server’s public IP
- UFW or another firewall configured to match the [firewall section](#firewall-ufw-guide).

Steps
1) Clone the repository
```bash
git clone https://github.com/tommyvange/RustDeskPro-WSS.git
cd RustDeskPro-WSS
```

2) Copy the sample environment file and edit values
```bash
cp .env.example .env
${EDITOR:-nano} .env
```
Required:
- DOMAINS: Comma-separated list (e.g., rd.example.com,servername.westeurope.cloudapp.azure.com). The installer converts this to a space-separated list for Caddy.
- FILE_LOCATION_CADDY: Where Caddy keeps config/state (default in example: /srv/caddy).
- FILE_LOCATION_RUSTDESK: Where RustDesk Pro stores data (default in example: /srv/rustdesk).
Optional:
- RUSTDESK_CORS: true to keep the strict rustdesk.com-only CORS block; false to remove it.
Note: Leave UID/GID fields empty; the installer fills them in.

3) Make the installer executable
```bash
chmod +x install.sh
```

4) Run the installer as root (uses Docker, creates system users, writes files)
```bash
sudo ./install.sh
```

Verification
- Check containers: `docker compose ps`
- Visit: `https://your-domain` (Caddy auto‑obtains certificates; ensure ports 80/443 are reachable)

---

## What the installer does

The `install.sh` script performs these steps safely and idempotently:
- Validates it runs as root and that Docker/Compose are present
- Loads variables from `.env` (created from `.env.example`); requires: `DOMAINS`, `FILE_LOCATION_CADDY`, `FILE_LOCATION_RUSTDESK`
- Creates system users: `rustdesk` and `caddy` (no shell, no home)
- Writes their UID/GID back into `.env` so `compose.yml` runs containers as those users
- Creates and permissions data directories
  - RustDesk: `$FILE_LOCATION_RUSTDESK/data` owned by `rustdesk:rustdesk` (750)
  - Caddy: `$FILE_LOCATION_CADDY/{data,config}` owned by `caddy:caddy` (750)
- Processes `Caddyfile`
  - Replaces `EXAMPLE.COM` with your `DOMAINS` (comma → space list)
  - Removes the CORS block if `RUSTDESK_CORS=false`; otherwise keeps it
  - Copies the processed file to `$FILE_LOCATION_CADDY/Caddyfile` (640, owner `caddy`)
- Orchestrates containers
  - `docker compose down` (if any), `pull`, then `up -d --force-recreate`
  - Prints a final status summary

If any required bits are missing (Docker not installed, `.env` absent, etc.), the script exits with a clear error and what to fix.

---

## Manual setup (do it yourself)

This is a simple, copy‑paste friendly guide that avoids the `.env` file. We’ll hardcode clear paths so you see exactly what’s happening.

Before you start: make sure your domain (for example, example.com) points to your server’s public IP, and Docker is installed.

1) Pick where files will live (you can change these)
- Caddy files: /srv/caddy
- RustDesk data: /srv/rustdesk

2) Create the folders
```bash
sudo mkdir -p /srv/caddy/data /srv/caddy/config
sudo mkdir -p /srv/rustdesk/data
```

3) (Optional but recommended) Create service users for better security
```bash
sudo useradd --system --no-create-home --shell /bin/false rustdesk || true
sudo useradd --system --no-create-home --shell /bin/false caddy || true

id -u rustdesk; id -g rustdesk   # note these numbers, e.g. 998 998
id -u caddy;    id -g caddy      # note these numbers, e.g. 997 997
```
If you skip this, containers will run as their default users. That’s simpler but less locked‑down.

4) Tell Docker where to store things (edit compose.yml)
- Open the file `compose.yml` in an editor.
- Find and replace the paths so they point to your folders:
  - Change `${FILE_LOCATION_RUSTDESK}/data` to `/srv/rustdesk/data`
  - Change `${FILE_LOCATION_CADDY}/Caddyfile` to `/srv/caddy/Caddyfile`
  - Change `${FILE_LOCATION_CADDY}/data` to `/srv/caddy/data`
  - Change `${FILE_LOCATION_CADDY}/config` to `/srv/caddy/config`
- About the `user: "${...}:${...}"` lines:
  - If you created users above, replace with the numbers you noted. Example: `user: "998:998"`
  - If you didn’t create users, you can remove or comment out those `user:` lines.

5) Prepare and place the Caddyfile
- Open the file `Caddyfile` (in this repo) and edit two things:
  1) Replace `EXAMPLE.COM` with your real domain. If you have www too, write both separated by a space, like:
     `example.com www.example.com {`
  2) Decide the CORS block:
     - Keep it if you want to only allow requests from rustdesk.com
     - Remove the whole block between `### CORS - START ###` and `### CORS - END ###` if you don’t need that restriction
- Set folder ownership, lock down the folder and copy the Caddyfile.
```bash
sudo chown -R caddy:caddy /srv/caddy || true
sudo chmod -R 750 /srv/caddy
sudo cp Caddyfile /srv/caddy/Caddyfile
sudo chmod 640 /srv/caddy/Caddyfile
```

6) Set ownership on the RustDesk data folder (if you created the user)
```bash
sudo chown -R rustdesk:rustdesk /srv/rustdesk || true
sudo chmod -R 750 /srv/rustdesk
```

7) Start the containers
```bash
docker compose pull                       # download images (safe to ignore failures)
docker compose up -d --force-recreate     # start in the background
docker compose ps                         # show status
```

8) Visit your site and test
- Go to https://your-domain in a browser. Caddy will get a certificate automatically (leave it a minute the first time).
- If it doesn’t work, check:
  - DNS is pointing to this server (run `dig +short your-domain` and verify the IP)
  - Ports 80 and 443 are allowed in your firewall
  - Logs for the caddy container for any certificate messages

Tip: See the Firewall section below for the exact allow/deny rules to use with UFW.

---

## How the stack is wired

- hbbr (RustDesk relay) and hbbs (RustDesk broker) run with `network_mode: host` by design (required by licensing and to expose the expected ports locally)
- Data volume: `${FILE_LOCATION_RUSTDESK}/data` → container `/root` for both hbbr and hbbs (where RustDesk stores config/state)
- Caddy also runs on the host network so it can proxy to `127.0.0.1:21114/18/19`
- Caddy mounts:
  - `${FILE_LOCATION_CADDY}/Caddyfile:/etc/caddy/Caddyfile:ro`
  - `${FILE_LOCATION_CADDY}/data` (ACME certs/state)
  - `${FILE_LOCATION_CADDY}/config`

### Architecture map: traffic flow and firewall

```
┌─────────────────────────────────────────────────────────────────────┐
│                           INTERNET                                  │
│                         Users/Clients                               │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
            ┌─────▼─────┐
            │  Firewall │ 
            │  (UFW)    │ ALLOW: 80/tcp, 443/tcp, 443/udp
            │           │ DENY:  21114-21119/tcp, 21116/udp
            └─────┬─────┘
                  │
         ┌────────▼─────────┐
         │  Your Server     │
         │  Public IP       │
         └────────┬─────────┘
                  │
    ┌─────────────▼──────────────┐
    │        Caddy Container     │ (network_mode: host)
    │   - Automatic HTTPS/TLS    │
    │   - Reverse Proxy          │ Binds to: 80, 443
    │   - CORS handling          │
    └─────────────┬──────────────┘
                  │
         ┌────────▼────────┐
         │ Request Routing │
         └─────┬───────────┘
               │
      ┌────────▼────────┐
      │ Path-based      │
      │ Distribution    │
      └─┬─────────────┬─┘
        │             │
   ┌────▼──────┐ ┌───▼────────────────────┐
   │/ws/id*    │ │/ws/relay*         /*   │
   │WebSocket  │ │WebSocket       Console │
   └────┬──────┘ └───┬──────────┬─────────┘
        │            │          │
        │    ┌───────▼──────┐   │
        │    │              │   │
        ▼    ▼              ▼   ▼
┌──────────────┐    ┌──────────────┐
│ hbbs         │    │ hbbr         │ (network_mode: host)
│ (RustDesk    │    │ (RustDesk    │
│  Broker)     │    │  Relay)      │
│              │    │              │
│ :21114 (API) │    │ :21119 (WS)  │ Bound to 127.0.0.1
│ :21118 (WS)  │    │ :21116 (UDP) │ (not Internet-facing)
└──────────────┘    └──────────────┘

Legend:
┌─────┐ Container/Service   ▼ Network flow   ─ Firewall rule
```

**Traffic Flow Examples:**
- User visits `https://example.com` → Caddy :443 → hbbs :21114 (web console)
- WebSocket ID request → Caddy `/ws/id*` → hbbs :21118
- WebSocket relay → Caddy `/ws/relay*` → hbbr :21119
- NAT traversal (UDP) → hbbr :21116 (direct, not through Caddy)

TLS: Caddy obtains and renews certificates automatically via HTTPS-01/HTTP-01. Ensure:
- `DOMAINS` point to this server (A/AAAA records)
- Ports 80/tcp and 443/tcp+udp reachable from the Internet

CORS: When enabled (default), the Caddyfile allows cross-origin requests from `https://rustdesk.com` only. If you self-host a console on another origin, disable via `RUSTDESK_CORS=false` and tailor the CORS section.

---

## Firewall (UFW) guide

Important: Before enabling UFW, make sure you allow SSH or you may lock yourself out.

Baseline rules
```bash
# Keep your SSH open (adjust if not 22)
sudo ufw allow 22/tcp

# Public web: HTTPS and HTTP (for ACME http-01 and redirect)
sudo ufw allow 443/tcp   # HTTPS and WebSockets via Caddy
sudo ufw allow 443/udp   # HTTP/3 (QUIC) via Caddy (optional but recommended)
sudo ufw allow 80/tcp    # ACME challenge + HTTP→HTTPS redirect

# Allow loopback explicitly (good hygiene)
sudo ufw allow in on lo

# Hide RustDesk backend ports from the Internet (Caddy will proxy)
sudo ufw deny 21114:21119/tcp  # hbbs console (21114), WS (21118/21119), etc.
sudo ufw deny 21116/udp        # NAT test

# Enable UFW if not already on
sudo ufw enable

# Review
sudo ufw status numbered
```

Why these ports?
- 80/tcp: Caddy uses this for ACME HTTP-01 and to redirect to HTTPS
- 443/tcp: TLS/HTTPS and WebSockets for RustDesk endpoints
- 443/udp: HTTP/3 (QUIC) for faster TLS on supporting clients
- 21114/21118/21119 (tcp) and 21116 (udp): RustDesk services bound locally; should not be Internet-exposed when proxied by Caddy

If you run a different firewall (nftables/iptables/cloud), translate the same intent: expose 80/443, keep RustDesk backend ports closed to the outside.

---

## Operations

- Status: `docker compose ps`
- Logs: `docker compose logs -f --tail=200`
- Restart: `docker compose restart`
- Update images: `docker compose pull && docker compose up -d`
- Stop: `docker compose down`

Backups
- Back up `${FILE_LOCATION_RUSTDESK}` and `${FILE_LOCATION_CADDY}` regularly. They hold RustDesk state and Caddy’s ACME material.

Uninstall (manual)
```bash
docker compose down
sudo rm -rf "$FILE_LOCATION_RUSTDESK" "$FILE_LOCATION_CADDY"
# Optionally remove users (only if dedicated to this stack)
sudo userdel rustdesk || true
sudo userdel caddy || true
```

---

## Troubleshooting

- Script says ".env file not found"
  - Create `.env` from the template and set at least `DOMAINS`, `FILE_LOCATION_CADDY`, `FILE_LOCATION_RUSTDESK`
- Caddy can’t obtain a certificate
  - Check DNS records, make sure ports 80 and 443 are open and not used by another service
  - Inspect: `docker compose logs caddy`
- Ports already in use (bind errors)
  - Another web server (nginx/apache/caddy host install) may be running; stop it or change ports
- Can’t reach backend ports from the Internet
  - That’s intentional; access via your domain through Caddy only
- Docker/Compose not found
  - Install Docker Engine + Compose Plugin from the official docs

---

## Notes and recommendations

- Images are `:latest` for convenience. For production stability, consider pinning versions in `compose.yml`.
- This setup assumes Linux; macOS/Windows won’t support `network_mode: host` the same way.
- Keep your domain list in `.env` up to date. You can rerun the installer any time; it’s safe.
- Use the included `.env.example` as a starting point and keep it around to document your defaults.

---

## License

MIT License. See `LICENSE`.
