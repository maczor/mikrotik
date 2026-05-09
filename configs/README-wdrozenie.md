# Wdrożenie sieci Solej Hotel — instrukcja krok po kroku

**Stan na dzień:** 2026-05-09
**Sprzęt:** LHG LTE18 + hAP ax³ + 2× cAP ax
**RouterOS:** 7.21.4

---

## 0. Co przygotować przed startem

- Karta SIM T-Mobile (wyciągnięta z plastiku, sprawdzona w telefonie że łapie sieć)
- Laptop z WinBox (macOS: pobrać z mikrotik.com/download — działa pod Wine lub natywnie ARM build)
- Kabel Ethernet do podłączania urządzeń serwisowo
- Aplikacja **Network Cell Info Lite** na Androidzie (do celowania anteny w BTS)
- Konto na **mikrotik.com** (darmowe — założysz w 30s, potrzebne do Back to Home VPN)

---

## 1. Wypełnienie zmiennych przez `.env` + `render.sh`

Pliki `.rsc` w katalogu `configs/` to **templates** z placeholderami `__PLACEHOLDER_*__`.
Nie edytuj ich ręcznie. Zamiast tego — z **roota projektu** (gdzie leży `render.sh` i `.env.example`):

```bash
cp .env.example .env
chmod 600 .env                      # ważne - zawiera hasła
vi .env                             # wypełnij wartości
./render.sh --check                 # walidacja (czy wszystko uzupełnione)
./render.sh                         # generuje finalne pliki w out/
```

Po wykonaniu `render.sh` masz w `out/`:
```
out/
├── 1-lhg-passthrough.rsc      ← do wgrania na LHG
├── 2-hap-router.rsc           ← do wgrania na hAP ax³
├── 3-cap-pietro1.rsc          ← do wgrania na pierwszy cAP
└── 3-cap-pietro2.rsc          ← do wgrania na drugi cAP
```

Te pliki zawierają hasła w plain text — `chmod 600` automatycznie. **Po wgraniu na urządzenia usuń je** (`rm -f out/*.rsc` lub przenieś w bezpieczne miejsce).

**Zmienne w `.env`** (szczegóły w `.env.example`):

| Zmienna | Co wpisać |
|---|---|
| `LHG_ADMIN_PASSWORD`, `HAP_ADMIN_PASSWORD`, `CAP1_ADMIN_PASSWORD`, `CAP2_ADMIN_PASSWORD` | Hasła admina (osobne dla każdego urządzenia, **min. 16 znaków**) |
| `PRIV_WIFI_PASSWORD` | Hasło `Solej-priv` (min. 12 znaków) |
| `CAMS_WIFI_PASSWORD` | Hasło `Solej-Cams` (włączysz potem, min. 12 znaków) |
| `APN` | APN operatora. T-Mobile PL = `internet`, Play = `internet`, Plus = `plus` |
| `HAP_ETHER1_MAC` | MAC adres ether1 z hAP — pobierzesz w **kroku 3.3** |
| `CAP1_IDENTITY`, `CAP2_IDENTITY` | Nazwy cAP-ów (np. `cap-pietro1`, `cap-pietro2`) |

**Generowanie haseł:**
```bash
# macOS terminal:
openssl rand -base64 24 | tr -d '/+=' | head -c 20
```

**`HAP_ETHER1_MAC` poznasz dopiero w kroku 3.3** — wtedy wracasz, edytujesz `.env`, ponownie odpalasz `./render.sh`. To jedyna iteracja w workflow.

**`.env` jest w `.gitignore`** — nie commituj go.

---

## 2. Aktualizacja firmware (każde urządzenie z osobna)

Dla każdego z 4 urządzeń (LHG, hAP, cAP × 2):

1. Podłącz je przewodem do laptopa (osobno, jedno na raz)
2. WinBox → **Neighbors** → wybierz urządzenie → **Connect** (po MAC, login `admin`, hasło puste lub fabryczne)
3. **System → Packages** → sprawdź wersję
4. **System → Routerboard → Upgrade** (firmware bootloadera)
5. **System → Auto Upgrade** lub Files → upload paczki `.npk` z 7.21.4 → reboot
6. Po reboocie: **System → Routerboard → Settings → Boot Device** = `flash` (nie nand fallback)
7. Sprawdź `/system resource print` → version: 7.21.4

Pobranie .npk: https://mikrotik.com/download
- LHG LTE18: arch `ARM`, package `routeros-7.21.4-arm.npk` + `wireless-7.21.4-arm.npk`
- hAP ax³: arch `ARM64`, package `routeros-7.21.4-arm64.npk` + `wifi-7.21.4-arm64.npk`
- cAP ax: arch `ARM64`, package `routeros-7.21.4-arm64.npk` + `wifi-7.21.4-arm64.npk`

---

## 3. Konfiguracja hAP ax³ (zaczynamy od centrum)

### 3.1. Przygotowanie

1. Włóż kartę SIM do LHG (jeszcze nie podłączamy LHG)
2. Podłącz hAP do prądu (zasilacz w zestawie)
3. Podłącz **laptop do ether5 hAP** (nie ether1!) kablem Ethernet
4. Laptop dostanie tymczasowo IP w sieci 192.168.88.x (default config) lub 0.0.0.0 (po reset)
5. WinBox → **Neighbors** → wybierz hAP → **Connect** po MAC

### 3.2. Reset to defaults BEZ default config

```
/system reset-configuration no-defaults=yes skip-backup=yes
```

Router zrestartuje się. Po ~60s podłącz ponownie WinBox po MAC. Logowanie: `admin`, hasło puste.

### 3.3. Pobranie MAC adresu ether1

W terminalu hAP:

```
/interface ethernet print
```

Skopiuj MAC z linii `ether1` (format `XX:XX:XX:XX:XX:XX`). Wpisz go do `.env` jako `HAP_ETHER1_MAC` i ponownie odpal — z **roota projektu** (gdzie leży `render.sh`):

```bash
vi .env                  # ustaw HAP_ETHER1_MAC
./render.sh              # wygeneruj na nowo
```

### 3.4. Wgranie strony hotspot

1. WinBox → **Files** → otwórz folder `flash/`
2. Utwórz folder `hotspot` (klik prawym → Create Directory)
3. Drag & drop pliku `hotspot/login.html` z laptopa do folderu `hotspot` w WinBox

### 3.5. Wgranie i import skryptu

1. WinBox → **Files** → drag & drop **`out/2-hap-router.rsc`** (do roota, nie do `hotspot/`)
2. Otwórz **Terminal** w WinBox
3. Wykonaj **dry-run** żeby sprawdzić syntax:
   ```
   /import file-name=2-hap-router.rsc verbose=yes dry-run
   ```
   Jeśli nie ma błędów, idź dalej:
4. Wykonaj prawdziwy import:
   ```
   /import file-name=2-hap-router.rsc verbose=yes
   ```
5. Po imporcie **stracisz chwilowo łączność** (włącza się VLAN filtering). To normalne. Odczekaj 10-15s, po czym laptop dostanie nowe IP w sieci `10.20.20.0/24` (priv VLAN przez ether5).
6. Zaloguj się ponownie: WinBox do `10.20.20.1`, login `admin`, hasło które ustawiłeś.

### 3.6. Aktywacja Back to Home VPN

1. WinBox → **IP → Cloud → Back To Home**
2. Kliknij **Enable**
3. W przeglądarce otwórz mikrotik.com (jeśli nie masz konta — załóż)
4. WinBox pokaże QR code i nazwę użytkownika
5. **Na iPhone/Android:** zainstaluj aplikację **MikroTik** (z App Store / Play). Otwórz, zaloguj się tym samym kontem mikrotik.com. Zobaczysz router w aplikacji — możesz dodać urządzenie do BtH (klik "Connect to Back to Home").
6. **Na macOS:** zainstaluj **WireGuard.app** (z Mac App Store). W routerze WinBox → IP → Cloud → Back To Home → przycisk "Show config" — skopiuj/skanuj QR. W WireGuard.app: Add Tunnel → Add Empty Tunnel → wklej config → Activate.

### 3.7. Weryfikacja hAP

```
/interface print                         # bridge, vlan-mgmt/priv/cams/guest, ether1-5
/ip address print                        # 4 adresy 10.20.X.1/24 + WAN dynamic z LTE
/ip dhcp-server lease print              # gdy podłączysz urządzenia, pokażą się tu
/interface wifi capsman print            # enabled=yes
/ip hotspot print                        # hotspot-guest active=yes
/log print where topics~"capsman|hotspot"  # logi
```

---

## 4. Konfiguracja LHG LTE18

### 4.1. Pierwsza próba — antena na ziemi

1. Karta SIM już włożona (krok 3.1)
2. Podłącz LHG do laptopa kablem Ethernet (zasilacz PoE z zestawu LHG, na razie nie z hAP)
3. WinBox → Neighbors → wybierz LHG → Connect po MAC
4. Reset:
   ```
   /system reset-configuration no-defaults=yes skip-backup=yes
   ```
5. Po reboocie podłącz ponownie. Sprawdź sygnał LTE:
   ```
   /interface lte info [find] once
   ```
   - `status: registered, network`
   - `signal-strength: -90 dBm` lub lepszy (im bliżej zera, tym lepiej)
   - `band: B1 / B3 / B7 / B8 / B20` itd. (T-Mobile PL używa głównie B3, B7, B20)

Jeśli signal poniżej -110 dBm — antena w niewłaściwym kierunku albo brak zasięgu. Skieruj antenę używając Network Cell Info Lite na androidzie.

### 4.2. Wgranie i import skryptu

1. Sprawdź czy `HAP_ETHER1_MAC` w `.env` ma poprawny adres (krok 3.3) i wygenerowałeś `out/1-lhg-passthrough.rsc` przez `./render.sh`
2. WinBox → Files → drag & drop `out/1-lhg-passthrough.rsc`
3. Terminal:
   ```
   /import file-name=1-lhg-passthrough.rsc verbose=yes dry-run
   /import file-name=1-lhg-passthrough.rsc verbose=yes
   ```
4. Po imporcie LHG przejdzie w tryb passthrough — stracisz IP.

### 4.3. Montaż docelowy

1. Wnieś LHG na dach / ścianę zewnętrzną. Skieruj na BTS.
2. Połącz kabel ethernet (kategorii min. CAT5e, lepiej CAT6) z LHG → **ether1 hAP** (PoE-out 24V z hAP zasili LHG).
3. Po ~60s hAP dostanie publiczne IP od T-Mobile na ether1.
4. Sprawdź na hAP: `/ip address print` — ether1 ma IP z DHCP (np. 10.x lub 100.64.x).
5. Speedtest: `/tool speed-test address=speedtest.t-mobile.pl` lub po prostu `ping 1.1.1.1`.

---

## 5. Konfiguracja cAP ax (× 2)

Dla każdego cAP osobno (najpierw piętro 1, potem piętro 2):

### 5.1. Reset i firmware

1. Podłącz cAP do laptopa (zasilacz PoE z zestawu cAP)
2. WinBox → MAC, reset:
   ```
   /system reset-configuration no-defaults=yes skip-backup=yes
   ```
3. Firmware update (jeśli nie zrobiłeś w kroku 2)

### 5.2. Wgranie i import skryptu

1. Wgrywasz odpowiedni plik:
   - `out/3-cap-pietro1.rsc` → na pierwszy cAP (piętro 1)
   - `out/3-cap-pietro2.rsc` → na drugi cAP (piętro 2)
2. Files → drag & drop pliku
3. Terminal (zauważ: nazwa pliku różni się dla każdego):
   ```
   /import file-name=3-cap-pietro1.rsc verbose=yes dry-run
   /import file-name=3-cap-pietro1.rsc verbose=yes
   ```
4. Po imporcie cAP się skonfiguruje. Stracisz lokalną łączność.

### 5.3. Montaż i połączenie

1. cAP na sufit / ścianę na piętrze 1
2. Kabel: ether1 cAP → **ether2 hAP** (dla piętra 1) lub **ether3 hAP** (dla piętra 2)
3. Zasilanie: PoE injektor cAP wpięty w gniazdko + jego port LAN do kabla
4. Czekaj ~60s

### 5.4. Sprawdzenie na hAP

W WinBox hAP → terminal:

```
/interface wifi capsman remote-cap print
```

Powinieneś zobaczyć cAP-a jako `running`. Jeśli go nie ma:

```
/log print where topics~"capsman" 
```

i sprawdź co się dzieje (zwykle DHCP na vlan-mgmt nie poszedł — wtedy cAP nie ma IP w 10.20.10.x).

### 5.5. Powtórz dla drugiego cAP

Identycznie, identity = `cap-pietro2`, kabel do ether3 hAP.

---

## 6. Walidacja całości

### 6.1. WiFi

- Telefon → WiFi → szukaj `Solej-priv`. Połącz się hasłem.
- Sprawdź speed test (cel: >100 Mb/s w pobliżu AP, >50 Mb/s w pokoju)
- Telefon → WiFi → szukaj `Solej-Guest` → połącz (bez hasła)
- Powinien otworzyć się **captive portal** (strona logowania w przeglądarce). Akceptuj regulamin → masz internet.
- Po 7 dniach (lub po `/ip hotspot active remove [find]` dla testów) → ponownie zobaczysz portal

### 6.2. Roaming

Idź z telefonem przez budynek. Sygnał powinien przechodzić z AP na AP bez rozłączania.

### 6.3. Izolacja

- Z telefonem na `Solej-Guest` spróbuj otworzyć `http://10.20.10.1` lub `http://10.20.20.1` — **musi się NIE udać** (firewall blokuje)
- Z telefonem na `Solej-priv` — `http://10.20.10.1` **musi działać** (WinBox / WebFig)

### 6.4. Kamery

- Po wpięciu kamery do ether4 hAP — kamera dostanie IP w 10.20.30.0/24
- Z `Solej-priv` wejdziesz na kamerę po IP — działa
- Próba połączenia z kamery do internetu — zablokowana (firewall)

### 6.5. VPN (Back to Home)

- Wyjdź z hotelu (zostaw siec w domu, połącz się przez LTE telefonu)
- Aktywuj WireGuard tunnel na Mac/iPhone
- WinBox / SSH / przeglądarka → `192.168.66.1` (gateway Back to Home) → masz dostęp do hAP
- Możesz wejść na AP-ki przez `10.20.10.x`, na kamery przez `10.20.30.x`

---

## 7. Rozwiązywanie problemów

| Symptom | Co sprawdzić |
|---|---|
| Brak internetu w `Solej-priv` | `/ip address print` na hAP — ether1 ma IP? Jeśli nie, LHG nie przekazuje passthrough — sprawdź MAC w skrypcie LHG |
| `Solej-Guest` widoczne ale brak captive portal | `/ip hotspot active print` — czy klient się rejestruje? Sprawdź `/ip hotspot host print` |
| cAP nie pokazuje się w CAPsMAN | Sprawdź `/log print` na cAP — czy dostał IP? Czy na hAP `vlan-mgmt` ma adres 10.20.10.1? |
| Słaby sygnał LTE (<-100 dBm) | Skieruj antenę dokładniej. Sprawdź band (jeden CA może być słabszy) |
| Back to Home nie aktywuje | Konto MikroTik niepotwierdzone? Sprawdź mail. Cloud `enabled=yes`? |

---

## 8. Co dalej

Kiedy będziesz chciał:

- **Dokupić kamery WiFi** → włącz SSID Solej-Cams: `/interface wifi configuration enable cfg-cams-2g`
- **Dodać 3-ci cAP w mesh** → kup cAP ax, zaaplikuj `3-cap-light-config.rsc` z identity `cap-mesh`. Provisioning automatyczny.
- **Dodać domek przez PtP** → kup parę SXT Lite5 ac, osobny config. To dodatkowy projekt.
- **Statystyki gości** → User Manager + RADIUS, zamiast trial mode (większa zmiana w hAP config).

---

## 9. Backup po wdrożeniu

Po zwalidowaniu, zrób backup każdego urządzenia:

```
/export file=hap-solej-prod-2026-05-09 show-sensitive=no
/system backup save name=hap-solej-prod-2026-05-09
```

Pobierz oba pliki na laptopa (Files → drag out). Trzymaj w bezpiecznym miejscu (np. zaszyfrowany dysk + chmura).
