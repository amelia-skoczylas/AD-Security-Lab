# AD-Security-Lab: Hardening Active Directory & LAPS Deployment

Projekt laboratoryjny z zakresu cyberbezpieczeństwa (Blue Team / Systems Engineering) symulujący środowisko korporacyjne oparte na Windows Server 2022 oraz Windows 10 Pro. Cel projektu obejmuje budowę domeny Active Directory, implementację polityk zabezpieczeń GPO (Hardening) oraz wdrożenie mechanizmu Windows LAPS chroniącego przed atakami typu *Lateral Movement*.

##  Architektura Laboratorium i Topologia Sieci

Środowisko zostało zbudowane w oparciu o wirtualizator Oracle VirtualBox z wykorzystaniem izolowanej sieci wirtualnej (`ad-lab`).

| Maszyna wirtualna | Rola w sieci | System operacyjny | Adres IP | DNS Server |
| :--- | :--- | :--- | :--- | :--- |
| **DC01** | Kontroler Domeny (`lab.local`), DNS Server | Windows Server 2022 Standard (Desktop Experience) | `192.168.10.10` | `127.0.0.1` / `192.168.10.10` |
| **AD-Client** | Stacja robocza (Domain Member) | Windows 10 Pro | `192.168.10.20` | `192.168.10.10` |

### Weryfikacja komunikacji sieciowej
Poniższy zrzut ekranu przedstawia pomyślną weryfikację połączenia (ICMP Ping) pomiędzy stacją roboczą a Kontrolerem Domeny wewnątrz izolowanej podsieci:

![Test połączenia Ping]
<img width="991" height="642" alt="image" src="https://github.com/user-attachments/assets/0797bd1b-646a-4ba2-9a08-c0987c42ed03" />

## Etap 1: Budowa Kontrolera Domeny Active Directory (AD DS)

1. **Konfiguracja statycznego adresowania IP** na serwerze `DC01` oraz instalacja roli **Active Directory Domain Services (AD DS)**.
2. **Promocja serwera** do poziomu Kontrolera Domeny dla nowego lasu: `lab.local`.
3. Pomyślna weryfikacja operacji i logowanie na konto administratora domeny (`LAB\Administrator`).

![Promocja DC i status usług AD DS]
<img width="1021" height="835" alt="image" src="https://github.com/user-attachments/assets/5fcc7ac4-be9f-4750-9aab-2c2f52f1a504" />

---

## Etap 2: Struktura Organizacyjna i Podłączenie Stacji Roboczej

<img width="519" height="325" alt="image" src="https://github.com/user-attachments/assets/b3af9450-3f44-4cd2-a99e-45582be287a2" />

---

## Etap 3: Hardening GPO (Polityki Bezpieczeństwa)

<img width="911" height="735" alt="image" src="https://github.com/user-attachments/assets/8352ba30-220c-4660-8d21-fa157eafed05" />

---

## Etap 4: Implementacja Windows LAPS (Local Administrator Password Solution)
*(Ten etap uzupełnimy na samym końcu z głównym dowodem na rotację haseł)*
