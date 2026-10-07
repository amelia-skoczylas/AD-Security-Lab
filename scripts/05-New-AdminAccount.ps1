<#
.SYNOPSIS
    Tworzy imienne konto administracyjne zamiast pracy na wbudowanym LAB\Administrator.

.DESCRIPTION
    W pierwszej wersji labu wszystkie czynności wykonywano na wbudowanym koncie
    LAB\Administrator. To antywzorzec: konto ma znany SID (-500), jest wspólne,
    nie da się przypisać działań konkretnej osobie i jest pierwszym celem ataków.

    Skrypt:
      1. Tworzy imienne konto administracyjne w OU Konta_Administracyjne
         (konwencja: <login>-adm, osobne od codziennego konta użytkownika).
      2. Dodaje je do Domain Admins i LAPS-Readers.
      3. Dodaje je do grupy Protected Users (brak NTLM, brak delegacji,
         brak buforowania poświadczeń, krótsze bilety Kerberos).

    Konto LAB\Administrator należy potem zostawić jako konto awaryjne
    z długim, sejfowanym hasłem i nie używać go na co dzień.

.EXAMPLE
    .\05-New-AdminAccount.ps1 -SamAccountName 'askoczylas-adm' -DisplayName 'Amelia Skoczylas (admin)'

.NOTES
    Hasło jest pobierane interaktywnie i nie trafia do historii ani do skryptu.
    Konta w Protected Users nie mogą logować się przez NTLM: przed dodaniem
    upewnij się, że logujesz się do DC01 nazwą hosta (Kerberos), a nie adresem IP.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$SamAccountName,
    [Parameter(Mandatory)][string]$DisplayName,
    [string]$AdminOU = 'OU=Konta_Administracyjne,OU=LAB,DC=lab,DC=local',
    [string[]]$Groups = @('Domain Admins', 'LAPS-Readers', 'Protected Users')
)

#Requires -Modules ActiveDirectory
$ErrorActionPreference = 'Stop'
$upnSuffix = (Get-ADDomain).DNSRoot

if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
    Write-Host "[=] Konto $SamAccountName już istnieje."
}
elseif ($PSCmdlet.ShouldProcess($SamAccountName, 'Utwórz konto administracyjne')) {
    $password = Read-Host -AsSecureString -Prompt "Hasło dla $SamAccountName (min. 16 znaków)"
    New-ADUser -Name $DisplayName -SamAccountName $SamAccountName `
        -UserPrincipalName "$SamAccountName@$upnSuffix" -Path $AdminOU `
        -AccountPassword $password -Enabled $true -ChangePasswordAtLogon $false `
        -AccountNotDelegated $true `
        -Description 'Imienne konto administracyjne (tier 0). Nie używać do pracy biurowej.'
    Write-Host "[+] Utworzono konto $SamAccountName"
}

foreach ($g in $Groups) {
    if ($PSCmdlet.ShouldProcess($SamAccountName, "Dodaj do $g")) {
        Add-ADGroupMember -Identity $g -Members $SamAccountName
        Write-Host "[+] $SamAccountName -> $g"
    }
}
