<#
.SYNOPSIS
    Tworzy uporządkowaną strukturę OU dla domeny lab.local i przenosi do niej stację roboczą.

.DESCRIPTION
    Poprawka względem pierwszej wersji labu: OU "Stacje_Robocze" było podfolderem
    "Firmowe_Konta", co mieszało konta użytkowników z obiektami komputerów.
    Ten skrypt tworzy osobne OU na tym samym poziomie:

        OU=LAB
         ├── OU=Konta_Uzytkownikow
         ├── OU=Konta_Administracyjne
         ├── OU=Stacje_Robocze
         └── OU=Serwery

    Dzięki temu polityki GPO dla komputerów (np. blokada USB, LAPS) nie obejmują
    przypadkiem kont użytkowników i odwrotnie.

    Uruchamiać na DC01 jako administrator domeny. Skrypt jest idempotentny:
    istniejące OU są pomijane.

.PARAMETER DomainDN
    Distinguished name domeny. Domyślnie DC=lab,DC=local.

.PARAMETER WorkstationName
    Stacja robocza do przeniesienia do nowego OU. Domyślnie PC-CLIENT01.

.EXAMPLE
    .\01-New-OUStructure.ps1 -WhatIf
    .\01-New-OUStructure.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DomainDN = 'DC=lab,DC=local',
    [string]$WorkstationName = 'PC-CLIENT01'
)

#Requires -Modules ActiveDirectory
$ErrorActionPreference = 'Stop'

$rootOU   = "OU=LAB,$DomainDN"
$childOUs = 'Konta_Uzytkownikow', 'Konta_Administracyjne', 'Stacje_Robocze', 'Serwery'

function New-OUIfMissing {
    param([string]$Name, [string]$Path)
    $dn = "OU=$Name,$Path"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue) {
        Write-Host "[=] OU już istnieje: $dn"
    }
    elseif ($PSCmdlet.ShouldProcess($dn, 'Utwórz OU')) {
        # Ochrona przed przypadkowym usunięciem jest domyślnie włączona.
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
        Write-Host "[+] Utworzono OU: $dn"
    }
}

New-OUIfMissing -Name 'LAB' -Path $DomainDN
foreach ($ou in $childOUs) {
    New-OUIfMissing -Name $ou -Path $rootOU
}

# Przeniesienie stacji roboczej do właściwego OU.
$targetOU = "OU=Stacje_Robocze,$rootOU"
$computer = Get-ADComputer -Identity $WorkstationName
if ($computer.DistinguishedName -like "*,$targetOU") {
    Write-Host "[=] $WorkstationName jest już w $targetOU"
}
elseif ($PSCmdlet.ShouldProcess($WorkstationName, "Przenieś do $targetOU")) {
    Move-ADObject -Identity $computer.DistinguishedName -TargetPath $targetOU
    Write-Host "[+] Przeniesiono $WorkstationName do $targetOU"
}

Write-Host ''
Write-Host 'Pamiętaj: GPO podpięte pod stare OU (np. GPO_Hardening_BlockUSB) trzeba podpiąć pod'
Write-Host "nowe OU: $targetOU. Zrobi to skrypt 02-Set-GPOBlockRemovableStorage.ps1."
