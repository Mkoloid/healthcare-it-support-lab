<#
.SYNOPSIS
    Automated Active Directory provisioning for the St. Jude Clinic lab domain.

.DESCRIPTION
    Creates the OU hierarchy, security groups, clinic user accounts, and
    group memberships for the Healthcare IT Support Lab. Run on the domain
    controller (DC-CLINIC-01) after AD DS has been promoted and the
    stjude-clinic.local forest exists.

.NOTES
    Run as: STJUDE-CLINIC\Administrator, in an elevated PowerShell session.
    Idempotency: this script does not check for existing objects. Re-running
    it against an already-provisioned domain will throw "already exists"
    errors on each cmdlet — expected and safe to ignore for a lab rebuild,
    or wrap each block in a check (see README for guidance) for production use.
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 1. Organizational Units
# ---------------------------------------------------------------------------
Write-Host "Creating OU hierarchy..." -ForegroundColor Cyan

New-ADOrganizationalUnit -Name "Healthcare_Clinic" `
    -Path "DC=stjude-clinic,DC=local"

New-ADOrganizationalUnit -Name "Clinical_Staff" `
    -Path "OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

New-ADOrganizationalUnit -Name "Doctors" `
    -Path "OU=Clinical_Staff,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

New-ADOrganizationalUnit -Name "Nurses" `
    -Path "OU=Clinical_Staff,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

New-ADOrganizationalUnit -Name "Administrative" `
    -Path "OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

New-ADOrganizationalUnit -Name "Workstations" `
    -Path "OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

# ---------------------------------------------------------------------------
# 2. Security Groups
# ---------------------------------------------------------------------------
Write-Host "Creating security groups..." -ForegroundColor Cyan

New-ADGroup -Name "SG_Clinical_Users" -GroupScope Global -Category Security `
    -Path "OU=Clinical_Staff,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

New-ADGroup -Name "SG_PHI_Access_Read" -GroupScope Global -Category Security `
    -Path "OU=Clinical_Staff,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

New-ADGroup -Name "SG_Admin_Users" -GroupScope Global -Category Security `
    -Path "OU=Administrative,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local"

# ---------------------------------------------------------------------------
# 3. Clinic User Accounts
# ---------------------------------------------------------------------------
Write-Host "Creating user accounts..." -ForegroundColor Cyan

# NOTE: for anything beyond a throwaway lab, prompt for this instead of
# hardcoding it — see README "Hardening for real use" section.
$Password = ConvertTo-SecureString "UserP@ss2026!" -AsPlainText -Force

New-ADUser -Name "Dr. Mahmoud Mohamed" -GivenName "Mahmoud" -Surname "Mohamed" `
    -SamAccountName "dr.mahmoud" `
    -UserPrincipalName "dr.mahmoud@stjude-clinic.local" `
    -Path "OU=Doctors,OU=Clinical_Staff,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local" `
    -AccountPassword $Password -Enabled $true -ChangePasswordAtLogon $false

New-ADUser -Name "Nurse Ola Ali" -GivenName "Ola" -Surname "Ali" `
    -SamAccountName "nurse.ola" `
    -UserPrincipalName "nurse.ola@stjude-clinic.local" `
    -Path "OU=Nurses,OU=Clinical_Staff,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local" `
    -AccountPassword $Password -Enabled $true -ChangePasswordAtLogon $false

New-ADUser -Name "Receptionist Ahmed Mohamed" -GivenName "Ahmed" -Surname "Mohamed" `
    -SamAccountName "admin.ahmed" `
    -UserPrincipalName "admin.ahmed@stjude-clinic.local" `
    -Path "OU=Administrative,OU=Healthcare_Clinic,DC=stjude-clinic,DC=local" `
    -AccountPassword $Password -Enabled $true -ChangePasswordAtLogon $false

# ---------------------------------------------------------------------------
# 4. Group Memberships
# ---------------------------------------------------------------------------
Write-Host "Assigning group memberships..." -ForegroundColor Cyan

Add-ADGroupMember -Identity "SG_Clinical_Users" -Members "dr.mahmoud", "nurse.ola"
Add-ADGroupMember -Identity "SG_PHI_Access_Read" -Members "dr.mahmoud", "nurse.ola"
Add-ADGroupMember -Identity "SG_Admin_Users" -Members "admin.ahmed"

Write-Host "Done. Verify with Get-ADUser / Get-ADGroupMember (see README)." -ForegroundColor Green
