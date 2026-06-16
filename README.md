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
