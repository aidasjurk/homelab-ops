# Dell OptiPlex 7070 SFF • Production Homelab Operations

[![OS: Debian 12](https://img.shields.io/badge/OS-Debian_12_(Bookworm)-a81d33?logo=debian&logoColor=white)](#1-hardware--physical-setup)
[![Hardware: i5--8500](https://img.shields.io/badge/Hardware-Intel_i5--8500_|_Samsung_970_Pro-0071c5?logo=intel&logoColor=white)](#1-hardware--physical-setup)
[![Memory: zram/zstd](https://img.shields.io/badge/Memory-8GB_DDR4_+_zram(zstd)-blueviolet)](#1-hardware--physical-setup)
[![Security: UFW Hardened](https://img.shields.io/badge/Security-UFW_&_SSH_Hardened-success?logo=gnubash&logoColor=white)](#2-network-topology--security)
[![DNS: AdGuard Home](https://img.shields.io/badge/DNS-AdGuard_Home_(DoH)-success?logo=adguard&logoColor=white)](#2-network-topology--security)
[![Backups: 3-2-1 Strategy](https://img.shields.io/badge/Backups-Rclone_AES--256_Encrypted-blue?logo=google-drive&logoColor=white)](#3-storage--backup-strategy)

Personal documentation, architectural specifications, security hardening policies, disaster recovery automation, and systematic triage runbook for a headless Dell OptiPlex 7070 SFF production home server.

---

## 0. Implementation Plan & Live Status Tracker

| Component | Category | Status | Details / What Works & What Doesn't |
| :--- | :--- | :--- | :--- |
| **BIOS / UEFI Settings** | Firmware | ✅ Working | AC Recovery, SpeedShift, C-states, headless boot enabled |
| **Debian 12 Base System** | OS | ✅ Working | Headless install, user permissions, `sudo` access |
| **SSH Hardening** | Security | ✅ Working | Ed25519 keys only, password auth disabled (`/etc/ssh/sshd_config.d/99-hardened.conf`), root login denied, verified via `sshd -T` |
| **Fish Shell + Starship** | Environment | ✅ Working | Interactive shell, autosuggestions, Starship prompt |
| **Memory Optimization (`zram`)** | OS Performance | ✅ Working | `zram-tools` with `zstd` algorithm active (~12–14 GB effective) |
| **Power Management** | OS Performance | ✅ Working | `cpupower` governor set to `powersave`, `powertop.service` active |
| **UFW Firewall** | Network | ✅ Working | Default deny inbound, Docker forwarding allowed |
| **Android Private DNS Fix** | Network | ✅ Working | Port `853/tcp` rejected; mobile clients fall back to local port 53 |
| **AdGuard Home** | DNS | ✅ Working | Local DNS filter active; upstream encrypted DoH/DoT (Quad9, Cloudflare) |
| **Automated OS Updates** | Maintenance | ✅ Working | `unattended-upgrades` configured for background CVE patches |
| **Google Drive Backup Sync** | Backups | ✅ Working | `rclone crypt` with AES-256 overlay active over `gdrive:server-backups/`, verified with live encryption tests |
| **Local Snapshot Script** | Backups | ✅ Working | `/usr/local/bin/backup-stacks.sh` active; creates atomic local tarballs with 7-day retention & offsite sync |
| **Cloudflare DNS & Custom Domain** | DNS | ⏳ Planned | `briefnodeops.com` setup on Cloudflare DNS; API token for DNS-01 ACME automated SSL |
| **Caddy Reverse Proxy** | Infrastructure | ⏳ Planned | Custom build with `caddy-dns/cloudflare` plugin for internal HTTPS (`*.briefnodeops.com`) |
| **docker-socket-proxy** | Security | ⏳ Planned | API isolation to shield `/var/run/docker.sock` |
| **Vaultwarden** | Applications | ⏳ Planned | Password vault, WebSocket sync, SQLite backup hook |
| **Joplin Server** | Applications | ⏳ Planned | Multi-device note syncing backend |
| **Immich** | Applications | ⏳ Planned | Self-hosted photo library with Intel QuickSync (`/dev/dri`) |
| **Homepage Dashboard** | Applications | ⏳ Planned | Unified service dashboard and system monitoring widgets |
| **SearXNG & IT-Tools** | Applications | ⏳ Planned | Private search and self-hosted developer tools |
| **Kasm Workspaces** | Applications | ⏳ Planned | Isolated browser/desktop sandbox environments |

---

## 1. Hardware & Physical Setup

- **Model:** Dell OptiPlex 7070 Small Form Factor (SFF)
- **CPU:** Intel® Core™ i5-8500 (6 Cores / 6 Threads, up to 4.10 GHz, UHD Graphics 630 with QuickSync)
- **RAM:** 8 GB DDR4 (Optimized via `zram` with `zstd` compression yielding ~12–14 GB effective memory pool)
- **Primary Storage:** Samsung 970 Pro 500 GB NVMe SSD (MLC NAND for sustained high write endurance)
- **Networking:** Intel® I219-LM Gigabit Ethernet (1 Gbps)
- **Power Management & Efficiency:**
  - Configured for silent, energy-efficient 24/7 headless operation (~15–25W low power profile).
  - CPU Governor: `powersave` tuned with Intel SpeedShift Energy Performance Preference (`power`).
  - Kernel tuning: `powertop.service` automatically optimizes PCIe link power states upon boot.

---

## 2. Network Topology & Security

```
 WAN / Internet
       │
       ▼
 ┌──────────────┐
 │ Telia Router │ ── DHCP Reservation (Static: 192.168.1.160)
 └──────┬───────┘
        │
        ├─────────────────────────────┬────────────────────────────┐
        ▼                             ▼                            ▼
 ┌──────────────┐              ┌──────────────┐             ┌──────────────┐
 │ Mobile / LAN │              │ Other Hosts  │             │   WireGuard  │
 │ (Subnet /24) │              │  on Subnet   │             │  (51820/udp) │
 └──────┬───────┘              └──────┬───────┘             └──────┬───────┘
        │ Port 53 UDP                 │ Port 53 UDP                │ External Ingress
        └──────────────────────┬──────┴────────────────────────────┘
                               ▼
        ┌──────────────────────────────────────────────────────────┐
        │ Dell OptiPlex 7070 (Debian 12 Bookworm Minimal)          │
        │                                                          │
        │ • UFW Policy: Default DROP Inbound, Docker Fwd ACCEPT    │
        │ • Reject Rule: Port 853/tcp (Forces Android fallback)    │
        │ • SSH Hardened: Port Hardened, Keys Only, Root Denied    │
        ├──────────────────────────────────────────────────────────┤
        │ Local DNS Pipeline (Host Port 53)                        │
        │   └─ AdGuard Home (Sinkhole + Tracker/Malware Filter)    │
        │        ├─ Upstream: Quad9 (DoH / DoT Encrypted)          │
        │        └─ Upstream: Cloudflare (DoH / DoT Encrypted)     │
        └──────────────────────────────────────────────────────────┘
```

- **Host IP (LAN):** `192.168.1.160` (Static DHCP via router)
- **Internal Domain (Planned):** `*.briefnodeops.com` (To be managed via Cloudflare DNS-01 ACME + Caddy reverse proxy)
- **VPN:** WireGuard (`51820/udp`) for encrypted off-site management
- **Host Firewall (UFW):**
  - Inbound allowed: WireGuard (`51820/udp`), DHCP (`67/udp`), DNS (`53/udp/tcp` from `192.168.1.0/24`), SSH (Ed25519 keys only).
  - Forwarding policy: `DEFAULT_FORWARD_POLICY="ACCEPT"` in `/etc/default/ufw` for Docker bridge routing.
  - Android Private DNS Fix: UFW rejects outbound port `853/tcp` to force mobile devices to immediately fall back to the local AdGuard DNS on port 53.
- **SSH Hardening** ([`configs/99-hardened.conf`](configs/99-hardened.conf)):
  - Root login disabled (`PermitRootLogin no`).
  - Password and keyboard-interactive authentication disabled (`PasswordAuthentication no`).
  - Cryptographic standard: Ed25519 public keys only; verified using `sshd -T`.

---

## 3. Storage & Backup Strategy

A strict **3-2-1 Disaster Recovery Policy** is enforced:

1. **Live State:** Running application containers and database volumes in `/opt/stacks/`.
2. **Local Snapshots:** Nightly timestamped `.tar.gz` archives in `/var/backups/stacks/` (7-day local retention).
3. **Offsite Encrypted Copy:** Client-side zero-knowledge encrypted sync via `rclone crypt` (AES-256) targeting Google Drive (`gdrive-crypt:server-backups/`, 14-day retention).

### Automated Backup Script: [`scripts/backup-stacks.sh`](scripts/backup-stacks.sh)
- **ACID Database Consistency:** Enforces SQLite hot snapshots (`sqlite3 <db> ".backup <db>.snap"`) prior to tar archiving, preventing database corruption during active WAL writes.
- **Root Environment Portability:** Explicitly sets `export RCLONE_CONFIG="/home/aidas/.config/rclone/rclone.conf"` to prevent service crashes when running under systemd or sudo.

---

## 4. Systematic Troubleshooting & 5-Layer Triage Hierarchy

When diagnosing any outage, degraded service, or connection failure, move systematically upwards from Layer 1 to Layer 5. Never guess or jump ahead until lower layers are validated.

```text
[Layer 5] Protocol & Application Handshake  ──> curl -iv, dig
      ▲
[Layer 4] Firewall & Network Reachability  ──> sudo ufw status verbose, dmesg UFW BLOCK
      ▲
[Layer 3] Listening Sockets & Binding       ──> sudo ss -tulpn
      ▲
[Layer 2] Process Health & Error Logs       ──> docker ps -a, docker logs, journalctl -u -e
      ▲
[Layer 1] Hardware, Storage & Kernel Health ──> df -h, free -h, dmesg -T (OOM killer)
```

### The 5 Layers in Detail:
1. **Layer 1: Hardware, Disk & Memory (The Silent Killers)**
   - `df -h`: Check if root `/` is at 100%. Full disk breaks locks, crashes SQLite, and fails SSH.
   - `free -h`: Check available RAM and `zram` swap usage.
   - `sudo dmesg -T | grep -i -E "oom|killed process"`: Verify if the Linux OOM Killer terminated a process with `kill -9`.
2. **Layer 2: Process Health & Container Logs**
   - `docker ps -a`: Inspect container status. Look for exit codes:
     - `Exited (0)`: Clean exit.
     - `Exited (1)`: Application crash (syntax error, missing config, wrong DB credentials).
     - `Exited (137)`: Killed by SIGKILL / OOM Killer ($128 + 9 = 137$) due to memory limits.
   - `docker logs --tail 50 <container>`: View dying error output.
   - `sudo journalctl -u <service> -n 50 -e`: View host-level systemd service failures.
3. **Layer 3: Sockets & The "Binding" Trap**
   - `sudo ss -tulpn | grep <port>`: Verify who is listening on the port.
   - **Local Address Check:**
     - `0.0.0.0:<port>` or `*:<port>`: Listening on all interfaces (reachable across LAN/VPN).
     - `127.0.0.1:<port>`: Bound **only to localhost** (unreachable by external devices; returns instant connection refused).
4. **Layer 4: Firewall & Network Reachability**
   - `sudo ufw status verbose`: Check if the destination port is explicitly allowed.
   - `sudo dmesg -T | grep -i "\[UFW BLOCK\]"`: Live verification of packets dropped by the kernel firewall.
5. **Layer 5: Protocol & Application Handshakes**
   - `curl -iv https://<service>`: Verbose protocol inspection (DNS resolution, TCP connection, TLS handshake, HTTP status headers).
   - `dig @127.0.0.1 <domain> +noall +answer`: Direct DNS resolution verification.

---

### Golden Diagnostic Signatures (Instant Root-Cause Identification)

| Symptom / Error | Timing | Underlying Technical Mechanism | Responsible Layer |
| :--- | :--- | :--- | :--- |
| **Connection Refused** | Instant (<1ms) | Kernel actively replied with TCP `RST`. Service is not running or bound to `127.0.0.1`. | Layer 3 (Socket) |
| **Connection Timed Out** | 15–30s delay | Kernel firewall (UFW) silently `DROP`ped the TCP `SYN` packet into a black hole. | Layer 4 (Firewall) |
| **HTTP 502 Bad Gateway** | Instant (<100ms) | Reverse proxy is alive, but the upstream backend container is dead or unreachable. | Layer 2 (Process) |
| **Database Disk Malformed** | On query/boot | SQLite database was copied via `cp`/`tar` during live WAL transactions instead of `.backup`. | Layer 1 (Storage) |

---

### Flag Mnemonics Cheat Sheet (Flags as Words)

- **`ss -tulpn`**:
  - `-t`: **T**CP
  - `-u`: **U**DP
  - `-l`: **L**istening sockets only
  - `-p`: **P**rocess name and PID
  - `-n`: **N**umeric port numbers (avoids slow DNS service name resolution)
- **`tar -czf <archive> <source>`**:
  - `-c`: **C**reate archive
  - `-z`: g**Z**ip compression
  - `-f`: **F**ile name destination
- **`df -h` / `free -h`**:
  - `-h`: **H**uman-readable (GB/MB instead of raw block/byte counts)
- **`docker logs -f --tail 50 <name>`**:
  - `-f`: **F**ollow live output
  - `--tail 50`: Last 50 lines only

---

## 5. Troubleshooting & Incident Log (Post-Mortems)

| Date | Issue / Symptom | Root Cause | Resolution / Prevention |
| :--- | :--- | :--- | :--- |
| *2026-09* | Android phones show "Connected, no internet" on Wi-Fi | Android "Private DNS" queries port `853/tcp` (DoT). UFW dropped packets, causing 15s timeout before falling back. | Added UFW `reject out 853/tcp` rule so phones immediately fall back to local AdGuard port 53. |
| *2026-09* | Live database backup corruption risk | Copying active SQLite `db.sqlite3` during container writes can result in malformed files. | Mandated SQLite `.backup` API execution before archiving. |
| *2026-09-17* | `rclone mkdir` failed with `403 ACCESS_TOKEN_SCOPE_INSUFFICIENT` | Configured scope as `drive.readonly` (read-only), which disallowed directory and file creation on Google Drive. | Updated remote scope to `drive` (full write access) and regenerated OAuth token via `rclone authorize`. |
| *2026-09-18* | `backup-stacks.sh` failed with `rclone.conf not found in /root/.config` | Script executed under `sudo`/root, but `rclone config` was created in `/home/aidas/.config/rclone/rclone.conf`. | Added `export RCLONE_CONFIG="/home/aidas/.config/rclone/rclone.conf"` to the backup script. |
| *2026-09-18* | `sshd -T` reported `passwordauthentication yes` during security audit | `/etc/ssh/sshd_config` had `#PasswordAuthentication yes` commented out, defaulting to Debian default `yes`. | Created `/etc/ssh/sshd_config.d/99-hardened.conf` with explicit `PasswordAuthentication no` and `PermitRootLogin no`, tested via `sshd -t`, and reloaded daemon. |

---

## 6. Repository Structure

```
homelab-ops/
├── README.md                  # Comprehensive architecture, security runbook & post-mortems
├── .gitignore                 # Exclusion for tokens, logs, secrets, and private keys
├── configs/
│   └── 99-hardened.conf       # Hardened SSH drop-in configuration (Ed25519 only)
└── scripts/
    └── backup-stacks.sh       # Automated backup, hot SQLite snapshot, and rclone sync
```

---

## Author

**Aidas Jurkevičius**  
- LinkedIn: [linkedin.com/in/aidas-jurkevicius](https://linkedin.com/in/aidas-jurkevicius)  
- GitHub: [github.com/aidasjurk](https://github.com/aidasjurk)
