# Hotel Solej — Sieć LTE: Spec konfiguracji MikroTik

**Data:** 2026-05-09
**Lokalizacja:** Hotel Solej (3 kondygnacje + domek na ~100 m, domek na razie poza zakresem — brak sprzętu PtP)
**Status:** Spec zaakceptowana — gotowa do implementacji

---

## 1. Cel

Wymiana starej instalacji LTE na zestaw MikroTik z agregacją kanałów (LHG LTE18). Zapewnienie:

1. **Sieci prywatnej** dla właściciela.
2. **Sieci gościnnej** z captive portalem (hotspot, bez hasła, sesja 7 dni).
3. **Wydzielonej sieci dla kamer** (LAN dziś, WiFi w przyszłości — przygotowane, disabled).
4. **Zdalnego zarządzania** przez WireGuard "Back to Home" (macOS, iPhone, WinBox).

---

## 2. Sprzęt w zakresie

| Lp. | Model | Rola |
|---|---|---|
| 1 | MikroTik LHG LTE18 kit | Antena zewnętrzna + modem LTE Cat18 (passthrough) |
| 2 | MikroTik hAP ax³ | Router, firewall, DHCP, CAPsMAN, hotspot, VPN, WiFi parteru |
| 3 | MikroTik cAP ax × 2 | Access pointy na piętra 1 i 2 (managed by CAPsMAN) |

**Poza zakresem (na razie):** trzeci cAP ax (mesh/repeater), para SXT Lite5 ac (PtP do domku).

---

## 3. Architektura

```
[T-Mobile BTS]
       │ LTE Cat18 (publiczne IP od operatora)
       ▼
[LHG LTE18] ── tryb passthrough (LTE→Ethernet bridge, bez double-NAT)
       │ PoE Ethernet (zasilanie z hAP, jeden kabel)
       ▼ do ether1 (2.5GbE + PoE-out 24V passive)
[hAP ax³] ── router + NAT + firewall + DHCP + CAPsMAN + hotspot + VPN
       │
       │ ether1 (2.5GbE, PoE-out 24V) = WAN do LHG ▲
       │
       ├─ ether2 (trunk) ─► [cAP ax piętro 1]   (własny PoE injektor)
       ├─ ether3 (trunk) ─► [cAP ax piętro 2]   (własny PoE injektor)
       ├─ ether4 (access VLAN 30) ─► kamery / NVR
       └─ ether5 (1GbE) ─► wolny / laptop serwisowy
```

**Założenia:**
- LHG w **passthrough mode** — IP od operatora trafia bezpośrednio na hAP. Pojedynczy NAT.
- hAP = całe centrum decyzyjne (single source of truth).
- cAP ax provisioned przez CAPsMAN — wymiana sprzętu = zero ręcznej konfiguracji.
- **Bridge VLAN filtering** (RouterOS 7.21.4) — jeden bridge, VLANy rozdzielają strefy.

---

## 4. Schemat IP / VLAN

| VLAN | Nazwa | Podsieć | Gateway | DHCP pool | Cel |
|---|---|---|---|---|---|
| 10 | mgmt | 10.20.10.0/24 | 10.20.10.1 | .100–.199 | Zarządzanie (router + AP-ki) |
| 20 | priv | 10.20.20.0/24 | 10.20.20.1 | .100–.199 | Sieć właściciela (Solej-priv) |
| 30 | cams | 10.20.30.0/24 | 10.20.30.1 | .100–.199 | Kamery (LAN + Solej-Cams disabled) |
| 40 | guest | 10.20.40.0/24 | 10.20.40.1 | .50–.250 | Goście (Solej-Guest, hotspot) |

**WAN:** ether1 (2.5GbE z PoE-out 24V), DHCP client (publiczne IP od T-Mobile via LHG passthrough). LHG zasilana z PoE-out hAP, 2.5GbE link bez kompromisu.
**Back to Home VPN:** 192.168.66.0/24 (zarządzane przez chmurę MikroTika).

### Porty hAP ax³

**Specyfikacja PoE hAP ax³** (z mikrotik.com i opisu na obudowie): PoE-out tylko na **ether1** (passive PoE, 24V, max 0.625A ≈ 15W przy <30V). ether1 jest jednocześnie portem 2.5GbE.

| Port | Speed | PoE | Tryb | Rola |
|---|---|---|---|---|
| **ether1** | **2.5GbE** | **PoE-out 24V/15W** | WAN | **LHG LTE18** — zasilanie + dane jednym kablem |
| ether2 | 1GbE | brak | trunk (10,20,30,40 tagged) | cAP ax piętro 1 (własny PoE z zestawu cAP) |
| ether3 | 1GbE | brak | trunk (10,20,30,40 tagged) | cAP ax piętro 2 (własny PoE z zestawu cAP) |
| ether4 | 1GbE | brak | access VLAN 30 | NVR / switch kamer |
| ether5 | 1GbE | brak | wolny / serwisowy | Laptop diagnostyczny |
| wlan1/wlan2 | — | — | provisioned przez CAPsMAN | WiFi parteru (3 SSID) |

**Margines PoE:** ether1 max 15W przy 24V, LHG LTE18 pobór ~10–12W. OK z marginesem. Jeśli LHG resetuje się pod obciążeniem (rzadkie) — wracasz do PoE injektora z zestawu LHG.

### Porty cAP ax

- **ether1**: trunk (uplink) — VLAN 10 untagged, reszta tagged.
- **ether2**: access VLAN 20 (dla TV/PS5 w pokoju właściciela na piętrze).
- **wlan1/wlan2**: provisioned przez CAPsMAN, 3 SSID-y.

---

## 5. Wi-Fi i hotspot

### SSID-y (te same na wszystkich AP — roaming)

| SSID | Pasmo | Auth | VLAN | Stan startowy |
|---|---|---|---|---|
| `Solej-priv` | 2.4 + 5 GHz | WPA2/WPA3-PSK | 20 | enabled |
| `Solej-Guest` | 2.4 + 5 GHz | Open + Hotspot | 40 | enabled |
| `Solej-Cams` | 2.4 GHz only | WPA2-PSK | 30 | **disabled** |

### CAPsMAN

- Configuration profile per SSID (3 profile).
- Datapath per VLAN (3 datapathy z odpowiednim VLAN-id).
- Provisioning rule: nowy `cAPGi-5HaxD2HaxD` automatycznie dostaje wszystkie 3 SSID-y.
- Roaming: 802.11k/v/r natywnie (cAP ax wspiera).

### Hotspot dla `Solej-Guest`

```
Profil użytkownika "guest":
  - rate-limit: 30M/10M (per klient)
  - shared-users: 3
  - session-timeout: 7d
  - idle-timeout: 30m

Hotspot profile:
  - login-by: trial
  - trial-uptime-limit: 7d
  - trial-user-profile: guest
  - DNS: 1.1.1.1, 8.8.8.8
  - HTTPS login: TAK
```

**Strona logowania (login.html, PL):** krótki regulamin (RODO, odpowiedzialność operatora) + przycisk "Połącz".

### Izolacja gości

- L2: `client-isolation` na cAP-ach.
- L3: firewall blokuje guest→guest, guest→mgmt/priv/cams. Wyjątek: DNS/DHCP/hotspot na bramce.

---

## 6. Firewall

### INPUT (do routera)

```
✓ established/related → accept
✓ ICMP → accept (rate limited)
✓ z mgmt (10.20.10.0/24) → accept
✓ z priv (10.20.20.0/24) → accept
✓ z back-to-home-vpn → accept
✓ guest → 10.20.40.1 (DNS/DHCP/hotspot) → accept
✗ wszystko inne → drop + log
```

### FORWARD (przez router)

```
✓ established/related → accept
✗ invalid → drop
✓ priv → wszystko → accept
✓ mgmt → wszystko → accept
✓ back-to-home-vpn → mgmt/priv/cams → accept
✗ cams → WAN → drop
✓ cams → priv (responses only) → accept
✗ guest → guest → drop
✗ guest → mgmt/priv/cams → drop
✓ guest → WAN → accept (po zalogowaniu w hotspot)
✗ wszystko inne → drop
```

### NAT

```
masquerade out=ether1 (WAN/LTE), src=10.20.0.0/16
```

### Bezpieczeństwo

- WinBox/SSH/HTTPS/API tylko z mgmt, priv, back-to-home-vpn.
- Telnet/FTP/WWW/api-ssl wyłączone.
- Hasło admina przez placeholder.
- MAC-Server ograniczony do bridge mgmt.

---

## 7. VPN — MikroTik Back to Home

- WireGuard hub w chmurze MikroTik (dostępne od RouterOS 7.15, używamy 7.21.4).
- Konto na mikrotik.com (darmowe).
- Aktywacja: WinBox → IP → Cloud → Back To Home.
- Klient: aplikacja MikroTik na iPhone/Android (QR), WireGuard.app na macOS (.conf).
- Domyślna podsieć: 192.168.66.0/24.
- Skrypt RSC nie aktywuje VPN (wymaga interakcji), ale przygotowuje firewall i routing.

**Co dostajesz:**
- WinBox/SSH do hAP via 192.168.66.1.
- Dostęp do AP-ek przez 10.20.10.x.
- Dostęp do kamer przez 10.20.30.x.

---

## 8. Kolejność wdrożenia

1. **Przygotowanie:** firmware update do RouterOS **7.21.4** (aktualne stable) na każdym urządzeniu, reset to defaults.
2. **LHG LTE18:** włożyć SIM, import `1-lhg-passthrough.rsc`, weryfikacja sygnału.
3. **hAP ax³:** podłączyć LHG do ether1 (2.5GbE+PoE-out — zasili LHG), laptop tymczasowo do ether5 (1GbE), import `2-hap-router.rsc`, ping test, aktywacja Back to Home.
4. **cAP ax #1:** kabel ether1 do ether2 hAP, czekać na CAPsMAN.
5. **cAP ax #2:** analogicznie do ether3 hAP.
6. **Klient macOS/iPhone:** import konfiguracji WireGuard z routera.
7. **Walidacja:** speedtest, hotspot test, izolacja, roaming.

---

## 9. Pliki dostarczone

```
docs/superpowers/specs/2026-05-09-hotel-siec-design.md   ← ten dokument
configs/
  ├─ 1-lhg-passthrough.rsc          ← LHG LTE18
  ├─ 2-hap-router.rsc               ← hAP ax³ (główny config)
  ├─ 3-cap-light-config.rsc         ← cAP ax (opcjonalny, light)
  ├─ hotspot/
  │   └─ login.html                 ← strona logowania PL
  └─ README-wdrozenie.md            ← instrukcja krok po kroku
```

---

## 10. Co poza zakresem (do następnej iteracji)

- Mesh/repeater cAP ax #3 — jak będzie potrzebny zasięg w miejscach bez kabla.
- Para SXT Lite5 ac — most PtP do domku 100 m.
- Kamery WiFi — włączenie SSID `Solej-Cams` (jedna komenda po dokupieniu).
- Backup VPN (Tailscale lub własny WireGuard na VPS) — jeśli kiedyś chcesz niezależność od chmury MikroTik.
- User Manager / RADIUS dla hotspot z statystykami per gość — na razie trial wystarcza.

---

## 11. Placeholdery do wypełnienia przed importem

Templates `.rsc` mają placeholdery — wypełniane przez `render.sh` z `.env` (patrz `configs/README-wdrozenie.md`):

- `__PLACEHOLDER_PRIV_WIFI_PASSWORD__` — hasło Solej-priv (min. 12 znaków).
- `__PLACEHOLDER_CAMS_WIFI_PASSWORD__` — hasło Solej-Cams (włączysz później).
- `__PLACEHOLDER_ADMIN_PASSWORD__` — hasło admina routera (każde urządzenie ma własne).
- `__PLACEHOLDER_HAP_ETHER1_MAC__` — MAC ether1 hAP (do trybu passthrough LHG).
- `__PLACEHOLDER_APN__` — APN operatora LTE.
- `__PLACEHOLDER_IDENTITY__` — identity cAP-a (np. `cap-pietro1`).
