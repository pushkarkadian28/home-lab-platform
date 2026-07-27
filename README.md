# Self-Hosted Cloud Platform: Home Lab Infrastructure

A production-grade, self-hosted cloud platform built on a single home server. Zero open inbound ports, full SSO across every service, and infrastructure defined as code from the OS layer up.

![Status](https://img.shields.io/badge/status-active-brightgreen)
![Docker](https://img.shields.io/badge/docker-compose-blue)
![Ansible](https://img.shields.io/badge/automation-ansible-red)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## Why This Exists

Cloud storage and productivity tools cost money every month and hand your data to a third party. This project replaces Google Drive, Bitwarden's hosted tier, Google Photos, and a document scanner app with self-hosted equivalents, all running on repurposed hardware, secured to a standard you'd expect in a production environment.

## Architecture

```
                              INTERNET
                                 │
                                 │ (no inbound ports open)
                                 ▼
                     ┌───────────────────────┐
                     │   Cloudflare Tunnel    │
                     │  (outbound-only conn)  │
                     └───────────┬────────────┘
                                 │
                                 ▼
                     ┌───────────────────────┐
                     │   Traefik (Reverse     │
                     │   Proxy + TLS + Auth   │
                     │   Middleware)          │
                     └───────────┬────────────┘
                                 │
                     ┌───────────▼────────────┐
                     │   Authelia (SSO / MFA) │
                     │   Forward-Auth Gateway │
                     └───────────┬────────────┘
                                 │
        ┌────────────┬──────────┼──────────┬─────────────┐
        ▼            ▼          ▼          ▼             ▼
   ┌─────────┐  ┌──────────┐┌────────┐┌───────────┐┌────────────┐
   │Nextcloud│  │Vaultwarden││Immich ││Paperless- ││ Grafana /   │
   │         │  │           ││       ││ngx        ││ Prometheus  │
   └────┬────┘  └─────┬─────┘└───┬────┘└─────┬─────┘└──────┬─────┘
        │             │          │           │             │
        └─────────────┴──────────┴───────────┴─────────────┘
                                 │
                     ┌───────────▼────────────┐
                     │   Docker Engine Host    │
                     │   Ubuntu Server 24.04   │
                     │   (Ansible-hardened)    │
                     └────────────────────────┘
```

All inbound traffic reaches the host through an outbound-only Cloudflare Tunnel. The router has no forwarded ports and no exposed services. Every request passes through Traefik, then through Authelia's forward-auth check, before it ever touches an application container.

## Stack

| Layer | Tool | Purpose |
|---|---|---|
| Host OS | Ubuntu Server 24.04 LTS | Base operating system |
| Virtualization | Proxmox VE (optional) | VM/container isolation |
| Orchestration | Docker Compose | Service deployment |
| Reverse Proxy | Traefik v3 | Routing, TLS termination |
| Ingress | Cloudflare Tunnels | Zero open ports |
| Identity | Authelia | SSO, MFA, forward-auth |
| Monitoring | Prometheus + Grafana | Metrics, dashboards, alerting |
| Automation | Ansible | Host provisioning, hardening |
| Firewall | UFW | Host-level packet filtering |

## Hosted Services

- **Nextcloud**: file sync and collaboration, replaces Google Drive
- **Vaultwarden**: password management, Bitwarden-compatible server
- **Immich**: photo and video backup, replaces Google Photos
- **Paperless-ngx**: document scanning, OCR, and archival

## Security Architecture

- **Zero open inbound ports.** The router forwards nothing. All ingress runs through Cloudflare Tunnels, which establish an outbound-only connection from the host to Cloudflare's edge.
- **Single sign-on everywhere.** Authelia sits in front of every service as a forward-auth provider. One login, one MFA prompt, applied consistently across the platform.
- **MFA on every service.** TOTP-based multi-factor authentication is enforced at the Authelia layer, not left to each app's own (often inconsistent) implementation.
- **Encrypted SSH access only.** Password authentication is disabled at the SSH daemon level. Key-based access only, keys generated with modern ciphers.
- **Host-level firewall.** UFW blocks all inbound traffic except SSH from a known management network. Docker's default iptables behavior is explicitly overridden to prevent container port leaks.
- **Secrets kept out of version control.** All credentials live in `.env` files excluded via `.gitignore`. This repo ships `secrets.example.env` as a template only.

## Repository Structure

```
.
├── ansible/
│   ├── playbooks/
│   │   ├── harden.yml
│   │   ├── docker-install.yml
│   │   └── firewall.yml
│   ├── inventory.example.ini
│   └── roles/
├── docker-compose.yml
├── traefik/
│   ├── traefik.yml
│   └── dynamic.yml
├── authelia/
│   └── configuration.yml
├── secrets.example.env
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
│       └── dashboards/
└── README.md
```

## Getting Started

### Prerequisites

- A Linux host (bare metal or VM) with Docker and Docker Compose installed
- A domain name with DNS managed through Cloudflare
- A Cloudflare account with Zero Trust enabled

### 1. Clone and configure

```bash
git clone https://github.com/pushkarkadian28/home-lab-platform.git
cd home-lab-platform
cp secrets.example.env .env
```

Edit `.env` with your own values:

```bash
# secrets.example.env
DOMAIN=example.com
CF_TUNNEL_TOKEN=your_cloudflare_tunnel_token_here
AUTHELIA_SESSION_SECRET=changeme_generate_random_64char_string
AUTHELIA_STORAGE_ENCRYPTION_KEY=changeme_generate_random_64char_string
POSTGRES_PASSWORD=changeme
NEXTCLOUD_ADMIN_PASSWORD=changeme
GRAFANA_ADMIN_PASSWORD=changeme
```

### 2. Harden the host with Ansible

```bash
cd ansible
cp inventory.example.ini inventory.ini
# edit inventory.ini with your host IP

ansible-playbook -i inventory.ini playbooks/harden.yml
ansible-playbook -i inventory.ini playbooks/docker-install.yml
ansible-playbook -i inventory.ini playbooks/firewall.yml
```
If command "ansible-playbook -i inventory.ini playbooks/harden.yml" gives error msg: "Task failed: Timed out waiting for become success or become password prompt."
```bash
echo "home2006 ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible > /dev/null
sudo chmod 440 /etc/sudoers.d/ansible
sudo visudo -c
```
Should show:
```
/etc/sudoers.d/ansible: parsed OK
```

The hardening playbook:
- Disables SSH password authentication
- Configures UFW with a default-deny inbound policy
- Applies kernel-level `sysctl` hardening (disabled IP forwarding where not needed, SYN flood protection)
- Creates a non-root deploy user with sudo access
- Installs and configures `fail2ban`

### 3. Launch the stack

```bash
docker compose up -d
```

### 4. Verify

```bash
docker compose ps
docker compose logs -f traefik
```

Check that each service resolves through your domain and that Authelia's login page appears before any application loads.

## Monitoring

Grafana dashboards track:
- Container CPU, memory, and disk I/O per service
- Traefik request rates and response codes
- Host-level metrics (load, disk usage, network throughput)
- Authelia authentication attempts and failures

Prometheus scrapes metrics every 15 seconds from `cadvisor`, `node-exporter`, and Traefik's built-in metrics endpoint.

## Operational Notes

- Backups run nightly via a cron-triggered script that snapshots Docker volumes to an external drive, then syncs to encrypted cloud storage.
- Container images are pinned to specific versions, not `latest`, to avoid unplanned breaking changes on restart.
- Watchtower is intentionally not used. Updates are applied manually after review, on a monthly cadence.

## License

MIT. See `LICENSE` for details.

## Disclaimer

This repository is a portfolio project documenting a personal home lab. Configuration files use placeholder values. Do not commit real secrets, tokens, or passwords to any public repository.
