# Instalacja sieci LTE — Hotel (3 kondygnacje)

**Data:** 2026-04-13  
**Cel:** Wymiana instalacji LTE, ~200 Mb/s na telefonie vs 22 Mb/s na obecnym routerze — problem to stary modem (brak Carrier Aggregation).

---

## Podsumowanie

To jest mega zestaw potencjalnie na zawsze.
Oczywiście nie mamy wpływu na to co nam poda T-mobile ale to wyciągnie max, a nawet więcej bo multiplikuje kanały.

1. Antena i modem do 1200 Mb/s
https://www.mikrotik.org.pl/?produkt,9027
774,23 zł netto
2. Router z POE (dla anteny)
https://www.mikrotik.org.pl/?produkt,9285
393,09 zł netto
3. Access point albo repeater - 3 szt. (dwie na piętra jedna do domku)
https://www.mikrotik.org.pl/?produkt,9570
357,32 zł netto x 3 = 1071,96
4. Do domku zestaw
https://www.mikrotik.org.pl/?produkt,7646
833,82 zł netto

Razem
774,23 + 393,09 + 1071,96 + 833,82 = 3073,10 netto

## Schemat sieci

```
[Wieża BTS]
     │
[LHG LTE18 — antena zewnętrzna]
     │ PoE Ethernet
[Router — parter/recepcja]
     ├── cAP ax — piętro 1 (kabel)
     ├── cAP ax — piętro 2 (kabel)
     ├── cAP ax — mesh/repeater (bez kabla)
     └── SXT Lite5 ac ──(100m wireless)── SXT Lite5 ac — [Domek]
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
- Zarządzanie centralne przez **CAPsMAN v2** (RouterOS 7.x)
- Roaming hotelowy bez rozłączeń
- ~290–320 PLN/szt → **~600 PLN łącznie**

---

### 4. Zasięg w miejscu bez kabla
**MikroTik cAP ax** (tryb mesh/wireless backhaul)
- Ten sam model co AP-ki na piętrach
- CAPsMAN obsługuje wireless uplink natywnie (RouterOS 7.x)
- Nie wymaga kabla — backhaul przez Wi-Fi od sąsiedniego AP
- ~300 PLN

> **Alternatywa:** MikroTik wAP ac (~180 PLN) jako prosty repeater

---

### 5. Połączenie z domkiem (~100 m)
**MikroTik SXT Lite5 ac** × 2
- 5 GHz, point-to-point bridge
- 100 m to minimalny dystans dla tych anten (działają do 5+ km)
- Przepustowość efektywna: 100–200 Mb/s
- Konfiguracja: jeden w trybie AP bridge, drugi Station bridge
- ~185–200 PLN/szt → **~380 PLN za parę**

> **Alternatywa z wyższym zyskiem:** MikroTik LHG 5 ac × 2 (~250 PLN/szt)

---

### 6. Opcjonalnie — Switch PoE
**MikroTik CRS112-8P-4S-IN** (~400 PLN)
- Zasila wszystkie AP-ki z jednego miejsca (bez osobnych injektorów)
- Zarządzany switch — VLAN per port

> Alternatywnie: injektory PoE osobno (~50 PLN/szt × 3)

---

## Zestawienie kosztów

| Element | Model | Cena |
|---|---|---|
| Antena LTE zewnętrzna | LHG LTE18 kit | ~550 PLN |
| Router z Wi-Fi | hAP ax³ | ~400 PLN |
| cAP ax × 2 (piętra) | cAP ax | ~600 PLN |
| cAP ax × 1 (mesh) | cAP ax | ~300 PLN |
| Domek PtP × 2 | SXT Lite5 ac kit | ~380 PLN |
| **Razem bez switcha** | | **~2 230 PLN** |
| Switch PoE (opcja) | CRS112-8P-4S | +400 PLN |
| **Razem z switchem** | | **~2 630 PLN** |

---

## Uwagi praktyczne

- **SIM karta:** sprawdź APN i TTL — niektórzy operatorzy blokują routery. Play, Plus i Magenta mają dedykowane taryfy na routery
- **Kierunek anteny:** aplikacja **Network Cell Info** (Android) pokazuje kierunek i odległość do BTS
- **VLAN:** rozdziel sieć gości od sieci wewnętrznej hotelu (recepcja, monitoring, POS)
- **RouterOS 7.x:** wymagany dla CAPsMAN v2 i wireless mesh — upewnij się że wszystkie urządzenia mają aktualny firmware
- **Backup LTE:** MikroTik obsługuje failover na drugi slot SIM lub drugi modem — warto rozważyć

---

## Przydatne linki

- MikroTik CAPsMAN v2 docs: https://help.mikrotik.com/docs/display/ROS/CAPsMAN
- Network Cell Info (Play Store): wyszukaj "Network Cell Info Lite"
- MikroTik wiki PtP bridge: https://wiki.mikrotik.com/wiki/Bridge
