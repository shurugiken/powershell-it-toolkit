<#
.SYNOPSIS
    Offboard a departing user in Microsoft 365 / Entra ID — securely and in the
    right order: block sign-in, kill active sessions, reset the password,
    convert the mailbox to shared, and strip licenses.

.DESCRIPTION
    The order matters for security: block sign-in and revoke sessions FIRST so the
    account can't be used while you finish, THEN handle mail/licenses. Converting to
    a shared mailbox preserves email access for the team without consuming a license.

.EXAMPLE
    .\Disable-DepartedUser.ps1 -UserPrincipalName jdoe@example.com -WhatIf

.NOTES
    Requires Microsoft.Graph (+ ExchangeOnlineManagement for the shared-mailbox step)
    and User Administrator / Exchange Administrator roles. Sanitized example.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$UserPrincipalName,
    [switch]$ConvertToShared
)

Connect-MgGraph -Scopes "User.ReadWrite.All","Directory.AccessAsUser.All" -NoWelcome
$user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop

# 1) Block sign-in immediately.
if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Block sign-in")) {
    Update-MgUser -UserId $user.Id -AccountEnabled:$false
}

# 2) Revoke all active sessions/refresh tokens (forces re-auth everywhere = locked out).
if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Revoke sessions")) {
    Revoke-MgUserSignInSession -UserId $user.Id | Out-Null
}

# 3) Reset to a random password the departing user won't know.
if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Reset password")) {
    $rand = -join ((33..126) | Get-Random -Count 20 | ForEach-Object {[char]$_})
    Update-MgUser -UserId $user.Id -PasswordProfile @{ Password = $rand; ForceChangePasswordNextSignIn = $true }
}

# 4) (Optional) convert the mailbox to shared so the team keeps the email, no license needed.
if ($ConvertToShared) {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Connect-ExchangeOnline -ShowBanner:$false
    if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Convert mailbox to shared")) {
        Set-Mailbox -Identity $UserPrincipalName -Type Shared
    }
    Disconnect-ExchangeOnline -Confirm:$false
}

# 5) Remove all assigned licenses.
if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Remove licenses")) {
    $skus = (Get-MgUserLicenseDetail -UserId $user.Id).SkuId
    if ($skus) { Set-MgUserLicense -UserId $user.Id -AddLicenses @() -RemoveLicenses $skus | Out-Null }
}

Write-Host "Offboarded $UserPrincipalName (sign-in blocked, sessions revoked, password reset, licenses removed)." -ForegroundColor Green
Disconnect-MgGraph | Out-Null
