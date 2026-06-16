<#
.SYNOPSIS
    Relocate / resize the Windows page file — e.g. move it off a small, nearly-full
    system SSD onto a roomier data drive — to raise the commit ceiling and reduce
    low-memory freezes.

.DESCRIPTION
    Turns off automatic page-file management, sets a small fixed page file on the
    system drive (enough for crash dumps), and creates a larger fixed page file on
    the target drive. A reboot is required for the change to fully apply.

    Useful when a machine throws low-memory / "out of virtual memory" errors while a
    data drive sits half empty. Pair with Get-SystemHealthReport.ps1.

.PARAMETER TargetDrive
    Drive letter (no colon) to host the new page file, e.g. D. Must be a fixed drive
    with free space.

.PARAMETER InitialMB
    Initial size of the target-drive page file in MB. Default 16384 (16 GB).

.PARAMETER MaximumMB
    Maximum size of the target-drive page file in MB. Default 32768 (32 GB).

.PARAMETER SystemInitialMB
    Small page file kept on the system drive (for crash dumps). Default 1024.

.PARAMETER SystemMaximumMB
    Max for the system-drive page file. Default 4096.

.EXAMPLE
    .\Move-PageFile.ps1 -TargetDrive D -WhatIf

.EXAMPLE
    .\Move-PageFile.ps1 -TargetDrive D -InitialMB 16384 -MaximumMB 32768

.NOTES
    Requires an elevated (Administrator) session. Reboot to apply. Sizes are a
    starting point — the real fix for chronic pressure is more physical RAM.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')][string]$TargetDrive,
    [int]$InitialMB = 16384,
    [int]$MaximumMB = 32768,
    [int]$SystemInitialMB = 1024,
    [int]$SystemMaximumMB = 4096
)

# --- admin check ---
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $elevated) { throw "Run this in an elevated (Administrator) PowerShell session." }

$target = "$($TargetDrive.ToUpper()):"
if (-not (Test-Path "$target\")) { throw "Target drive $target not found." }
$sysDrive = $env:SystemDrive   # e.g. C:

# --- turn off automatic management ---
$comp = Get-CimInstance Win32_ComputerSystem
if ($comp.AutomaticManagedPagefile) {
    if ($PSCmdlet.ShouldProcess("Win32_ComputerSystem", "Disable AutomaticManagedPagefile")) {
        Set-CimInstance -InputObject $comp -Property @{ AutomaticManagedPagefile = $false }
    }
}

# --- shrink the system-drive page file ---
$sysPf = Get-CimInstance Win32_PageFileSetting -Filter "Name='$sysDrive\\pagefile.sys'"
if ($sysPf -and $PSCmdlet.ShouldProcess("$sysDrive\pagefile.sys", "Set $SystemInitialMB-$SystemMaximumMB MB")) {
    Set-CimInstance -InputObject $sysPf -Property @{ InitialSize = $SystemInitialMB; MaximumSize = $SystemMaximumMB }
}

# --- create / set the target-drive page file ---
$pfName = "$target\pagefile.sys"
$tgtPf = Get-CimInstance Win32_PageFileSetting -Filter "Name='$target\\pagefile.sys'"
if ($PSCmdlet.ShouldProcess($pfName, "Set $InitialMB-$MaximumMB MB")) {
    if ($tgtPf) {
        Set-CimInstance -InputObject $tgtPf -Property @{ InitialSize = $InitialMB; MaximumSize = $MaximumMB }
    }
    else {
        Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{ Name = $pfName; InitialSize = $InitialMB; MaximumSize = $MaximumMB } | Out-Null
    }
}

Write-Host "`nPage files now configured:" -ForegroundColor Green
Get-CimInstance Win32_PageFileSetting | Format-Table Name, InitialSize, MaximumSize -AutoSize
Write-Host "==> REBOOT to apply." -ForegroundColor Yellow
