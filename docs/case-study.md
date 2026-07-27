# Building a Zero-Trust Home Cloud: A Case Study in Self-Hosted Infrastructure

## The Problem

I was paying for four separate cloud subscriptions: storage, password management, photo backup, and a document scanning app. Each one held a slice of my data on someone else's server. I wanted to bring that data home, run it on hardware I control, and secure it to the same standard I'd expect in a production environment at work. This is the write-up of how I did it.

## Starting Point

The hardware was simple: a repurposed desktop PC running Ubuntu Server 24.04 LTS. No enterprise gear, no rack, no budget for anything fancy. The constraint shaped every decision that followed. If a solution needed expensive hardware or a dedicated appliance, it was off the table.

The bigger constraint was security. A home server sitting on a residential connection is a target the moment you open a port. My first rule for this project was simple: the router forwards nothing.

## Design Decision One: Zero Open Ports

Most self-hosted guides tell you to forward port 443 on your router and point it at a reverse proxy. That approach works, but it puts your home IP address directly in the line of fire. Every port scanner on the internet eventually finds it.

Instead, I used Cloudflare Tunnels. A lightweight daemon (`cloudflared`) runs on the host and opens an outbound connection to Cloudflare's edge network. Traffic reaches my services through that tunnel, never through an inbound connection to my router. The router's firewall has nothing to forward, because there's nothing listening on a public interface.

This one decision eliminated an entire category of attack surface. No port scan finds an open port, because there isn't one.

## Design Decision Two: One Login, Not Four

Each app I wanted to self-host (Nextcloud, Vaultwarden, Immich, Paperless-ngx) ships its own authentication system. Left alone, that means four separate logins, four separate password policies, and four separate places for a weak configuration to slip through.

I put Authelia in front of everything as a forward-auth provider, sitting behind Traefik. When a request hits Traefik, Traefik checks with Authelia before it lets the request through to the application. Authelia handles the login screen, the session, and the multi-factor prompt, once, for every service behind it.

The practical effect: I log in one time per session, with a TOTP code, and every service trusts that session. If I want to tighten the policy (say, require MFA on every login instead of once per session for sensitive apps like Vaultwarden), I change one Authelia rule instead of hunting through four different app settings.

## Design Decision Three: Infrastructure as Code, Not Manual Setup

I built and rebuilt this server more than once during testing, and manual setup got old fast. So the entire host configuration lives in Ansible playbooks: user creation, SSH hardening, UFW rules, kernel-level sysctl tuning, Docker installation, and fail2ban setup all run from a single command.

This matters for two reasons. First, it makes disaster recovery realistic. If the drive dies, I'm not reconstructing configuration from memory. I run the playbooks against a fresh install and I'm back to a known state in minutes, not hours. Second, it makes the hardening auditable. Anyone can read `harden.yml` and see exactly what security posture the host has, instead of trusting that I remembered every step correctly the last time I touched the box by hand.

## Operational Challenges

**Container networking with a forward-auth proxy.** Traefik's forward-auth middleware needs to reach Authelia on every single request, which means Authelia's uptime is now a dependency for every other service. I mitigated this by giving Authelia its own healthcheck in Docker Compose and configuring Traefik to fail closed, not open. If Authelia goes down, services become inaccessible rather than accessible without authentication. Slower recovery, but the right failure mode for a security-focused stack.

**Secrets management without a vault server.** Running something like HashiCorp Vault felt like overkill for a single-host home lab. I settled on `.env` files excluded from git, loaded directly by Docker Compose, with a `secrets.example.env` template committed instead. It's not enterprise-grade secrets management, but it matches the actual threat model for this project and keeps the setup approachable for anyone using the repo as a reference.

**Certificate and DNS churn.** Early on, Traefik would occasionally hit Let's Encrypt rate limits during testing because every `docker compose up` regenerated challenge requests. I fixed this by switching to DNS-01 challenges through the Cloudflare API instead of HTTP-01, which also removed the need for port 80 to be reachable at all, consistent with the zero-open-port design.

**Monitoring without alert fatigue.** Prometheus and Grafana were easy to stand up. Tuning the alert thresholds so I wasn't getting paged for a 2 AM backup job spiking CPU took longer. I ended up scoping alerts to sustained conditions (5+ minutes above threshold) rather than instantaneous spikes, which cut false positives significantly.

## What This Demonstrates

This project is a home lab, but the problems it solves are not toy problems. Zero-trust ingress, centralized identity, infrastructure as code, and layered defense are the same concerns you'd address running production infrastructure at any company. The scale is smaller. The discipline is the same.

## What's Next

I'm working on adding automated off-site backup verification (a scheduled job that actually restores a sample backup and checks integrity, not just confirms the backup ran), and evaluating a move to a small Proxmox cluster for better isolation between services. Both will get their own write-up once they're live.

The full source, including all Ansible playbooks, Docker Compose files, and Traefik configuration, is available on GitHub with placeholder values in place of real secrets.
