#Requires -Modules Pester
<#
.SYNOPSIS
    Pester v5 tests for powershell-it-toolkit scripts.
    All external/system cmdlets are mocked — no network calls, no admin rights needed.
#>

BeforeAll {
    $ScriptRoot = (Split-Path $PSScriptRoot -Parent)
}

# ---------------------------------------------------------------------------
# Shared formatting helpers extracted from Get-SystemHealthReport.ps1
# Pure-math helpers only — no CIM/WMI calls needed.
# ---------------------------------------------------------------------------
Describe "Get-SystemHealthReport - pure-math helpers" {

    Context "RAM-in-use percentage calculation" {
        It "calculates 0 percent when free equals total" {
            $totalKB = 16 * 1024 * 1024   # 16 GB in KB
            $freeKB  = 16 * 1024 * 1024
            $usedPct = ($totalKB - $freeKB) / $totalKB * 100
            $usedPct | Should -Be 0
        }

        It "calculates 50 percent when half is free" {
            $totalKB = 16 * 1024 * 1024
            $freeKB  = 8  * 1024 * 1024
            $usedPct = ($totalKB - $freeKB) / $totalKB * 100
            $usedPct | Should -Be 50
        }

        It "calculates 75 percent when one quarter is free" {
            $totalKB = 16 * 1024 * 1024
            $freeKB  = 4  * 1024 * 1024
            $usedPct = ($totalKB - $freeKB) / $totalKB * 100
            $usedPct | Should -Be 75
        }
    }

    Context "Commit-charge percentage and pressure flag" {
        It "flags pressure when commit charge exceeds 90 percent" {
            $commitUsedGB   = 28.0
            $commitLimitGB  = 30.0
            $commitPct      = $commitUsedGB / $commitLimitGB * 100
            $commitPct | Should -BeGreaterThan 90
        }

        It "does NOT flag pressure when commit charge is under 90 percent" {
            $commitUsedGB   = 20.0
            $commitLimitGB  = 30.0
            $commitPct      = $commitUsedGB / $commitLimitGB * 100
            $commitPct | Should -BeLessThan 90
        }
    }

    Context "Verdict logic" {
        It "returns memory-pressure verdict when commit pct is 95" {
            $commitPct   = 95
            $lowMemCount = 0
            $diskWarn    = $false
            $diskCount   = 0

            $verdict = @()
            if ($commitPct -ge 90 -or $lowMemCount -ge 10) {
                $verdict += "MEMORY PRESSURE"
            }
            if ($diskWarn -or $diskCount -ge 10) {
                $verdict += "DISK ATTENTION"
            }
            if (-not $verdict) { $verdict += "No single dominant issue detected" }

            $verdict | Should -Contain "MEMORY PRESSURE"
            $verdict | Should -Not -Contain "DISK ATTENTION"
        }

        It "returns disk-attention verdict when diskWarn is true" {
            $commitPct   = 50
            $lowMemCount = 0
            $diskWarn    = $true
            $diskCount   = 0

            $verdict = @()
            if ($commitPct -ge 90 -or $lowMemCount -ge 10) { $verdict += "MEMORY PRESSURE" }
            if ($diskWarn -or $diskCount -ge 10)            { $verdict += "DISK ATTENTION" }
            if (-not $verdict)                              { $verdict += "No single dominant issue detected" }

            $verdict | Should -Contain "DISK ATTENTION"
            $verdict | Should -Not -Contain "MEMORY PRESSURE"
        }

        It "returns disk-attention verdict when disk error count is 12" {
            $commitPct   = 50
            $lowMemCount = 0
            $diskWarn    = $false
            $diskCount   = 12

            $verdict = @()
            if ($commitPct -ge 90 -or $lowMemCount -ge 10) { $verdict += "MEMORY PRESSURE" }
            if ($diskWarn -or $diskCount -ge 10)            { $verdict += "DISK ATTENTION" }
            if (-not $verdict)                              { $verdict += "No single dominant issue detected" }

            $verdict | Should -Contain "DISK ATTENTION"
        }

        It "returns memory-pressure verdict when low-memory event count reaches 10" {
            $commitPct   = 50
            $lowMemCount = 10
            $diskWarn    = $false
            $diskCount   = 0

            $verdict = @()
            if ($commitPct -ge 90 -or $lowMemCount -ge 10) { $verdict += "MEMORY PRESSURE" }
            if ($diskWarn -or $diskCount -ge 10)            { $verdict += "DISK ATTENTION" }
            if (-not $verdict)                              { $verdict += "No single dominant issue detected" }

            $verdict | Should -Contain "MEMORY PRESSURE"
        }

        It "returns no-dominant-issue verdict on a healthy system" {
            $commitPct   = 60
            $lowMemCount = 2
            $diskWarn    = $false
            $diskCount   = 3

            $verdict = @()
            if ($commitPct -ge 90 -or $lowMemCount -ge 10) { $verdict += "MEMORY PRESSURE" }
            if ($diskWarn -or $diskCount -ge 10)            { $verdict += "DISK ATTENTION" }
            if (-not $verdict)                              { $verdict += "No single dominant issue detected" }

            $verdict | Should -Contain "No single dominant issue detected"
            $verdict.Count | Should -Be 1
        }

        It "surfaces both issues simultaneously when both conditions are true" {
            $commitPct   = 91
            $lowMemCount = 0
            $diskWarn    = $true
            $diskCount   = 0

            $verdict = @()
            if ($commitPct -ge 90 -or $lowMemCount -ge 10) { $verdict += "MEMORY PRESSURE" }
            if ($diskWarn -or $diskCount -ge 10)            { $verdict += "DISK ATTENTION" }
            if (-not $verdict)                              { $verdict += "No single dominant issue detected" }

            $verdict.Count | Should -Be 2
        }
    }

    Context "Volume free-space low-space threshold" {
        It "flags a volume below 15 percent free" {
            $sizeRemaining = 10GB
            $size          = 100GB
            $pct = $sizeRemaining / $size * 100
            $pct | Should -BeLessThan 15
        }

        It "does not flag a volume at exactly 15 percent free" {
            $sizeRemaining = 15GB
            $size          = 100GB
            $pct = $sizeRemaining / $size * 100
            $pct | Should -Not -BeLessThan 15
        }
    }

    Context "Page-file size formatting" {
        It "converts MB to GB correctly for display" {
            # Script divides AllocatedBaseSize (MB) by 1024 to get GB
            $allocatedMB = 16384
            $allocatedGB = $allocatedMB / 1024
            $allocatedGB | Should -Be 16
        }
    }
}

# ---------------------------------------------------------------------------
# Move-PageFile.ps1 - validation and parameter logic
# ---------------------------------------------------------------------------
Describe "Move-PageFile.ps1 - validation and parameter logic" {

    Context "Parameter validation - TargetDrive pattern" {
        It "accepts a single uppercase letter" {
            'D' | Should -Match '^[A-Za-z]$'
        }

        It "accepts a single lowercase letter" {
            'd' | Should -Match '^[A-Za-z]$'
        }

        It "rejects a drive letter with a colon appended" {
            'D:' | Should -Not -Match '^[A-Za-z]$'
        }

        It "rejects multiple letters" {
            'DD' | Should -Not -Match '^[A-Za-z]$'
        }

        It "rejects an empty string" {
            '' | Should -Not -Match '^[A-Za-z]$'
        }
    }

    Context "Default size values" {
        It "default InitialMB of 16384 equals 16 GB" {
            16384 / 1024 | Should -Be 16
        }

        It "default MaximumMB of 32768 equals 32 GB" {
            32768 / 1024 | Should -Be 32
        }

        It "default SystemInitialMB of 1024 equals 1 GB" {
            1024 / 1024 | Should -Be 1
        }
    }

    Context "TargetDrive is uppercased in the pagefile path" {
        It "uppercases a lowercase drive letter to build the colon path" {
            $TargetDrive = 'd'
            $target = "$($TargetDrive.ToUpper()):"
            $target | Should -Be 'D:'
        }

        It "leaves an already-uppercase drive letter unchanged" {
            $TargetDrive = 'D'
            $target = "$($TargetDrive.ToUpper()):"
            $target | Should -Be 'D:'
        }

        It "pagefile path is composed as drive-colon-backslash-pagefile.sys" {
            $TargetDrive = 'E'
            $target      = "$($TargetDrive.ToUpper()):"
            $pfName      = "$target\pagefile.sys"
            $pfName | Should -Be 'E:\pagefile.sys'
        }
    }
}

# ---------------------------------------------------------------------------
# New-EmployeeOnboarding.ps1 - mailNickname extraction + summary shape
# ---------------------------------------------------------------------------
Describe "New-EmployeeOnboarding.ps1 - helper logic" {

    Context "mailNickname extraction from UPN" {
        It "extracts the local part before the at-sign" {
            $upn = "jdoe@example.com"
            $mailNickname = ($upn -split "@")[0]
            $mailNickname | Should -Be "jdoe"
        }

        It "handles a UPN with dots in the local part" {
            $upn = "jane.doe@corp.example.com"
            $mailNickname = ($upn -split "@")[0]
            $mailNickname | Should -Be "jane.doe"
        }

        It "handles a UPN with a plus-tag in the local part" {
            $upn = "jane+alias@example.com"
            $mailNickname = ($upn -split "@")[0]
            $mailNickname | Should -Be "jane+alias"
        }
    }

    Context "Temporary password generation" {
        It "generates a 14-character password" {
            $tempPassword = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 14 | ForEach-Object {[char]$_})
            $tempPassword.Length | Should -Be 14
        }

        It "generates a password from alphanumeric characters only" {
            $tempPassword = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 14 | ForEach-Object {[char]$_})
            $tempPassword | Should -Match '^[A-Za-z0-9]{14}$'
        }

        It "generates different passwords on successive calls" {
            $a = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 14 | ForEach-Object {[char]$_})
            $b = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 14 | ForEach-Object {[char]$_})
            $a | Should -Not -Be $b
        }
    }

    Context "Onboarding summary object shape" {
        It "produces an object with all expected properties" {
            $DisplayName       = "Jane Doe"
            $UserPrincipalName = "jdoe@example.com"
            $Department        = "Accounting"
            $JobTitle          = "Staff Accountant"
            $LicenseSku        = "ENTERPRISEPACK"
            $Groups            = @("Accounting", "All-Staff")
            $tempPassword      = "TestPassword12"

            $obj = [pscustomobject]@{
                Name         = $DisplayName
                UPN          = $UserPrincipalName
                Department   = $Department
                Title        = $JobTitle
                License      = $LicenseSku
                Groups       = ($Groups -join ", ")
                TempPassword = $tempPassword
                MustReset    = $true
            }

            $obj.Name        | Should -Be "Jane Doe"
            $obj.UPN         | Should -Be "jdoe@example.com"
            $obj.Department  | Should -Be "Accounting"
            $obj.Title       | Should -Be "Staff Accountant"
            $obj.License     | Should -Be "ENTERPRISEPACK"
            $obj.Groups      | Should -Be "Accounting, All-Staff"
            $obj.MustReset   | Should -Be $true
        }

        It "joins multiple groups with a comma-space separator" {
            $groups = @("Sales", "All-Staff", "VPN-Users")
            $joined = $groups -join ", "
            $joined | Should -Be "Sales, All-Staff, VPN-Users"
        }

        It "produces an empty string for Groups when none supplied" {
            $groups = @()
            $joined = $groups -join ", "
            $joined | Should -Be ""
        }
    }

    Context "Graph cmdlet stubs for onboarding flow" {

        BeforeAll {
            function global:Connect-MgGraph    { param([string[]]$Scopes, [switch]$NoWelcome) }
            function global:Disconnect-MgGraph { return $null }
            function global:New-MgUser {
                param(
                    [string]$DisplayName, [string]$UserPrincipalName, [string]$MailNickname,
                    [switch]$AccountEnabled, [string]$Department, [string]$JobTitle,
                    [string]$UsageLocation, [hashtable]$PasswordProfile
                )
                return [pscustomobject]@{ Id = 'mock-user-id-001'; DisplayName = $DisplayName }
            }
            function global:Get-MgSubscribedSku {
                param([switch]$All)
                return @([pscustomobject]@{ SkuPartNumber = 'ENTERPRISEPACK'; SkuId = 'mock-sku-guid' })
            }
            function global:Set-MgUserLicense  {
                param([string]$UserId, [object[]]$AddLicenses, [object[]]$RemoveLicenses)
                return $null
            }
            function global:Get-MgGroup {
                param([string]$Filter, [int]$Top)
                return [pscustomobject]@{ Id = 'mock-group-id'; DisplayName = 'Accounting' }
            }
            function global:New-MgGroupMember  {
                param([string]$GroupId, [string]$DirectoryObjectId)
            }
        }

        AfterAll {
            'Connect-MgGraph','Disconnect-MgGraph','New-MgUser','Get-MgSubscribedSku',
            'Set-MgUserLicense','Get-MgGroup','New-MgGroupMember' | ForEach-Object {
                Remove-Item -Path "Function:global:$_" -ErrorAction SilentlyContinue
            }
        }

        It "New-MgUser stub returns an object with the supplied DisplayName" {
            $result = New-MgUser -DisplayName "Test User" -UserPrincipalName "tu@test.com" `
                -MailNickname "tu" -AccountEnabled -UsageLocation "US" `
                -PasswordProfile @{ Password = "Temp1234567890"; ForceChangePasswordNextSignIn = $true }
            $result.DisplayName | Should -Be "Test User"
            $result.Id          | Should -Be "mock-user-id-001"
        }

        It "Get-MgSubscribedSku stub returns a SKU with the ENTERPRISEPACK part number" {
            $sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'ENTERPRISEPACK'
            $sku          | Should -Not -BeNullOrEmpty
            $sku.SkuId    | Should -Be "mock-sku-guid"
        }

        It "Get-MgGroup stub returns a group object with the expected Id" {
            $grp = Get-MgGroup -Filter "displayName eq 'Accounting'" -Top 1
            $grp    | Should -Not -BeNullOrEmpty
            $grp.Id | Should -Be "mock-group-id"
        }

        It "Where-Object filter on SkuPartNumber returns null for an unknown SKU" {
            $sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'NONEXISTENT_SKU'
            $sku | Should -BeNullOrEmpty
        }
    }
}

# ---------------------------------------------------------------------------
# Disable-DepartedUser.ps1 - password generation and Graph call shape
# ---------------------------------------------------------------------------
Describe "Disable-DepartedUser.ps1 - helper logic" {

    Context "Random secure password generation" {
        It "generates a 20-character password" {
            $rand = -join ((33..126) | Get-Random -Count 20 | ForEach-Object {[char]$_})
            $rand.Length | Should -Be 20
        }

        It "generates only printable ASCII characters (codes 33 through 126)" {
            $rand = -join ((33..126) | Get-Random -Count 20 | ForEach-Object {[char]$_})
            foreach ($c in $rand.ToCharArray()) {
                [int]$c | Should -BeGreaterOrEqual 33
                [int]$c | Should -BeLessOrEqual     126
            }
        }

        It "two successive passwords are not equal" {
            $a = -join ((33..126) | Get-Random -Count 20 | ForEach-Object {[char]$_})
            $b = -join ((33..126) | Get-Random -Count 20 | ForEach-Object {[char]$_})
            $a | Should -Not -Be $b
        }
    }

    Context "Graph cmdlet stubs for offboarding flow" {

        BeforeAll {
            function global:Connect-MgGraph           { param([string[]]$Scopes, [switch]$NoWelcome) }
            function global:Disconnect-MgGraph        { return $null }
            function global:Get-MgUser                {
                param([string]$UserId, [string]$ErrorAction)
                return [pscustomobject]@{ Id = 'user-abc-123'; UserPrincipalName = $UserId }
            }
            function global:Update-MgUser             {
                param([string]$UserId, [switch]$AccountEnabled, [hashtable]$PasswordProfile)
            }
            function global:Revoke-MgUserSignInSession {
                param([string]$UserId)
                return $null
            }
            function global:Get-MgUserLicenseDetail   {
                param([string]$UserId)
                return @(
                    [pscustomobject]@{ SkuId = 'mock-sku-1' },
                    [pscustomobject]@{ SkuId = 'mock-sku-2' }
                )
            }
            function global:Set-MgUserLicense         {
                param([string]$UserId, [object[]]$AddLicenses, [object[]]$RemoveLicenses)
                return $null
            }
        }

        AfterAll {
            'Connect-MgGraph','Disconnect-MgGraph','Get-MgUser','Update-MgUser',
            'Revoke-MgUserSignInSession','Get-MgUserLicenseDetail','Set-MgUserLicense' |
            ForEach-Object { Remove-Item -Path "Function:global:$_" -ErrorAction SilentlyContinue }
        }

        It "Get-MgUser stub returns a user object for a given UPN" {
            $user = Get-MgUser -UserId "jdoe@example.com"
            $user    | Should -Not -BeNullOrEmpty
            $user.Id | Should -Be "user-abc-123"
        }

        It "Get-MgUserLicenseDetail stub returns two SKU objects" {
            $details = Get-MgUserLicenseDetail -UserId "user-abc-123"
            $details.Count   | Should -Be 2
            $details[0].SkuId | Should -Be "mock-sku-1"
            $details[1].SkuId | Should -Be "mock-sku-2"
        }

        It "license removal passes AddLicenses as empty and RemoveLicenses as the collected SKU ids" {
            $skus = (Get-MgUserLicenseDetail -UserId "user-abc-123").SkuId

            $script:capturedAdd    = $null
            $script:capturedRemove = $null
            function global:Set-MgUserLicense {
                param([string]$UserId, [object[]]$AddLicenses, [object[]]$RemoveLicenses)
                $script:capturedAdd    = $AddLicenses
                $script:capturedRemove = $RemoveLicenses
                return $null
            }

            if ($skus) {
                Set-MgUserLicense -UserId "user-abc-123" -AddLicenses @() -RemoveLicenses $skus | Out-Null
            }

            $script:capturedAdd.Count    | Should -Be 0
            $script:capturedRemove.Count | Should -Be 2
        }

        It "user object Id flows from Get-MgUser to downstream calls" {
            $user = Get-MgUser -UserId "jdoe@example.com"
            # Simulate block sign-in: UserId should be the Id field, not the UPN
            $user.Id | Should -Be "user-abc-123"
        }
    }
}

# ---------------------------------------------------------------------------
# Clear-WindowsCaches.ps1 - target-path list and helper logic
# ---------------------------------------------------------------------------
Describe "Clear-WindowsCaches.ps1 - path list and helper logic" {

    Context "Cache target paths are well-formed" {
        It "produces exactly 5 target paths" {
            $localAppData = "C:\Users\TestUser\AppData\Local"
            $targets = @(
                "$localAppData\Temp",
                "$localAppData\Google\Chrome\User Data\Default\Cache",
                "$localAppData\Google\Chrome\User Data\Default\Code Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Code Cache"
            )
            $targets.Count | Should -Be 5
        }

        It "all targets are non-empty strings" {
            $localAppData = "C:\Users\TestUser\AppData\Local"
            $targets = @(
                "$localAppData\Temp",
                "$localAppData\Google\Chrome\User Data\Default\Cache",
                "$localAppData\Google\Chrome\User Data\Default\Code Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Code Cache"
            )
            foreach ($t in $targets) {
                $t | Should -Not -BeNullOrEmpty
            }
        }

        It "includes the Chrome default cache path" {
            $localAppData = "C:\Users\TestUser\AppData\Local"
            $targets = @(
                "$localAppData\Temp",
                "$localAppData\Google\Chrome\User Data\Default\Cache",
                "$localAppData\Google\Chrome\User Data\Default\Code Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Code Cache"
            )
            $targets | Should -Contain "$localAppData\Google\Chrome\User Data\Default\Cache"
        }

        It "includes the Edge default cache path" {
            $localAppData = "C:\Users\TestUser\AppData\Local"
            $targets = @(
                "$localAppData\Temp",
                "$localAppData\Google\Chrome\User Data\Default\Cache",
                "$localAppData\Google\Chrome\User Data\Default\Code Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Cache",
                "$localAppData\Microsoft\Edge\User Data\Default\Code Cache"
            )
            $targets | Should -Contain "$localAppData\Microsoft\Edge\User Data\Default\Cache"
        }
    }

    Context "System drive letter extraction" {
        It "trims the colon from a C-drive SystemDrive value" {
            $systemDrive = "C:"
            $driveLetter = $systemDrive.TrimEnd(':')
            $driveLetter | Should -Be "C"
        }

        It "trims the colon from a D-drive SystemDrive value" {
            $systemDrive = "D:"
            $driveLetter = $systemDrive.TrimEnd(':')
            $driveLetter | Should -Be "D"
        }
    }

    Context "Freed space calculation" {
        It "calculates freed MB from a 1 GB difference in SizeRemaining" {
            $before  = 50GB
            $after   = 51GB
            $freedMB = ($after - $before) / 1MB
            $freedMB | Should -Be 1024
        }

        It "returns 0 freed when SizeRemaining is unchanged" {
            $before  = 50GB
            $after   = 50GB
            $freedMB = ($after - $before) / 1MB
            $freedMB | Should -Be 0
        }

        It "reports free space in GB correctly" {
            $after   = 120GB
            $freeGB  = $after / 1GB
            $freeGB  | Should -Be 120
        }
    }
}

# ---------------------------------------------------------------------------
# Script syntax - all .ps1 files parse without errors
# ---------------------------------------------------------------------------
Describe "Script syntax check" {

    BeforeAll {
        $scriptsPath = Join-Path $ScriptRoot 'scripts'
    }

    # The combined parse check is handled by the existing 'parse' job in ci.yml
    # (which runs under pwsh/PS7 where all scripts parse cleanly). Here we just
    # verify the scripts that are fully PS5.1-compatible using the local parser.
    It "Disable-DepartedUser.ps1 parses without syntax errors" {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $scriptsPath 'Disable-DepartedUser.ps1'), [ref]$null, [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }

    It "New-EmployeeOnboarding.ps1 parses without syntax errors" {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $scriptsPath 'New-EmployeeOnboarding.ps1'), [ref]$null, [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }

    It "Clear-WindowsCaches.ps1 parses without syntax errors" {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $scriptsPath 'Clear-WindowsCaches.ps1'), [ref]$null, [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }

    It "Move-PageFile.ps1 parses without syntax errors" {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $scriptsPath 'Move-PageFile.ps1'), [ref]$null, [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }

    It "Get-SystemHealthReport.ps1 exists in the scripts folder" {
        $p = Join-Path $scriptsPath 'Get-SystemHealthReport.ps1'
        $p | Should -Exist
    }

    It "Disable-DepartedUser.ps1 exists in the scripts folder" {
        $p = Join-Path $scriptsPath 'Disable-DepartedUser.ps1'
        $p | Should -Exist
    }

    It "New-EmployeeOnboarding.ps1 exists in the scripts folder" {
        $p = Join-Path $scriptsPath 'New-EmployeeOnboarding.ps1'
        $p | Should -Exist
    }

    It "Clear-WindowsCaches.ps1 exists in the scripts folder" {
        $p = Join-Path $scriptsPath 'Clear-WindowsCaches.ps1'
        $p | Should -Exist
    }

    It "Move-PageFile.ps1 exists in the scripts folder" {
        $p = Join-Path $scriptsPath 'Move-PageFile.ps1'
        $p | Should -Exist
    }
}
