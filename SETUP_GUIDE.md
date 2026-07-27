# Step-by-Step Setup Guide

This walks through building the platform from a blank machine to a fully running, secured stack. Follow the steps in order. Each one builds on the last.

## Step 1: Prepare the Host

Install Ubuntu Server 24.04 LTS on your hardware. During install:

- Enable OpenSSH server
- Create a non-root user with sudo access
- Skip snap packages you don't need (they add overhead you won't use)

Once it boots, update the system:

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

Note the host's local IP address. You'll need it for Ansible.

```bash
ip a
```

## Step 2: Generate SSH Keys and Lock Down Access

On your local machine, not the server:

```bash
ssh-keygen -t ed25519 -C "homelab-admin"
ssh-copy-id youruser@your-server-ip
```

Confirm key-based login works before you disable passwords:

```bash
ssh youruser@your-server-ip
```

Leave password authentication on for now. Ansible will disable it in the next step, once key access is confirmed.

## Step 3: Run Ansible to Harden the Host

From your local machine, clone the repo and set your inventory:

```bash
git clone https://github.com/pushkarkadian28/home-lab-platform.git
cd home-lab-platform/ansible
cp inventory.example.ini inventory.ini
```

Install the required Ansible collections before running anything. Newer versions of Ansible split `sysctl` and `ufw` out of ansible-core, so these playbooks fail without them:

```bash
ansible-galaxy collection install -r requirements.yml
```

If you installed Ansible with `pip install ansible-core` instead of the full `ansible` package, install the full package instead to avoid missing collections in general:

```bash
pip install ansible
```

Edit `inventory.ini` with your server's IP and SSH user, then run:

```bash
ansible-playbook -i inventory.ini playbooks/harden.yml
```

If the command "ansible-playbook -i inventory.ini playbooks/harden.yml" gives an error message: "Task failed: Timed out waiting for become success or become password prompt."
```bash
echo "home2006 ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible > /dev/null
sudo chmod 440 /etc/sudoers.d/ansible
sudo visudo -c
```
Should show:
```
/etc/sudoers.d/ansible: parsed OK
```

This playbook:

- Disables SSH password authentication
- Installs and configures fail2ban
- Applies sysctl hardening (SYN flood protection, disabled IP forwarding)
- Sets up UFW with a default-deny inbound policy, SSH allowed only from your management network

Verify SSH still works before closing your current session. If it doesn't, you still have your current session open to fix it.

## Step 4: Install Docker

```bash
ansible-playbook -i inventory.ini playbooks/docker-install.yml
```

Confirm it worked:

```bash
ssh youruser@your-server-ip
docker --version
docker compose version
```

## Step 5: Set Up Cloudflare

Before touching the server again, set up Cloudflare:

1. Add your domain to Cloudflare and point its nameservers there.
2. In the Cloudflare dashboard, go to Zero Trust, then Networks, then Tunnels.
3. Create a tunnel and name it something like `homelab`.
4. Copy the tunnel token. You'll drop this into your `.env` file.
5. Add a public hostname for each service you plan to run (for example, `cloud.yourdomain.com` routing to `nextcloud:80`). You can add these now or after the containers are up.

No ports need to be open on your router for any of this.

## Step 6: Configure Environment Variables

Back on the server:

```bash
cd ~/home-lab-platform
cp secrets.example.env .env
nano .env
```

Fill in real values:

- `DOMAIN`: your actual domain
- `CF_TUNNEL_TOKEN`: the token from Step 5
- `AUTHELIA_SESSION_SECRET` and `AUTHELIA_STORAGE_ENCRYPTION_KEY`: generate with `openssl rand -hex 32`
- Database and admin passwords for each service

Never commit this file. Confirm it's in `.gitignore` before you do anything else.

## Step 7: Configure Traefik

Edit `traefik/traefik.yml` to set your Cloudflare API token for DNS-01 certificate challenges. This avoids needing port 80 open at all.

Edit `traefik/dynamic.yml` to define routing rules for each service and attach the Authelia forward-auth middleware to each one.

## Step 8: Configure Authelia

Edit `authelia/configuration.yml`:

- Set your domain
- Define user accounts (or connect an LDAP backend if you have one)
- Configure TOTP settings for MFA
- Set session and access control rules per service

Generate user password hashes with:

```bash
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'
```

Paste the resulting hash into the Authelia user database file. Never store plaintext passwords there.

## Step 9: Launch the Stack

```bash
docker compose up -d
```

Watch the logs during first boot:

```bash
docker compose logs -f
```

Give it a minute. Some services (Nextcloud, Immich) take longer to initialize on first run.

## Step 10: Verify Each Service

Check container health:

```bash
docker compose ps
```

Visit each domain in a browser. You should hit the Authelia login page first, every time, before any application loads. If a service loads without prompting for login, check that its Traefik label includes the Authelia middleware.

Set up MFA on your Authelia account immediately, using an authenticator app to scan the TOTP QR code.

## Step 11: Complete Per-Service Setup

- **Nextcloud**: log in with the admin password from `.env`, then set up your storage quota and any desired apps.
- **Vaultwarden**: create your first vault account. Disable public registration in `.env` once your accounts exist.
- **Immich**: install the mobile app, point it at your domain, and enable automatic backup.
- **Paperless-ngx**: set up your document storage paths and run a test scan through OCR to confirm it's tagging and indexing correctly.

## Step 12: Stand Up Monitoring

Confirm Prometheus is scraping targets:

```
https://prometheus.yourdomain.com/targets
```

All targets should show as `UP`. If `node-exporter` or `cadvisor` show as down, check their container status and network config.

Log into Grafana with the admin password from `.env`, then import the dashboards from `monitoring/grafana/dashboards`. Point them at the Prometheus data source.

Set up at least two alerts to start:

- Disk usage above 85 percent, sustained for 10 minutes
- Any container restarting more than twice in 5 minutes

## Step 13: Set Up Backups

Write a backup script that snapshots your Docker volumes on a schedule, then syncs to external storage. A minimal cron entry:

```bash
0 3 * * * /home/youruser/scripts/backup.sh >> /var/log/backup.log 2>&1
```

Test the restore process once, before you need it for real. A backup you haven't restored is a guess, not a backup.

## Step 14: Final Security Pass

- Run `sudo ufw status verbose` and confirm only SSH is allowed inbound, from your management network only.
- Confirm `PasswordAuthentication no` is set in `/etc/ssh/sshd_config`.
- Confirm no service in `docker-compose.yml` publishes a port directly to the host. Everything should route through Traefik.
- Rotate the Authelia secrets and any default passwords you used during testing.

## Step 15: Document and Commit

Push your configuration to your own repository, with `.env` and any real secrets excluded. Keep `secrets.example.env` up to date as a template for anyone (including future you) rebuilding this from scratch.

At this point you have a working platform: authenticated, encrypted, monitored, and reproducible from code.
