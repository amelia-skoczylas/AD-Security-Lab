# AD-Security-Lab: Hardening Active Directory & LAPS Deployment

Projekt laboratoryjny z zakresu cyberbezpieczeństwa (Blue Team / Systems Engineering) symulujący środowisko korporacyjne oparte na Windows Server 2022 oraz Windows 10 Pro. Cel projektu obejmuje budowę domeny Active Directory, implementację polityk zabezpieczeń GPO (Hardening) oraz wdrożenie mechanizmu Windows LAPS chroniącego przed atakami typu *Lateral Movement*.

##  Architektura Laboratorium i Topologia Sieci

Środowisko zostało zbudowane w oparciu o wirtualizator Oracle VirtualBox z wykorzystaniem izolowanej sieci wirtualnej (`ad-lab`).

| Maszyna wirtualna | Rola w sieci | System operacyjny | Adres IP | DNS Server |
| :--- | :--- | :--- | :--- | :--- |
| **OPNsense-FW** | Firewall / Default Gateway | HardenedBSD (OPNsense) | `192.168.10.1` (LAN) / NAT (WAN) | N/A |
| **DC01** | Kontroler Domeny (`lab.local`), DNS Server | Windows Server 2022 Standard | `192.168.10.10` | `127.0.0.1` / `192.168.10.10` |
| **AD-Client** | Stacja robocza (Domain Member) | Windows 10 Pro | `192.168.10.20` | `192.168.10.10` |

### Weryfikacja komunikacji sieciowej
Poniższy zrzut ekranu przedstawia pomyślną weryfikację połączenia (ICMP Ping) pomiędzy stacją roboczą a Kontrolerem Domeny wewnątrz izolowanej podsieci:

![Test połączenia Ping]
<img width="991" height="642" alt="image" src="https://github.com/user-attachments/assets/0797bd1b-646a-4ba2-9a08-c0987c42ed03" />

## Etap 1: Wdrożenie zapory sieciowej (Edge Security - OPNsense)

W celu zabezpieczenia styku sieci i monitorowania ruchu wychodzącego, wdrożono zaporę sieciową klasy korporacyjnej bazującą na systemie OPNsense.
1. Maszyna wirtualna została wyposażona w dwa interfejsy: WAN (dostęp do Internetu) oraz LAN (brama domyślna dla sieci `ad-lab`).
2. Skonfigurowano adresację statyczną interfejsu LAN na `192.168.10.1`.
3. Zaktualizowano tablice routingu na Kontrolerze Domeny oraz stacji roboczej, ustawiając OPNsense jako domyślną bramę, co pozwala na pełną inspekcję ruchu.

![Konsola OPNsense] 
<img width="626" height="484" alt="image" src="https://github.com/user-attachments/assets/225753ec-6b84-4e78-80bf-0c75131ed0b4" />

---

## Etap 2: Budowa Kontrolera Domeny Active Directory (AD DS)

1. **Konfiguracja statycznego adresowania IP** na serwerze `DC01` oraz instalacja roli **Active Directory Domain Services (AD DS)**.
2. **Promocja serwera** do poziomu Kontrolera Domeny dla nowego lasu: `lab.local`.
3. Pomyślna weryfikacja operacji i logowanie na konto administratora domeny (`LAB\Administrator`).

![Promocja DC i status usług AD DS]
<img width="1021" height="835" alt="image" src="https://github.com/user-attachments/assets/5fcc7ac4-be9f-4750-9aab-2c2f52f1a504" />

---

## Etap 3: Struktura Organizacyjna i Podłączenie Stacji Roboczej

W celu zachowania dobrych praktyk zarządzania tożsamością, wdrożono logiczną strukturę jednostek organizacyjnych (OU) rozdzielającą konta użytkowników od stacji roboczych.
1. Utworzono dedykowane kontenery OU: `Firmowe_Konta` oraz podfolder `Stacje_Robocze`.
2. Stację roboczą Windows 10 przełączono z domyślnej grupy roboczej do domeny `lab.local` pod nową, ustandaryzowaną nazwą (`PC-CLIENT01`).

<img width="519" height="325" alt="image" src="https://github.com/user-attachments/assets/b3af9450-3f44-4cd2-a99e-45582be287a2" />

---

## Etap 4: Hardening GPO (Polityki Bezpieczeństwa)

Jednym z kluczowych wektorów ataków w sieciach korporacyjnych (np. ransomware, exfiltration) są zewnętrze nośniki pamięci. Wdrożono centralną politykę GPO blokującą dostęp do portów USB na stacjach końcowych.
1. Skonfigurowano obiekt GPO (`GPO_Hardening_BlockUSB`) podpięty pod OU `Stacje_Robocze`.
2. Aktywowano regułę: *All Removable Storage classes: Deny all access*.
3. Pomyślnie zweryfikowano działanie blokady na stacji roboczej po wykonaniu aktualizacji zasad (`gpupdate /force`) – system zwraca wyjątek "Odmowa dostępu".

<img width="911" height="735" alt="image" src="https://github.com/user-attachments/assets/8352ba30-220c-4660-8d21-fa157eafed05" />

---

## Etap 5: Implementacja Windows LAPS (Local Administrator Password Solution)

Aby zabezpieczyć środowisko przed atakami typu *Lateral Movement* oraz *Pass-the-Hash*, wyeliminowano problem statycznych, współdzielonych haseł lokalnych administratorów na stacjach roboczych.
1. Rozszerzono schemat bazy Active Directory (`Update-AdmPwdADSchema`) o nowe atrybuty do bezpiecznego przechowywania haseł.
2. Skonfigurowano politykę wymuszającą generowanie skomplikowanych, 16-znakowych haseł rotowanych automatycznie co 30 dni.
3. **Weryfikacja sukcesu:** Poniższy zrzut ekranu przedstawia odczyt wygenerowanego hasła stacji `PC-CLIENT01` bezpośrednio z atrybutu `ms-Mcs-AdmPwd` na Kontrolerze Domeny:

<img width="741" height="704" alt="image" src="https://github.com/user-attachments/assets/c32481e1-fd80-4381-a630-f338fc88c8bd" />

