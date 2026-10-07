# OPNsense: segmentacja sieci i reguły zapory (plan)

> **Status: do wdrożenia.** Ten dokument opisuje docelową konfigurację, która poprawia
> problem zauważony w pierwszej wersji labu. Po wdrożeniu dołącz zrzuty reguł
> i eksport konfiguracji (z zamaskowanymi hasłami) do katalogu `docs/`.

## Problem w obecnej wersji

DC01 (`192.168.10.10`) i PC-CLIENT01 (`192.168.10.20`) są w tej samej podsieci `192.168.10.0/24`.
Ruch między nimi idzie bezpośrednio przez wirtualny przełącznik VirtualBox i **nigdy nie przechodzi
przez OPNsense**. Zapora widzi wyłącznie ruch wychodzący do Internetu, więc nie może ani filtrować,
ani logować komunikacji klient ↔ kontroler domeny, czyli dokładnie tej drogi, którą idzie
większość ataków na AD (lateral movement, Kerberoasting, enumeracja LDAP).

## Docelowa topologia

W VirtualBox najprościej zrobić segmentację na osobnych sieciach wewnętrznych
(odpowiednik VLAN-ów), każda podpięta do osobnego interfejsu OPNsense.

| Segment | Sieć VirtualBox | Podsieć | Interfejs OPNsense | Maszyny |
| :--- | :--- | :--- | :--- | :--- |
| Serwery | `ad-servers` | `192.168.10.0/24` | LAN `192.168.10.1` | DC01 `192.168.10.10` |
| Stacje robocze | `ad-clients` | `192.168.20.0/24` | OPT1 `192.168.20.1` | PC-CLIENT01 `192.168.20.20` |
| Internet | NAT | (DHCP) | WAN | — |

Po zmianie: PC-CLIENT01 dostaje adres `192.168.20.20`, bramę `192.168.20.1` i DNS `192.168.10.10`.

## Reguły: stacje robocze → kontroler domeny

Zasada: **domyślnie blokuj, przepuszczaj tylko porty potrzebne do działania domeny.**
Reguły na interfejsie OPT1 (`ad-clients`), źródło `192.168.20.0/24`, cel `192.168.10.10`.

| # | Akcja | Protokół | Port(y) | Usługa | Logowanie |
| :-- | :--- | :--- | :--- | :--- | :--- |
| 1 | Pass | TCP/UDP | 53 | DNS | nie |
| 2 | Pass | TCP/UDP | 88 | Kerberos | tak |
| 3 | Pass | TCP/UDP | 464 | Kerberos (zmiana hasła) | tak |
| 4 | Pass | UDP | 123 | NTP (synchronizacja czasu, wymagana przez Kerberos) | nie |
| 5 | Pass | TCP | 135 | RPC Endpoint Mapper | tak |
| 6 | Pass | TCP | 389, 636 | LDAP / LDAPS | tak |
| 7 | Pass | TCP | 3268, 3269 | Global Catalog | tak |
| 8 | Pass | TCP | 445 | SMB (SYSVOL/NETLOGON, czyli pobieranie GPO) | tak |
| 9 | Pass | TCP | 49152–65535 | RPC dynamiczne | tak |
| 10 | **Block** | any | any | wszystko inne do segmentu serwerów | **tak** |

Uwagi:
- Zakres portów RPC dynamicznych można zawęzić na DC (konfiguracja portów RPC w rejestrze),
  co pozwala zamienić regułę 9 na wąski zakres. To dobry kolejny krok hardeningu.
- Nie ma reguły na RDP (3389) ani WinRM (5985/5986) ze stacji roboczych do DC.
  Administracja DC powinna odbywać się z dedykowanej stacji administracyjnej, nie z PC-CLIENT01.
- Logowanie reguł blokujących to źródło danych dla przyszłego SIEM-a (Wazuh).

## Reguły: ruch wychodzący (egress)

OPNsense przetwarza reguły na interfejsie od góry do pierwszego dopasowania. Na OPT1
reguły z tabeli powyżej (do DC) muszą stać **przed** regułami egress, inaczej reguła 2
poniżej zablokowałaby też DNS do kontrolera domeny.

| # | Interfejs | Akcja | Źródło | Cel | Port(y) | Cel reguły |
| :-- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | OPT1 | Pass | `192.168.20.0/24` | any | 80, 443 | przeglądanie WWW, aktualizacje |
| 2 | OPT1 | Block | `192.168.20.0/24` | any | 53 | wymusza DNS przez DC (utrudnia DNS tunneling) |
| 3 | LAN | Pass | `192.168.10.10` | any | 53 | DC jako jedyny resolver zewnętrzny |
| 4 | LAN | Pass | `192.168.10.0/24` | any | 80, 443 | Windows Update |
| 5 | oba | Block | any | any | any | domyślna blokada z logowaniem |

## Weryfikacja po wdrożeniu

Na PC-CLIENT01:

```powershell
# Ruch dozwolony: domena dalej działa
nltest /sc_verify:lab.local
gpupdate /force
Test-NetConnection 192.168.10.10 -Port 389     # TcpTestSucceeded : True

# Ruch zablokowany
Test-NetConnection 192.168.10.10 -Port 3389    # TcpTestSucceeded : False
Resolve-DnsName example.com -Server 1.1.1.1    # powinno się nie udać
```

W OPNsense: **Firewall > Log Files > Live View**, filtr na `192.168.20.20`,
powinny być widoczne zablokowane próby z ostatnich testów. Ten zrzut ekranu to dowód,
że zapora faktycznie widzi i filtruje ruch wewnętrzny.
