# Instalacja sieci LTE — Hotel (3 kondygnacje)

**Data:** 2026-04-13  
**Cel:** Wymiana instalacji LTE, ~200 Mb/s na telefonie vs 22 Mb/s na obecnym routerze — problem to stary modem (brak Carrier Aggregation).

---

## Podsumowanie

To jest mega zestaw potencjalnie na zawsze.
Oczywiście nie mamy wpływu na to co nam poda T-mobile ale to wyciągnie max, a nawet więcej bo multiplikuje kanały.

Zakres MVP (zgodnie ze spec `docs/superpowers/specs/2026-05-09-hotel-siec-design.md` sekcja 2 i 10):

1. Antena i modem do 1200 Mb/s
https://www.mikrotik.org.pl/?produkt,9027
774,23 zł netto
2. Router z POE (dla anteny)
https://www.mikrotik.org.pl/?produkt,9285
393,09 zł netto
3. Access point - 2 szt. (po jednym na piętro)
https://www.mikrotik.org.pl/?produkt,9570
357,32 zł netto x 2 = 714,64

Razem MVP
774,23 + 393,09 + 714,64 = 1881,96 netto

> **Poza zakresem MVP** (do następnej iteracji): 3-ci cAP ax (mesh/repeater bez kabla), para SXT Lite5 ac na most PtP do domku ~100 m. Patrz spec sekcja 10.

## Schemat sieci

```
[Wieża BTS]
     │
[LHG LTE18 — antena zewnętrzna]
     │ PoE Ethernet
[Router — parter/recepcja]
     ├── cAP ax — piętro 1 (kabel)
     └── cAP ax — piętro 2 (kabel)
```

---

## Sprzęt

### 1. Antena zewnętrzna LTE
**MikroTik LHG LTE18 kit**
- LTE Cat18, 4×4 MIMO, 5× Carrier Aggregation
- Antena kierunkowa dish 17 dBi
- Zintegrowany modem, zasilanie PoE przez kabel Ethernet
- Montaż na zewnątrz budynku, skierowana na najbliższą wieżę BTS
- ~550 PLN

> **Alternatywa budżetowa:** LHG LTE6 kit (~300 PLN) — Cat6, maks. 300 Mb/s teoretycznie

---

### 2. Router wewnętrzny
**MikroTik hAP ax³** (~400 PLN)
- WiFi 6 (802.11ax), 2.4 + 5 GHz
- Słabszy routing niż RB5009, ale wystarczający dla małego hotelu
- Pokrywa parter/recepcję → potrzeba tylko **2 dodatkowych cAP ax**

---

### 3. Access Pointy — 2 sztuki (piętra 1 i 2)
**MikroTik cAP ax** × 2
- WiFi 6 (802.11ax), 2.4 + 5 GHz
- Montaż sufitowy, zasilanie PoE
- Zarządzanie: lokalne kopie konfiguracji wifi na każdym AP, wspólny passphrase + 802.11r FT mobility-domain dla seamless roamingu między piętrami
- Roaming hotelowy bez rozłączeń
- ~290–320 PLN/szt → **~600 PLN łącznie**

---

### 4. Opcjonalnie — Switch PoE
**MikroTik CRS112-8P-4S-IN** (~400 PLN)
- Zasila wszystkie AP-ki z jednego miejsca (bez osobnych injektorów)
- Zarządzany switch — VLAN per port

> Alternatywnie: injektory PoE osobno (~50 PLN/szt × 3)

---

## Zestawienie kosztów (MVP)

| Element | Model | Cena |
|---|---|---|
| Antena LTE zewnętrzna | LHG LTE18 kit | ~550 PLN |
| Router z Wi-Fi | hAP ax³ | ~400 PLN |
| cAP ax × 2 (piętra) | cAP ax | ~600 PLN |
| **Razem bez switcha** | | **~1 550 PLN** |
| Switch PoE (opcja) | CRS112-8P-4S | +400 PLN |
| **Razem z switchem** | | **~1 950 PLN** |

> Pozycje poza zakresem MVP (3-ci cAP ax mesh, para SXT Lite5 ac do domku) — patrz spec sekcja 10.

---

## Uwagi praktyczne

- **SIM karta:** sprawdź APN i TTL — niektórzy operatorzy blokują routery. Play, Plus i Magenta mają dedykowane taryfy na routery
- **Kierunek anteny:** aplikacja **Network Cell Info** (Android) pokazuje kierunek i odległość do BTS
- **VLAN:** rozdziel sieć gości od sieci wewnętrznej hotelu (recepcja, monitoring, POS)
- **Backup LTE:** MikroTik obsługuje failover na drugi slot SIM lub drugi modem — warto rozważyć

---

## Przydatne linki

- MikroTik WiFi (lokalna konfiguracja) docs: https://help.mikrotik.com/docs/display/ROS/WiFi
- Network Cell Info (Play Store): wyszukaj "Network Cell Info Lite"
- MikroTik wiki PtP bridge: https://wiki.mikrotik.com/wiki/Bridge
