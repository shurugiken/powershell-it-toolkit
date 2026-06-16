<#
.SYNOPSIS
    Safely reclaim disk space by clearing user temp files and browser caches.

.DESCRIPTION
    Clears the per-user TEMP folder and Chrome/Edge cache directories. These all
    regenerate on demand and clearing them does NOT sign you out (cookies, saved
    passwords, and history live in separate files this never touches). Reports the
    space freed. Locked/in-use files are skipped automatically.

    Supports -WhatIf so you can see what would be cleared before committing.

.EXAMPLE
    .\Clear-WindowsCaches.ps1 -WhatIf

.EXAMPLE
    .\Clear-WindowsCaches.ps1

.NOTES
    Runs as the current user — no admin needed. Close browsers first to clear the
    last bit of cache that's held open.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$targets = @(
    "$env:LOCALAPPDATA\Temp",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
)

$sysDrive = ($env:SystemDrive).TrimEnd(':')
$before = (Get-Volume -DriveLetter $sysDrive).SizeRemaining

foreach ($t in $targets) {
    if (-not (Test-Path $t)) { continue }
    if ($PSCmdlet.ShouldProcess($t, "Clear cache contents")) {
        Get-ChildItem -Path $t -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  cleared: $t"
    }
}

if (-not $WhatIfPreference) {
    $after = (Get-Volume -DriveLetter $sysDrive).SizeRemaining
    "`nFreed: {0:N0} MB   |   {1}: {2:N1} GB free" -f (($after - $before) / 1MB), $env:SystemDrive, ($after / 1GB)
}
