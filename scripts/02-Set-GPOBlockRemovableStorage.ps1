<#
.SYNOPSIS
    Odtwarza jako kod politykę GPO blokującą wszystkie nośniki wymienne (Etap 4).

.DESCRIPTION
    Pierwotnie polityka była ustawiona ręcznie w GPMC:
        Computer Configuration > Policies > Administrative Templates > System >
        Removable Storage Access > "All Removable Storage classes: Deny all access" = Enabled

    To ustawienie zapisuje w rejestrze klienta wartość:
        HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices
        Deny_All (DWORD) = 1

    Skrypt tworzy GPO (jeśli nie istnieje), ustawia tę wartość i podpina GPO
    pod OU stacji roboczych. Dzięki temu konfigurację da się odtworzyć i przejrzeć
    w repozytorium, a nie tylko na zrzucie ekranu.

    Uruchamiać na DC01 jako administrator domeny.

.EXAMPLE
    .\02-Set-GPOBlockRemovableStorage.ps1 -WhatIf
    .\02-Set-GPOBlockRemovableStorage.ps1

.NOTES
    Weryfikacja na kliencie:
        gpupdate /force
        gpresult /r /scope computer      # GPO powinno być na liście "Applied Group Policy Objects"
        reg query HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices /v Deny_All
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GpoName  = 'GPO_Hardening_BlockUSB',
    [string]$TargetOU = 'OU=Stacje_Robocze,OU=LAB,DC=lab,DC=local'
)

#Requires -Modules GroupPolicy
$ErrorActionPreference = 'Stop'

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    if ($PSCmdlet.ShouldProcess($GpoName, 'Utwórz GPO')) {
        $gpo = New-GPO -Name $GpoName -Comment 'Blokada wszystkich klas nośników wymiennych (Deny_All).'
        Write-Host "[+] Utworzono GPO: $GpoName"
    }
}
else {
    Write-Host "[=] GPO już istnieje: $GpoName"
}

if ($PSCmdlet.ShouldProcess($GpoName, 'Ustaw Deny_All = 1')) {
    Set-GPRegistryValue -Name $GpoName `
        -Key 'HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices' `
        -ValueName 'Deny_All' -Type DWord -Value 1 | Out-Null
    Write-Host '[+] Ustawiono: All Removable Storage classes: Deny all access'
}

$linked = (Get-GPInheritance -Target $TargetOU).GpoLinks | Where-Object DisplayName -eq $GpoName
if ($linked) {
    Write-Host "[=] GPO jest już podpięte pod $TargetOU"
}
elseif ($PSCmdlet.ShouldProcess($TargetOU, "Podepnij $GpoName")) {
    New-GPLink -Name $GpoName -Target $TargetOU -LinkEnabled Yes | Out-Null
    Write-Host "[+] Podpięto $GpoName pod $TargetOU"
}

# Kopia zapasowa GPO, którą można dołączyć do repozytorium jako dowód konfiguracji.
$backupDir = Join-Path $PSScriptRoot '..\gpo-backups'
if ($PSCmdlet.ShouldProcess($backupDir, "Backup $GpoName")) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Backup-GPO -Name $GpoName -Path $backupDir | Out-Null
    Get-GPOReport -Name $GpoName -ReportType Html -Path (Join-Path $backupDir "$GpoName.html")
    Write-Host "[+] Backup i raport HTML zapisane w $backupDir"
}
