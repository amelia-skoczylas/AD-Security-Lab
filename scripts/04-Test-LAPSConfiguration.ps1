<#
.SYNOPSIS
    Weryfikuje wdrożenie Windows LAPS bez ujawniania hasła.

.DESCRIPTION
    Pierwsza wersja labu potwierdzała działanie LAPS zrzutem ekranu z jawnym hasłem.
    Ten skrypt sprawdza to samo, ale pokazuje wyłącznie metadane:
      - skąd pochodzi hasło (Source: EncryptedPassword oznacza, że szyfrowanie działa),
      - kiedy zostało ustawione i kiedy wygaśnie,
      - kto ma prawo odczytu haseł w OU (audyt uprawnień).

    Hasło jest zwracane jako SecureString i nigdy nie jest wypisywane na ekran.
    Wynik nadaje się do zrzutu ekranu do README.

.EXAMPLE
    .\04-Test-LAPSConfiguration.ps1
#>
[CmdletBinding()]
param(
    [string]$ComputerName = 'PC-CLIENT01',
    [string]$TargetOU     = 'OU=Stacje_Robocze,OU=LAB,DC=lab,DC=local'
)

#Requires -Modules LAPS
$ErrorActionPreference = 'Stop'

Write-Host "=== Hasło LAPS dla $ComputerName (tylko metadane) ===" -ForegroundColor Cyan
# Bez -AsPlainText hasło pozostaje obiektem SecureString.
Get-LapsADPassword -Identity $ComputerName |
    Select-Object ComputerName, Account, Source, DecryptionStatus, AuthorizedDecryptor,
                  PasswordUpdateTime, ExpirationTimestamp |
    Format-List

Write-Host "=== Kto może czytać hasła w $TargetOU ===" -ForegroundColor Cyan
# Każdy podmiot poza oczekiwanymi (np. SYSTEM, Domain Admins, LAPS-Readers) jest do wyjaśnienia.
Find-LapsADExtendedRights -Identity $TargetOU | Format-List
