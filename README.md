# powershell-it-toolkit

Practical **PowerShell** for everyday IT support and **Microsoft 365 / Active Directory** administration — the kind of repetitive help-desk tasks worth automating so they're fast, consistent, and documented.

> ⚠️ Sanitized examples (`example.com`, placeholder OUs/groups). Test in a lab or with `-WhatIf` before running against production. Never commit credentials.

## Scripts

| Script | What it does |
|---|---|
| [`New-EmployeeOnboarding.ps1`](scripts/New-EmployeeOnboarding.ps1) | Creates a new user (Microsoft 365 + Entra ID), assigns a license, adds them to groups, and prints a summary for the ticket. |
| [`Disable-DepartedUser.ps1`](scripts/Disable-DepartedUser.ps1) | Offboards a departing user: blocks sign-in, resets the password, revokes sessions, converts the mailbox to shared, and removes licenses. |
| [`Get-SystemHealthReport.ps1`](scripts/Get-SystemHealthReport.ps1) | Triages a slow / freezing / out-of-space PC: memory-commit pressure, SMART disk health, volume space, page file, top consumers, and an event-log scan **filtered by source** — then prints a verdict. Read-only. |
| [`Move-PageFile.ps1`](scripts/Move-PageFile.ps1) | Relocates/resizes the page file (e.g. off a full system SSD onto a data drive) to raise the commit ceiling and stop low-memory freezes. `-WhatIf` supported. |
| [`Clear-WindowsCaches.ps1`](scripts/Clear-WindowsCaches.ps1) | Safely reclaims disk space (user temp + browser caches; no sign-outs). Reports space freed. `-WhatIf` supported. |

## Why
Onboarding and offboarding are the two tasks a help-desk does constantly and where mistakes hurt most (an offboarded user who can still sign in is a security gap). Scripting them makes the process repeatable, auditable, and quick — and the output drops straight into a ticket.

The diagnostics scripts solve the other recurring ticket — "my computer is slow / freezes" — with evidence instead of guesses. One detail worth calling out: `Get-SystemHealthReport.ps1` scans the event log by **source**, not by ID alone, because many benign events share an ID with serious ones (ID 55 is "NTFS corruption" from the *Ntfs* source but "processor power capabilities" from *Kernel-Processor-Power*). ID-only filtering can turn a perfectly healthy machine into a fake "132 disk corruptions" — filtering by source avoids that false alarm and points you at the real cause (usually memory pressure, not the disk).

## Requirements
- PowerShell 5.1+ / 7+
- `Microsoft.Graph` module (`Install-Module Microsoft.Graph -Scope CurrentUser`) for the M365 scripts
- Appropriate admin role (User Administrator / Exchange Administrator) for the M365 scripts
- The diagnostics scripts need **no extra modules**; `Move-PageFile.ps1` requires an elevated session, the other two run as a standard user

## Run safely
Every script supports `-WhatIf` where it makes changes. Start there:
```powershell
.\scripts\Disable-DepartedUser.ps1 -UserPrincipalName jdoe@example.com -WhatIf
```

## Example output

All samples below are **illustrative** — generated from realistic values to show the format the scripts actually produce. Real output reflects the machine or tenant it runs against.

---

### `Get-SystemHealthReport.ps1` (illustrative)

```
===== MEMORY =====
Total RAM:            16.0 GB
Free RAM:              2.3 GB
RAM in use:            86 %
Commit charge:        18.4 / 24.0 GB  (77% of commit limit)

===== RAM MODULES / SLOTS =====
  DIMM-A1         8 GB  3200 MT/s  CT8G4DFS832A
  DIMM-B1         8 GB  3200 MT/s  CT8G4DFS832A
  Slots: 2 populated / 4 total   Max supported: 64 GB
  -> 2 free slot(s): RAM is upgradeable without removing existing sticks.

===== PHYSICAL DISKS (health) =====
  Samsung SSD 870 EVO 500GB    SSD   Health=Healthy  465 GB  bus=SATA
  WDC WD10EZEX-08WN4A0         HDD   Health=Healthy  931 GB  bus=SATA

===== VOLUMES (free space) =====
  C:     11.4 GB free /   465.0 GB  ( 2.5% free)  ! low
  D:    412.7 GB free /   931.4 GB  (44.3% free)

===== PAGE FILE =====
  C:\pagefile.sys  allocated= 7.9 GB  peak= 5.2 GB  current= 4.1 GB

===== TOP RAM CONSUMERS =====
  chrome                        1 842 MB
  MsMpEng                         412 MB
  Code                            389 MB
  SearchIndexer                   201 MB
  svchost                         177 MB
  explorer                        134 MB
  ...

===== EVENT-LOG ISSUES (last 30 days, filtered by source) =====
      0  Low-memory (Resource-Exhaustion 2004)
      0  Hard freezes / dirty shutdowns (Kernel-Power 41)
      0  Bugchecks / BSOD
      2  Real disk / NTFS errors (by source)
      3  App crashes (1000)       0  App hangs (1002)

===== VERDICT =====
  * No single dominant issue detected in this window.
```

> The `C:` volume flagged `! low` because it is below 15% free. No memory-pressure events were found, so the VERDICT stays clean — this is a space problem, not a RAM problem.

---

### `New-EmployeeOnboarding.ps1` (illustrative)

```powershell
.\scripts\New-EmployeeOnboarding.ps1 `
    -DisplayName "Jane Doe" `
    -UserPrincipalName jdoe@example.com `
    -Department "Accounting" `
    -JobTitle "Staff Accountant" `
    -Groups "Accounting","All-Staff"
```

```
--- Onboarding summary (paste into the ticket) ---

Name         : Jane Doe
UPN          : jdoe@example.com
Department   : Accounting
Title        : Staff Accountant
License      : ENTERPRISEPACK
Groups       : Accounting, All-Staff
TempPassword : rK7mNq3BvXpL2w
MustReset    : True
```

The `Format-List` block is designed to be copied directly into the help-desk ticket so there is a clean audit record of exactly what was provisioned.

---

### `Clear-WindowsCaches.ps1` (illustrative)

```
  cleared: C:\Users\jdoe\AppData\Local\Temp
  cleared: C:\Users\jdoe\AppData\Local\Google\Chrome\User Data\Default\Cache
  cleared: C:\Users\jdoe\AppData\Local\Google\Chrome\User Data\Default\Code Cache
  cleared: C:\Users\jdoe\AppData\Local\Microsoft\Edge\User Data\Default\Cache

Freed: 3 241 MB   |   C:: 14.6 GB free
```

Locked files (held open by a running browser) are skipped silently — close Chrome and Edge first to maximise the reclaim.
