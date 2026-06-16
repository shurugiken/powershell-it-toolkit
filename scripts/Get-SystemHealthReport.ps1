<#
.SYNOPSIS
    One-shot Windows health report for triaging "my PC is slow / freezes / runs
    out of space" tickets — without guessing.

.DESCRIPTION
    Surfaces the signals that actually explain slowdowns, freezes, and crashes:
    memory-commit pressure, physical disk (SMART) health, volume free space, the
    page file, the top resource consumers, and a focused scan of the event log.

    It separates the two most common root causes — memory-commit exhaustion vs. a
    failing/near-full disk — using hard evidence (commit charge vs. limit, SMART
    HealthStatus, Resource-Exhaustion events) instead of vibes, and prints a short
    verdict at the end.

    Event-log gotcha this handles: it filters by event SOURCE (ProviderName), NOT
    by ID alone. Many benign events share an ID with serious ones — e.g. ID 55 is
    "NTFS corruption" from the *Ntfs* source but "processor power capabilities" from
    *Kernel-Processor-Power* (which fires once per CPU core every boot). Naive
    ID-only filtering can turn a healthy machine into a fake "132 disk corruptions."
    Filtering by source avoids that false alarm.

.PARAMETER Days
    Days of event-log history to scan. Default 30.

.EXAMPLE
    .\Get-SystemHealthReport.ps1

.EXAMPLE
    .\Get-SystemHealthReport.ps1 -Days 7

.NOTES
    Read-only. A few reliability counters need an elevated session; the script runs
    fine without admin and simply notes anything it couldn't read.
#>
[CmdletBinding()]
param([int]$Days = 30)

function Write-Head($t) { Write-Host "`n===== $t =====" -ForegroundColor Cyan }

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

# ---- memory ----
Write-Head "MEMORY"
$totalGB = $cs.TotalPhysicalMemory / 1GB
$freeGB  = $os.FreePhysicalMemory / 1MB
$usedPct = (($cs.TotalPhysicalMemory / 1KB) - $os.FreePhysicalMemory) / ($cs.TotalPhysicalMemory / 1KB) * 100
$commitUsedGB = ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB
$commitLimitGB = $os.TotalVirtualMemorySize / 1MB
$commitPct = $commitUsedGB / $commitLimitGB * 100
"{0,-22}{1:N1} GB" -f "Total RAM:", $totalGB
"{0,-22}{1:N1} GB" -f "Free RAM:", $freeGB
"{0,-22}{1:N0} %" -f "RAM in use:", $usedPct
"{0,-22}{1:N1} / {2:N1} GB  ({3:N0}% of commit limit)" -f "Commit charge:", $commitUsedGB, $commitLimitGB, $commitPct
if ($commitPct -ge 90) { Write-Host "  ! Commit charge is near the limit — this is the classic cause of low-memory freezes." -ForegroundColor Yellow }

# ---- RAM modules / upgrade headroom ----
Write-Head "RAM MODULES / SLOTS"
Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    "  {0,-12} {1,5:N0} GB  {2} MT/s  {3}" -f $_.DeviceLocator, ($_.Capacity / 1GB), $_.Speed, $_.PartNumber
}
$arr = Get-CimInstance Win32_PhysicalMemoryArray
$maxGB = if ($arr.MaxCapacityEx) { $arr.MaxCapacityEx / 1MB } else { $arr.MaxCapacity / 1MB }
$used = (Get-CimInstance Win32_PhysicalMemory | Measure-Object).Count
"  Slots: {0} populated / {1} total   Max supported: {2:N0} GB" -f $used, $arr.MemoryDevices, $maxGB
if ($used -lt $arr.MemoryDevices) { Write-Host "  -> $($arr.MemoryDevices - $used) free slot(s): RAM is upgradeable without removing existing sticks." -ForegroundColor Green }

# ---- disks (SMART) ----
Write-Head "PHYSICAL DISKS (health)"
$diskWarn = $false
Get-PhysicalDisk | ForEach-Object {
    if ($_.HealthStatus -ne 'Healthy') { $diskWarn = $true }
    "  {0,-32} {1,-5} Health={2}  {3:N0} GB  bus={4}" -f $_.FriendlyName, $_.MediaType, $_.HealthStatus, ($_.Size / 1GB), $_.BusType
}

# ---- volumes ----
Write-Head "VOLUMES (free space)"
Get-Volume | Where-Object DriveLetter | Sort-Object DriveLetter | ForEach-Object {
    $pct = $_.SizeRemaining / $_.Size * 100
    $line = "  {0}:  {1,7:N1} GB free / {2,7:N1} GB  ({3,4:N1}% free)" -f $_.DriveLetter, ($_.SizeRemaining / 1GB), ($_.Size / 1GB), $pct
    if ($pct -lt 15) { Write-Host "$line  ! low" -ForegroundColor Yellow } else { $line }
}

# ---- page file ----
Write-Head "PAGE FILE"
Get-CimInstance Win32_PageFileUsage | ForEach-Object {
    "  {0}  allocated={1:N1} GB  peak={2:N1} GB  current={3:N1} GB" -f $_.Name, ($_.AllocatedBaseSize / 1024), ($_.PeakUsage / 1024), ($_.CurrentUsage / 1024)
}

# ---- top consumers ----
Write-Head "TOP RAM CONSUMERS"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
    ForEach-Object { "  {0,-28} {1,6:N0} MB" -f $_.Name, ($_.WorkingSet64 / 1MB) }

# ---- event-log scan (BY SOURCE, not just ID) ----
Write-Head "EVENT-LOG ISSUES (last $Days days, filtered by source)"
$since = (Get-Date).AddDays(-$Days)
$sys = Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue
$app = Get-WinEvent -FilterHashtable @{LogName = 'Application'; StartTime = $since } -ErrorAction SilentlyContinue

$lowMem = @($sys | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Resource-Exhaustion-Detector' -and $_.Id -eq 2004 })
$freeze = @($sys | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41 })
$bsod   = @($sys | Where-Object { $_.ProviderName -match 'BugCheck|WER-SystemErrorReporting' -and $_.Id -eq 1001 })
$disk   = @($sys | Where-Object { $_.LevelDisplayName -in 'Error', 'Warning', 'Critical' -and $_.ProviderName -match 'disk|ntfs|storahci|stornvme|volmgr|volsnap|storport' })
$crash  = @($app | Where-Object { $_.Id -eq 1000 })
$hang   = @($app | Where-Object { $_.Id -eq 1002 })

"  {0,5}  Low-memory (Resource-Exhaustion 2004)" -f $lowMem.Count
"  {0,5}  Hard freezes / dirty shutdowns (Kernel-Power 41)" -f $freeze.Count
"  {0,5}  Bugchecks / BSOD" -f $bsod.Count
"  {0,5}  Real disk / NTFS errors (by source)" -f $disk.Count
"  {0,5}  App crashes (1000)   {1,5}  App hangs (1002)" -f $crash.Count, $hang.Count

if ($lowMem.Count) {
    Write-Host "`n  Programs named in the most recent low-memory event:" -ForegroundColor DarkGray
    ($lowMem[0].Message -replace '\s+', ' ') -replace '^.*programs consumed[^:]*:\s*', '  ' | ForEach-Object { $_.Substring(0, [Math]::Min(220, $_.Length)) }
}

# ---- verdict ----
Write-Head "VERDICT"
$verdict = @()
if ($commitPct -ge 90 -or $lowMem.Count -ge 10) { $verdict += "MEMORY PRESSURE — commit charge is maxing out (add RAM and/or enlarge the page file; see Move-PageFile.ps1)." }
if ($diskWarn -or $disk.Count -ge 10) { $verdict += "DISK ATTENTION — SMART not healthy or repeated disk/NTFS errors (back up and check the drive)." }
if (-not $verdict) { $verdict += "No single dominant issue detected in this window." }
$verdict | ForEach-Object { Write-Host "  * $_" -ForegroundColor White }
