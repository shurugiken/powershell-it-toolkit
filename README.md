# powershell-it-toolkit

Practical **PowerShell** for everyday IT support and **Microsoft 365 / Active Directory** administration — the kind of repetitive help-desk tasks worth automating so they're fast, consistent, and documented.

> ⚠️ Sanitized examples (`example.com`, placeholder OUs/groups). Test in a lab or with `-WhatIf` before running against production. Never commit credentials.

## Scripts

| Script | What it does |
|---|---|
| [`New-EmployeeOnboarding.ps1`](scripts/New-EmployeeOnboarding.ps1) | Creates a new user (Microsoft 365 + Entra ID), assigns a license, adds them to groups, and prints a summary for the ticket. |
| [`Disable-DepartedUser.ps1`](scripts/Disable-DepartedUser.ps1) | Offboards a departing user: blocks sign-in, resets the password, revokes sessions, converts the mailbox to shared, and removes licenses. |

## Why
Onboarding and offboarding are the two tasks a help-desk does constantly and where mistakes hurt most (an offboarded user who can still sign in is a security gap). Scripting them makes the process repeatable, auditable, and quick — and the output drops straight into a ticket.

## Requirements
- PowerShell 5.1+ / 7+
- `Microsoft.Graph` module (`Install-Module Microsoft.Graph -Scope CurrentUser`) for the M365 scripts
- Appropriate admin role (User Administrator / Exchange Administrator)

## Run safely
Every script supports `-WhatIf` where it makes changes. Start there:
```powershell
.\scripts\Disable-DepartedUser.ps1 -UserPrincipalName jdoe@example.com -WhatIf
```
