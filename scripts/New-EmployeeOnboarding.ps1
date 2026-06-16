<#
.SYNOPSIS
    Onboard a new employee in Microsoft 365 / Entra ID: create the account,
    assign a license, add group memberships, and print a ticket-ready summary.

.EXAMPLE
    .\New-EmployeeOnboarding.ps1 -DisplayName "Jane Doe" -UserPrincipalName jdoe@example.com `
        -Department "Accounting" -JobTitle "Staff Accountant" -Groups "Accounting","All-Staff" -WhatIf

.NOTES
    Requires the Microsoft.Graph module and a User Administrator role.
    Sanitized example — set $LicenseSku to your tenant's SKU (Get-MgSubscribedSku).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$DisplayName,
    [Parameter(Mandatory)] [string]$UserPrincipalName,
    [string]$Department,
    [string]$JobTitle,
    [string[]]$Groups = @(),
    [string]$LicenseSku = "ENTERPRISEPACK",          # e.g. Microsoft 365 E3; change to yours
    [string]$UsageLocation = "US"
)

Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Organization.Read.All" -NoWelcome

# A reasonable temporary password the user must change at first sign-in.
$tempPassword = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 14 | ForEach-Object {[char]$_})
$mailNickname = ($UserPrincipalName -split "@")[0]

if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Create M365 user")) {
    $user = New-MgUser -DisplayName $DisplayName -UserPrincipalName $UserPrincipalName `
        -MailNickname $mailNickname -AccountEnabled `
        -Department $Department -JobTitle $JobTitle -UsageLocation $UsageLocation `
        -PasswordProfile @{ Password = $tempPassword; ForceChangePasswordNextSignIn = $true }

    # Assign license
    $sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq $LicenseSku
    if ($sku) { Set-MgUserLicense -UserId $user.Id -AddLicenses @{ SkuId = $sku.SkuId } -RemoveLicenses @() | Out-Null }

    # Add to groups
    foreach ($g in $Groups) {
        $grp = Get-MgGroup -Filter "displayName eq '$g'" -Top 1
        if ($grp) { New-MgGroupMember -GroupId $grp.Id -DirectoryObjectId $user.Id }
        else { Write-Warning "Group not found: $g" }
    }

    Write-Host "`n--- Onboarding summary (paste into the ticket) ---" -ForegroundColor Cyan
    [pscustomobject]@{
        Name        = $DisplayName
        UPN         = $UserPrincipalName
        Department  = $Department
        Title       = $JobTitle
        License     = $LicenseSku
        Groups      = ($Groups -join ", ")
        TempPassword= $tempPassword
        MustReset   = $true
    } | Format-List
}

Disconnect-MgGraph | Out-Null
