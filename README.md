# Healthcare IT Support Lab — VMware Workstation Edition

A self-contained, HIPAA-aligned clinic IT environment built from scratch on
VMware Workstation: Active Directory, Group Policy security controls,
role-based file access, and a self-hosted ITSM ticketing system with
ITIL-aligned incident SLAs.

Built as a hands-on lab to practice the kind of infrastructure a small
healthcare organization's IT support role would actually own — domain
services, endpoint security policy, access control, and incident
management — end to end, including the real troubleshooting that came up
along the way.

---

## Architecture

| Virtual Machine | OS | Role | Network |
|---|---|---|---|
| `DC-CLINIC-01` | Windows Server 2019 Standard | AD DS, DHCP, DNS, file share, XAMPP/osTicket | VMnet2 (Custom LAN Segment), static `192.168.100.10/24` |
| `CLIN-WS-01` | Windows 10 Pro (64-bit) | Domain-joined clinical workstation | VMnet2, DHCP (`192.168.100.100`–`.200`) |

The lab network is fully isolated (host-only / LAN Segment) — no outbound
internet access by design. That constraint turned out to matter (see
[Troubleshooting Log](#troubleshooting-log) below).

**Domain:** `stjude-clinic.local`

```
stjude-clinic.local
└── Healthcare_Clinic (OU)
    ├── Clinical_Staff (OU)
    │   ├── Doctors (OU)      → dr.mahmoud
    │   └── Nurses (OU)       → nurse.ola
    ├── Administrative (OU)   → admin.ahmed
    └── Workstations (OU)     → CLIN-WS-01

Security Groups:
    SG_Clinical_Users     → dr.mahmoud, nurse.ola
    SG_PHI_Access_Read    → dr.mahmoud, nurse.ola
    SG_Admin_Users        → admin.ahmed
```

---

## What's in this repo

```
├── scripts/
│   ├── Deploy-ClinicAD.ps1        # OUs, security groups, users, group memberships
│   └── Setup-PatientShare.ps1     # Restricted PatientRecords$ file share (RBAC)
└── README.md
```

The Group Policy configuration (screen-lock timeout, removable-storage
blocking) and the osTicket install are GUI/web-driven and documented below
rather than scripted, since they don't have a clean CLI-only path in this
build.

---

## Build steps

### 1. VMware network
Custom LAN Segment (`VMnet2`), Host-Only, subnet `192.168.100.0/24`, no
VMware-managed DHCP (Windows Server handles that instead).

### 2. Domain controller
- Windows Server 2019 Standard (Desktop Experience), static IP `192.168.100.10`
- AD DS role installed → promoted to a new forest, `stjude-clinic.local`
- DHCP role installed → scope `192.168.100.100`–`.200`, Option 006 (DNS) → `192.168.100.10`

### 3. Active Directory provisioning
```powershell
.\scripts\Deploy-ClinicAD.ps1
```
Creates the full OU tree, three security groups, three clinic user
accounts, and wires up group memberships in one pass.

### 4. HIPAA-aligned Group Policy
GPO `GPO_HIPAA_Workstation_Security`, linked to the `Workstations` OU:
- **Screen lock:** Enable Screen Saver + Password Protect, 300-second timeout
- **Removable media:** Deny read *and* write access to removable disks
  (both directions matter — read-only blocking still allows exfiltration
  via the write side, and vice versa)

### 5. Restricted patient records share
```powershell
.\scripts\Setup-PatientShare.ps1
```
Creates `C:\Shares\PatientRecords`, shares it as the hidden share
`PatientRecords$`, and locks down both share-level and NTFS-level
permissions to `SG_PHI_Access_Read` only. Windows enforces the more
restrictive of the two layers on network access, so both had to be
addressed — fixing only one leaves the share effectively open.

### 6. Domain join & RBAC verification
`CLIN-WS-01` joined to `stjude-clinic.local`, moved into the
`Workstations` OU (so the GPO link actually applies — computer objects
land in the default `Computers` container on join, not the OU you want).

**Verified:**
| Logon | Access to `\\192.168.100.10\PatientRecords$` |
|---|---|
| `stjude-clinic\dr.mahmoud` | ✅ Success |
| `stjude-clinic\admin.ahmed` | ❌ Access denied (expected — confirms RBAC works) |

### 7. ITSM ticketing (osTicket on XAMPP)
- XAMPP (Apache + MySQL + PHP), osTicket deployed to `htdocs/osticket`
- Three SLA plans created and mapped to Help Topics by ITIL-style priority:

| Priority | Scenario | SLA Target |
|---|---|---|
| P1 – Emergency | EHR/system outage | 2 hours |
| P2 – High | Workstation/hardware failure | 8 hours |
| P3 – Normal | Access/onboarding request | 24 hours |

---

## Troubleshooting Log

Documenting these because the debugging mattered as much as the build
itself — these are the kind of issues that show up in a real deployment,
not just a lab.

<details>
<summary><strong>1. <code>scp</code> admin login → "Error: Contact system admin."</strong></summary>

**Cause:** `ost-config.php` was still the unfilled installer template —
`OSTINSTALLED` was `FALSE` and DB fields held `%CONFIG-*` placeholder
tokens. Since the `setup/` folder had already been renamed for security,
osTicket couldn't redirect to the installer and hit its hard fallback
error instead.

**Fix:** Restored `setup/`, replaced `ost-config.php` with a clean copy
of the sample config, confirmed it was writable, re-ran the install
wizard to completion.
</details>

<details>
<summary><strong>2. Installer crashed with HTTP 500</strong></summary>

**Cause:** Apache error log showed an uncaught `mysqli_sql_exception`:
`Access denied for user 'root'@'localhost' (using password: YES)`. The
installer was given a password for MySQL root, but XAMPP's bundled MySQL
ships with **no** root password by default — nothing to match against.

**Fix:** Reset MySQL root's password via
`mysqladmin -u root password "..."` to match what the installer expected,
dropped/recreated the partially-written database, re-ran the installer.
Confirmed successful via `OSTINSTALLED` flipping to `TRUE` and the
`%CONFIG-*` tokens being replaced with real values.
</details>

<details>
<summary><strong>3. phpMyAdmin → "Access denied ... (using password: NO)"</strong></summary>

**Cause:** After fixing #2, phpMyAdmin's own `config.inc.php` still had
the original blank-password default and hadn't been updated to match the
new root password.

**Fix:** Updated `$cfg['Servers'][$i]['password']` in `config.inc.php` to
match.
</details>

<details>
<summary><strong>4. "Issue Details is a required field" despite text being entered</strong></summary>

**Cause:** Confirmed via browser DevTools console that the ticket
description's rich-text editor failed to load — its JS assets are
pulled from an external CDN, and this lab's network is intentionally
isolated with no outbound internet access. The field visually accepted
typed text, but the hidden form field the editor writes to never
populated, so osTicket correctly flagged it as empty on submit.

**Fix:** Confirmed as a CDN-availability issue tied to the lab's offline
network design, not a config or permissions problem. For a permanent fix
in an offline environment: host the editor's JS/CSS assets locally
within the osTicket install rather than referencing a CDN, or grant the
VM outbound access to the specific CDN domain.
</details>

---

## Hardening for real use

This is a lab build — a few shortcuts here would need to change before
this pattern went anywhere near production:

- Passwords are hardcoded in the scripts for repeatability; in practice,
  prompt for credentials (`Read-Host -AsSecureString`) or pull from a
  secrets store instead.
- `Deploy-ClinicAD.ps1` isn't idempotent — re-running it against an
  already-provisioned domain will throw "already exists" errors. Fine
  for a rebuild-from-scratch lab; a production version should check for
  existing objects first (`Get-ADUser -Filter ...`) before creating them.
- phpMyAdmin's `config.inc.php` stores the DB password in plaintext under
  `auth_type = config`; switching to `auth_type = cookie` avoids that at
  the cost of a login prompt on each visit.

---
## Screenshots

   ![RBAC test - access granted](screenshots/rbac-success.png)
   ![RBAC test - access denied](screenshots/rbac-denied.png)
---

## Skills demonstrated

Active Directory Domain Services · Group Policy Management · PowerShell
automation · Role-Based Access Control (RBAC) · NTFS & share permissions ·
HIPAA-aligned security controls · VMware Workstation networking · DHCP/DNS ·
ITSM/ITIL incident management · MySQL/Apache/PHP troubleshooting · root-cause
debugging via log analysis
