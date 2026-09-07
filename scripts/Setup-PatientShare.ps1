<#
.SYNOPSIS
    Provisions the restricted PatientRecords$ share with locked-down
    share-level and NTFS-level permissions.

.DESCRIPTION
    Creates C:\Shares\PatientRecords, shares it as a hidden share, and
    grants read access to SG_PHI_Access_Read only — removing the default
    Everyone/Users grants at both the share and NTFS layers. Windows
    applies the more restrictive of the two whenever a resource is
    accessed over the network, so both layers must be locked down;
    fixing only one leaves the resource effectively open.

.NOTES
    Run on DC-CLINIC-01 as STJUDE-CLINIC\Administrator, after the
    SG_PHI_Access_Read group has been created (see Deploy-ClinicAD.ps1).
#>

$ErrorActionPreference = "Stop"

$FolderPath = "C:\Shares\PatientRecords"
$ShareName  = "PatientRecords$"
$Group      = "STJUDE-CLINIC\SG_PHI_Access_Read"

Write-Host "Creating folder $FolderPath..." -ForegroundColor Cyan
New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null

Write-Host "Creating hidden share $ShareName..." -ForegroundColor Cyan
New-SmbShare -Name $ShareName -Path $FolderPath -FullAccess $Group

Write-Host "Locking down share permissions..." -ForegroundColor Cyan
Revoke-SmbShareAccess -Name $ShareName -AccountName "Everyone" -Force
Grant-SmbShareAccess -Name $ShareName -AccountName $Group -AccessRight Read -Force

Write-Host "Locking down NTFS permissions..." -ForegroundColor Cyan
icacls $FolderPath /inheritance:d
icacls $FolderPath /remove "Users"
icacls $FolderPath /grant "$($Group):(RX)"

Write-Host "`nVerification:" -ForegroundColor Green
Get-SmbShareAccess -Name $ShareName
icacls $FolderPath
