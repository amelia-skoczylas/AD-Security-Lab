<#
.SYNOPSIS
    Migracja z Microsoft LAPS (legacy) na wbudowany Windows LAPS z szyfrowaniem haseł w AD.

.DESCRIPTION
    W Etapie 5 wdrożono Microsoft LAPS (legacy): schemat rozszerzono poleceniem
    Update-AdmPwdADSchema, a hasło trafia do atrybutu ms-Mcs-AdmPwd jako jawny tekst
    (chroniony wyłącznie przez ACL). Microsoft LAPS jest wycofywany na rzecz
    Windows LAPS, wbudowanego w Windows Server 2022 i Windows 10 (od aktualizacji
    z kwietnia 2023).

    Windows LAPS używa własnych atrybutów (msLAPS-Password, msLAPS-EncryptedPassword)
    i potrafi szyfrować hasło tak, że odszyfrować je może tylko wskazana grupa.

    Kroki wykonywane przez skrypt (na DC01):
      1. Rozszerzenie schematu AD o atrybuty Windows LAPS (Update-LapsADSchema).
      2. Utworzenie grupy LAPS-Readers, która jako jedyna może czytać i odszyfrować hasła.
      3. Nadanie komputerom w OU prawa do zapisu własnego hasła.
      4. Nadanie grupie LAPS-Readers prawa odczytu.
      5. Utworzenie GPO z polityką Windows LAPS (kopia w AD, szyfrowanie, 16 znaków, 30 dni).

    Kroki ręczne PO STRONIE KLIENTA (nie da się ich bezpiecznie zautomatyzować z DC):
      - Odinstalować klienta Microsoft LAPS (AdmPwd GPO Extension) z PC-CLIENT01
        i odłączyć stare GPO legacy LAPS. Microsoft zaleca, aby to samo konto
        nie było zarządzane jednocześnie przez obie wersje.
      - gpupdate /force, następnie Invoke-LapsPolicyProcessing.

.PARAMETER TargetOU
    OU ze stacjami roboczymi objętymi LAPS.

.EXAMPLE
    .\03-Deploy-WindowsLAPS.ps1 -WhatIf
    .\03-Deploy-WindowsLAPS.ps1

.NOTES
    Szyfrowanie haseł wymaga poziomu funkcjonalnego domeny Windows Server 2016 lub wyższego
    (nowy las na Windows Server 2022 domyślnie go spełnia).

    Ścieżkę i nazwy wartości rejestru polityki LAPS warto przed uruchomieniem porównać
    z aktualną dokumentacją Microsoft "Configure policy settings for Windows LAPS".
    Alternatywnie te same ustawienia można wyklikać w GPMC:
        Computer Configuration > Policies > Administrative Templates > System > LAPS
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TargetOU    = 'OU=Stacje_Robocze,OU=LAB,DC=lab,DC=local',
    [string]$ReadersOU   = 'OU=Konta_Administracyjne,OU=LAB,DC=lab,DC=local',
    [string]$ReadersName = 'LAPS-Readers',
    [string]$GpoName     = 'GPO_Hardening_WindowsLAPS',
    [ValidateRange(14, 64)][int]$PasswordLength = 16,
    [ValidateRange(1, 365)][int]$PasswordAgeDays = 30
)

#Requires -Modules ActiveDirectory, GroupPolicy, LAPS
$ErrorActionPreference = 'Stop'
$domainNetBios = (Get-ADDomain).NetBIOSName

# 1. Schemat
if ($PSCmdlet.ShouldProcess('Schemat AD', 'Update-LapsADSchema')) {
    Update-LapsADSchema -Confirm:$false
    Write-Host '[+] Schemat AD rozszerzony o atrybuty Windows LAPS.'
}

# 2. Grupa uprawniona do odczytu haseł
if (-not (Get-ADGroup -Filter "Name -eq '$ReadersName'" -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($ReadersName, 'Utwórz grupę')) {
        New-ADGroup -Name $ReadersName -GroupScope Global -GroupCategory Security -Path $ReadersOU `
            -Description 'Jedyna grupa uprawniona do odczytu i odszyfrowania haseł Windows LAPS.'
        Write-Host "[+] Utworzono grupę $ReadersName (dodaj do niej konto administracyjne)."
    }
}

# 3. Komputery mogą zapisywać własne hasło
if ($PSCmdlet.ShouldProcess($TargetOU, 'Set-LapsADComputerSelfPermission')) {
    Set-LapsADComputerSelfPermission -Identity $TargetOU | Out-Null
    Write-Host "[+] Komputery w $TargetOU mogą zapisywać swoje hasła LAPS."
}

# 4. Prawo odczytu tylko dla LAPS-Readers
if ($PSCmdlet.ShouldProcess($TargetOU, "Set-LapsADReadPasswordPermission dla $ReadersName")) {
    Set-LapsADReadPasswordPermission -Identity $TargetOU -AllowedPrincipals "$domainNetBios\$ReadersName" | Out-Null
    Write-Host "[+] Prawo odczytu haseł nadane grupie $ReadersName."
}

# 5. GPO z polityką Windows LAPS
$policyKey = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
$settings = @(
    @{ Name = 'BackupDirectory';               Type = 'DWord';  Value = 2 }                # 2 = Active Directory
    @{ Name = 'PasswordComplexity';            Type = 'DWord';  Value = 4 }                # duże + małe litery + cyfry + znaki specjalne
    @{ Name = 'PasswordLength';                Type = 'DWord';  Value = $PasswordLength }
    @{ Name = 'PasswordAgeDays';               Type = 'DWord';  Value = $PasswordAgeDays }
    @{ Name = 'ADPasswordEncryptionEnabled';   Type = 'DWord';  Value = 1 }
    @{ Name = 'ADPasswordEncryptionPrincipal'; Type = 'String'; Value = "$domainNetBios\$ReadersName" }
)

if (-not (Get-GPO -Name $GpoName -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($GpoName, 'Utwórz GPO')) {
        New-GPO -Name $GpoName -Comment 'Windows LAPS: kopia w AD, szyfrowanie, rotacja.' | Out-Null
        Write-Host "[+] Utworzono GPO: $GpoName"
    }
}
foreach ($s in $settings) {
    if ($PSCmdlet.ShouldProcess($GpoName, "Ustaw $($s.Name) = $($s.Value)")) {
        Set-GPRegistryValue -Name $GpoName -Key $policyKey -ValueName $s.Name -Type $s.Type -Value $s.Value | Out-Null
    }
}
$linked = (Get-GPInheritance -Target $TargetOU).GpoLinks | Where-Object DisplayName -eq $GpoName
if (-not $linked -and $PSCmdlet.ShouldProcess($TargetOU, "Podepnij $GpoName")) {
    New-GPLink -Name $GpoName -Target $TargetOU -LinkEnabled Yes | Out-Null
    Write-Host "[+] Podpięto $GpoName pod $TargetOU"
}

Write-Host ''
Write-Host 'Następne kroki na PC-CLIENT01: odinstaluj klienta legacy LAPS, gpupdate /force, Invoke-LapsPolicyProcessing.'
Write-Host 'Weryfikacja na DC01 (bez wyświetlania hasła): .\04-Test-LAPSConfiguration.ps1'
