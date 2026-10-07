# AD-Security-Lab: Hardening Active Directory & LAPS Deployment

> **EN summary:** Home lab simulating a small corporate network (Windows Server 2022 DC, Windows 10 client, OPNsense firewall on VirtualBox). Implemented: AD DS domain, OU structure, GPO hardening (removable storage block) and Microsoft LAPS (legacy) to remove shared local admin passwords. In progress, with PowerShell scripts included: migration to built-in Windows LAPS with AD password encryption, network segmentation with least-privilege firewall rules, and a dedicated named admin account. Lessons learned are documented below.

Projekt laboratoryjny z zakresu cyberbezpieczeństwa (Blue Team / Systems Engineering) symulujący środowisko korporacyjne oparte na Windows Server 2022 oraz Windows 10 Pro. Cel projektu: budowa domeny Active Directory, hardening za pomocą polityk GPO oraz wyeliminowanie wspólnych haseł lokalnych administratorów (LAPS), które ułatwiają atakującemu *lateral movement*.

## Status projektu

| Etap | Zakres | Status |
| :--- | :--- | :--- |
| 1 | Zapora OPNsense jako brama do Internetu | ✅ wdrożone |
| 2 | Kontroler domeny AD DS (`lab.local`) | ✅ wdrożone |
| 3 | Struktura OU i dołączenie stacji roboczej | ✅ wdrożone, 🔧 poprawka struktury OU: [`scripts/01`](scripts/01-New-OUStructure.ps1) |
| 4 | GPO: blokada nośników wymiennych | ✅ wdrożone, 📄 odtworzone jako kod: [`scripts/02`](scripts/02-Set-GPOBlockRemovableStorage.ps1) |
| 5 | Microsoft LAPS (legacy) | ✅ wdrożone |
| 6 | Migracja na Windows LAPS z szyfrowaniem haseł | 🔧 do wdrożenia: [`scripts/03`](scripts/03-Deploy-WindowsLAPS.ps1), [`scripts/04`](scripts/04-Test-LAPSConfiguration.ps1) |
| 7 | Imienne konto administracyjne zamiast `LAB\Administrator` | 🔧 do wdrożenia: [`scripts/05`](scripts/05-New-AdminAccount.ps1) |
| 8 | Segmentacja sieci i reguły zapory | 🔧 do wdrożenia: [`docs/opnsense-segmentation.md`](docs/opnsense-segmentation.md) |

## Architektura laboratorium i topologia sieci

Środowisko zostało zbudowane w oparciu o wirtualizator Oracle VirtualBox z wykorzystaniem izolowanej sieci wirtualnej (`ad-lab`).

| Maszyna wirtualna | Rola w sieci | System operacyjny | Adres IP | DNS Server |
| :--- | :--- | :--- | :--- | :--- |
| **OPNsense-FW** | Firewall / Default Gateway | OPNsense (FreeBSD) | `192.168.10.1` (LAN) / NAT (WAN) | N/A |
| **DC01** | Kontroler Domeny (`lab.local`), DNS Server | Windows Server 2022 Standard | `192.168.10.10` | `127.0.0.1` / `192.168.10.10` |
| **AD-Client** | Stacja robocza (Domain Member) | Windows 10 Pro | `192.168.10.20` | `192.168.10.10` |

> **Ograniczenie obecnej topologii:** wszystkie maszyny są w jednej podsieci `192.168.10.0/24`, więc ruch między stacją roboczą a kontrolerem domeny nie przechodzi przez zaporę. Docelową segmentację opisuje [`docs/opnsense-segmentation.md`](docs/opnsense-segmentation.md).

### Weryfikacja komunikacji sieciowej
Poniższy zrzut ekranu przedstawia pomyślną weryfikację połączenia (ICMP Ping) pomiędzy stacją roboczą a Kontrolerem Domeny wewnątrz izolowanej podsieci:

<img width="991" height="642" alt="Test połączenia ping między PC-CLIENT01 a DC01" src="https://github.com/user-attachments/assets/0797bd1b-646a-4ba2-9a08-c0987c42ed03" />

## Etap 1: Wdrożenie zapory sieciowej (Edge Security - OPNsense)

W celu zabezpieczenia styku z Internetem i kontroli ruchu wychodzącego wdrożono zaporę sieciową OPNsense.
1. Maszyna wirtualna została wyposażona w dwa interfejsy: WAN (dostęp do Internetu) oraz LAN (brama domyślna dla sieci `ad-lab`).
2. Skonfigurowano adresację statyczną interfejsu LAN na `192.168.10.1`.
3. Na Kontrolerze Domeny oraz stacji roboczej ustawiono OPNsense jako bramę domyślną. Dzięki temu cały ruch **wychodzący do Internetu** przechodzi przez zaporę i może być filtrowany oraz logowany.

Ruch wewnątrz podsieci (stacja robocza ↔ DC) na tym etapie nie przechodzi przez OPNsense. Reguły filtrujące ten ruch są zaplanowane w Etapie 8.

<img width="626" height="484" alt="Konsola OPNsense" src="https://github.com/user-attachments/assets/225753ec-6b84-4e78-80bf-0c75131ed0b4" />

---

## Etap 2: Budowa Kontrolera Domeny Active Directory (AD DS)

1. **Konfiguracja statycznego adresowania IP** na serwerze `DC01` oraz instalacja roli **Active Directory Domain Services (AD DS)**.
2. **Promocja serwera** do poziomu Kontrolera Domeny dla nowego lasu: `lab.local`.
3. Pomyślna weryfikacja operacji i logowanie na konto administratora domeny (`LAB\Administrator`).

> **Uwaga (dobra praktyka):** praca na wbudowanym koncie `LAB\Administrator` jest w środowisku produkcyjnym antywzorcem: konto jest wspólne, ma znany SID i jest pierwszym celem ataków. W Etapie 7 zostanie zastąpione imiennym kontem administracyjnym w grupie *Protected Users*, a `LAB\Administrator` pozostanie kontem awaryjnym.

<img width="1021" height="835" alt="Promocja DC i status usług AD DS" src="https://github.com/user-attachments/assets/5fcc7ac4-be9f-4750-9aab-2c2f52f1a504" />

---

## Etap 3: Struktura Organizacyjna i Podłączenie Stacji Roboczej

W celu uporządkowania zarządzania tożsamością utworzono jednostki organizacyjne (OU), pod które można podpinać osobne polityki GPO.
1. Utworzono kontenery OU: `Firmowe_Konta` oraz podrzędne `Stacje_Robocze`.
2. Stację roboczą Windows 10 przełączono z domyślnej grupy roboczej do domeny `lab.local` pod nową, ustandaryzowaną nazwą (`PC-CLIENT01`).

<img width="519" height="325" alt="Struktura OU i stacja PC-CLIENT01 w domenie" src="https://github.com/user-attachments/assets/b3af9450-3f44-4cd2-a99e-45582be287a2" />

> **Poprawka:** umieszczenie `Stacje_Robocze` wewnątrz `Firmowe_Konta` miesza obiekty komputerów z kontami użytkowników. Docelowa struktura z osobnymi OU (`Konta_Uzytkownikow`, `Konta_Administracyjne`, `Stacje_Robocze`, `Serwery`) jest tworzona skryptem [`scripts/01-New-OUStructure.ps1`](scripts/01-New-OUStructure.ps1).

---

## Etap 4: Hardening GPO (Polityki Bezpieczeństwa)

Nośniki wymienne są jednym z wektorów wprowadzania złośliwego oprogramowania (np. ransomware) i wynoszenia danych (exfiltration). Wdrożono centralną politykę GPO blokującą dostęp do nośników wymiennych na stacjach końcowych.
1. Skonfigurowano obiekt GPO (`GPO_Hardening_BlockUSB`) podpięty pod OU `Stacje_Robocze`.
2. Aktywowano regułę: *All Removable Storage classes: Deny all access*.
3. Pomyślnie zweryfikowano działanie blokady na stacji roboczej po wykonaniu aktualizacji zasad (`gpupdate /force`): system zwraca komunikat „Odmowa dostępu”.

<img width="911" height="735" alt="Blokada nośnika USB na PC-CLIENT01" src="https://github.com/user-attachments/assets/8352ba30-220c-4660-8d21-fa157eafed05" />

Ta sama polityka jest odtworzona jako kod w [`scripts/02-Set-GPOBlockRemovableStorage.ps1`](scripts/02-Set-GPOBlockRemovableStorage.ps1), który dodatkowo wykonuje backup GPO i raport HTML.

---

## Etap 5: Wdrożenie Microsoft LAPS (legacy)

Wspólne, statyczne hasło lokalnego administratora na wielu stacjach pozwala atakującemu, który przejmie jedną maszynę, zalogować się tym samym hasłem (lub jego hashem, *Pass-the-Hash*) na pozostałe. LAPS nadaje każdej stacji unikalne, rotowane hasło, dzięki czemu **ogranicza zasięg lateral movement**: przejęte poświadczenia działają tylko na jednej maszynie. LAPS nie zapobiega samej technice Pass-the-Hash.

1. Rozszerzono schemat Active Directory (`Update-AdmPwdADSchema`) o atrybuty Microsoft LAPS.
2. Skonfigurowano politykę wymuszającą generowanie 16-znakowych haseł o pełnej złożoności, rotowanych co 30 dni.
3. **Weryfikacja:** odczytano wygenerowane hasło stacji `PC-CLIENT01` z atrybutu `ms-Mcs-AdmPwd` na Kontrolerze Domeny.

<!-- TODO: wstawić zrzut z zamazanym hasłem (oryginalny zrzut pokazywał hasło jawnym tekstem) -->

> **Wniosek:** Microsoft LAPS (legacy) przechowuje hasło w atrybucie `ms-Mcs-AdmPwd` **jawnym tekstem**, chronionym wyłącznie przez uprawnienia ACL. Każdy, kto ma prawo odczytu atrybutu, widzi hasło. Rozwiązanie jest wycofywane przez Microsoft na rzecz wbudowanego Windows LAPS, dlatego zaplanowano migrację (Etap 6).

---

## Etap 6: Migracja na Windows LAPS z szyfrowaniem haseł (do wdrożenia)

Windows LAPS jest wbudowany w Windows Server 2022 i Windows 10 (od aktualizacji z kwietnia 2023). W porównaniu z wersją legacy:

| | Microsoft LAPS (legacy) | Windows LAPS |
| :--- | :--- | :--- |
| Instalacja | osobny klient (MSI) na każdej stacji | wbudowany w system |
| Rozszerzenie schematu | `Update-AdmPwdADSchema` | `Update-LapsADSchema` |
| Atrybut z hasłem | `ms-Mcs-AdmPwd` (jawny tekst) | `msLAPS-Password` lub `msLAPS-EncryptedPassword` |
| Szyfrowanie w AD | brak | tak, odszyfrować może tylko wskazana grupa |
| Historia haseł | brak | tak (przy szyfrowaniu) |
| Kopia do Entra ID | nie | tak |

Plan wdrożenia:
1. [`scripts/03-Deploy-WindowsLAPS.ps1`](scripts/03-Deploy-WindowsLAPS.ps1): rozszerzenie schematu, grupa `LAPS-Readers`, uprawnienia i GPO z włączonym szyfrowaniem.
2. Na `PC-CLIENT01`: odinstalowanie klienta legacy LAPS i odłączenie starego GPO (to samo konto nie powinno być zarządzane przez obie wersje), następnie `gpupdate /force` i `Invoke-LapsPolicyProcessing`.
3. [`scripts/04-Test-LAPSConfiguration.ps1`](scripts/04-Test-LAPSConfiguration.ps1): weryfikacja **bez wyświetlania hasła**. Pole `Source: EncryptedPassword` potwierdza szyfrowanie, a `Find-LapsADExtendedRights` pokazuje, kto może czytać hasła.

---

## Etap 7: Imienne konto administracyjne (do wdrożenia)

[`scripts/05-New-AdminAccount.ps1`](scripts/05-New-AdminAccount.ps1) tworzy konto `<login>-adm` w OU `Konta_Administracyjne`, dodaje je do *Domain Admins*, `LAPS-Readers` i *Protected Users* (bez NTLM, bez delegacji, bez buforowania poświadczeń).

## Etap 8: Segmentacja sieci (do wdrożenia)

Rozdzielenie serwerów i stacji roboczych na osobne podsieci z regułami *least privilege* na OPNsense: stacje mogą komunikować się z DC tylko na portach potrzebnych domenie (DNS, Kerberos, LDAP, SMB, RPC), a cały pozostały ruch jest blokowany i logowany. Szczegóły i tabela reguł: [`docs/opnsense-segmentation.md`](docs/opnsense-segmentation.md).

---

## Wnioski (lessons learned)

- **Wersja narzędzia ma znaczenie.** Microsoft LAPS i Windows LAPS to różne produkty z różnymi atrybutami i modelem bezpieczeństwa. Przegląd dokumentacji przed wdrożeniem pozwala uniknąć wdrażania rozwiązania wycofywanego.
- **Dowód nie może być wyciekiem.** Weryfikacja działania LAPS nie wymaga pokazywania hasła: wystarczą metadane (źródło, data rotacji, uprawnienia).
- **Brama domyślna to nie segmentacja.** Zapora widzi tylko ruch, który przez nią przechodzi. Hosty w jednej podsieci komunikują się z pominięciem zapory.
- **Precyzja w opisie zagrożeń.** LAPS ogranicza skutki Pass-the-Hash (jedno hasło = jedna maszyna), ale nie blokuje samej techniki.
- **Konfiguracja jako kod.** Ustawienia odtworzone skryptami PowerShell da się przejrzeć, powtórzyć i porównać, w przeciwieństwie do samych zrzutów ekranu.

## Kolejne kroki

- [ ] Wdrożenie Etapów 6–8 i dołączenie zrzutów z weryfikacji.
- [ ] Symulacja ataków na lab z maszyny Kali (np. enumeracja BloodHound, password spraying, Kerberoasting) i porównanie wyników przed oraz po hardeningu.
- [ ] Zbieranie logów (Sysmon + Wazuh) i reguły detekcji zmapowane na MITRE ATT&CK.

## Struktura repozytorium

```
AD-Security-Lab/
├── README.md
├── scripts/
│   ├── 01-New-OUStructure.ps1              # docelowa struktura OU
│   ├── 02-Set-GPOBlockRemovableStorage.ps1 # GPO blokady USB jako kod + backup
│   ├── 03-Deploy-WindowsLAPS.ps1           # migracja na Windows LAPS z szyfrowaniem
│   ├── 04-Test-LAPSConfiguration.ps1       # weryfikacja LAPS bez ujawniania hasła
│   └── 05-New-AdminAccount.ps1             # imienne konto admina w Protected Users
└── docs/
    └── opnsense-segmentation.md            # plan segmentacji i reguł zapory
```

Skrypty uruchamia się na `DC01` jako administrator domeny. Każdy obsługuje `-WhatIf`, który pokazuje planowane zmiany bez ich wykonywania.
