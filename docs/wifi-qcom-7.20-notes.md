# WiFi-qcom RouterOS 7.20.8 — notatki praktyczne

Ten dokument zbiera wszystko co empirycznie ustaliliśmy o `interface wifi`
(wifi-qcom) w trybie LOCAL (bez CAPsMAN) na hAP ax3 / cAP ax z RouterOS 7.20.8.
Pomocniczo do skryptów `configs/2-hap-router.rsc` i `configs/3-cap-light-config.rsc`.

## Architektura

W RouterOS 7.13+ stary stos `wireless` został zastąpiony przez `interface wifi`
(wifi-qcom dla układów Qualcomm IPQ używanych w hAP ax3 / cAP ax). Nowe podejście:

- `/interface wifi security` — profile uwierzytelniania (WPA2/3, FT)
- `/interface wifi datapath` — gdzie ramki idą (bridge + VLAN)
- `/interface wifi configuration` — kompletna „personalność SSID" (mode, ssid, security, datapath, country)
- `/interface wifi` — fizyczne radia (wifi1, wifi2) i wirtualne AP (jako children master-interface)

## Kanoniczny model konfiguracji

```
[security profile]  ──┐
[datapath profile]  ──┼──► [configuration]  ──► /interface wifi (master + slaves)
[country/channel]   ──┘                              │
                                                     └──► /interface bridge port (PVID, frame-types)
                                                              │
                                                              └──► /interface bridge vlan (tagged ports)
```

## Pułapki 7.20.8 — zweryfikowane empirycznie na hAP ax3

### 1. country=Poland MUSI być PascalCase

`country=poland` (lowercase) podczas `/import` zwraca:
```
input does not match any value of country
```
i **wywala cały dalszy import bez wyraźnego błędu w logu**. Pierwsza linia
`/interface wifi configuration add ...` z lowercase country abortuje sekcję 19,
więc configurations + provisioning + capsman pozostają puste. Defconf SSID
zostaje aktywne.

Pre-deploy grep: `grep -n 'country=[a-z]' configs/*.rsc` — wszystkie matche
muszą być PascalCase.

### 2. Lokalny CAP→CAPsMAN bind broken

W 7.20.8 wifi-qcom CAPWAP handshake między lokalnym `interface wifi cap`
a `interface wifi capsman` na **TYM SAMYM urządzeniu** nie kończy się.
Radia stoją w stanie `MBI: no connection to CAPsMAN`. Wszystkie permutacje
(`capsman interfaces=bridge|vlan-mgmt`, `cap discovery-interfaces=...`,
`cap caps-man-addresses=10.20.10.1`, firewall self-loopback, reboot) → bez efektu.

**Rozwiązanie**: skip CAPsMAN dla lokalnych radii. Użyj `configuration.manager=local`
i przypisz `configuration=cfg-priv-XX` bezpośrednio na master radia. Multi-SSID
przez virtual slaves (`/interface wifi add master-interface=wifi1 ...`).

CAPsMAN może mieć sens tylko dla zdalnych cAP-ów — ale do testowania na
naszym setupie 1 hAP + 2 cAP zostaliśmy przy local mode na każdym AP.

### 3. Per-radio override-y są silniejsze niż configuration=

Defconf hAP ustawia per-radio:
```
configuration.ssid="MikroTik-XXXXXX"
configuration.mode=ap
security.passphrase="XXXXX"
security.authentication-types=wpa2-psk,wpa3-psk
security.ft=yes
security.ft-over-ds=yes
```

Te wartości NADPISUJĄ to co przychodzi z `configuration=cfg-priv-5g`. Czyli
radio dostaje cfg-priv-5g, ALE nadal nadaje `MikroTik-XXXXXX`.

**Naprawa** — `!`-syntax UNSET (nie ustawienie na pusty string!):
```routeros
/interface wifi set wifi1 \
    !configuration.ssid !configuration.mode \
    !security.passphrase !security.authentication-types \
    !security.ft !security.ft-over-ds
```

PUŁAPKA: `set wifi1 configuration.ssid=""` (z pustym stringiem) ustawia override
na pusty SSID — radio pokaże `SSID not set`. Trzeba `!.ssid` żeby USUNĄĆ
override i pozwolić cfg-priv-5g zadziałać.

### 4. Master radia: datapath SAM zarządza bridge port jako Dynamic

PIERWOTNIE myśleliśmy że trzeba master radia (wifi1, wifi2) dodawać statycznie
do `/interface bridge port`. Empiryczny test (10 maja 2026) udowodnił że jest
ODWROTNIE: datapath wifi-qcom z `datapath.bridge=bridge .vlan-id=20` SAM dodaje
master radio jako Dynamic bridge port po `enable`. Statyczny `/interface bridge
port add` BLOKUJE dynamiczny i ramki nie idą prawidłowo:

- klient asocjuje (widoczny w `wifi registration-table`)
- bridge host table widzi MAC klienta na wifi1 z VID=20 (poprawnie)
- DHCP serwer otrzymuje DISCOVER, wysyła OFFER (pojawia się lease w stanie 'offered')
- ALE klient nie odpowiada DHCPREQUEST (lease NIGDY nie staje się 'bound')

Naprawa: NIE dodawaj statycznie wifi1/wifi2 do bridge port. Czyść ewentualne
defconf wpisy i pozwól datapath dodać dynamicznie:

```routeros
:foreach iface in={"wifi1";"wifi2"} do={
    :foreach bp in=[/interface bridge port find where interface=$iface] do={
        /interface bridge port remove $bp
    }
}
# (nie ma `add` po tym — datapath sam dorobi)
```

Slaves (wifi1-guest, wifi2-guest) tak samo — datapath dodaje sam.

PUŁAPKI:
- `master-interface!=""` jako filter w cleanup (`/interface wifi find where ...`)
  matchuje też master radia, próba remove → `failure: not allowed to remove`.
  Filtruj po nazwach: `find where name="wifi1-guest"`.

### 4a. Defconf DHCP server konkuruje z dhcp-priv

Po fabrycznym resecie hAP defconf zawiera:
- `/ip address 192.168.88.1/24 interface=bridge`
- `/ip dhcp-server "defconf" interface=bridge`
- pool `default-dhcp` 192.168.88.10-254
- DHCP network 192.168.88.0/24

Skrypt który NIE usuwa defconf na początku zostawia ten DHCP serwer aktywny
na bridge. Klient wifi w VLAN 20 dostaje DWA DHCP OFFERs (jeden 192.168.88.x
z defconf, drugi 10.20.20.x z dhcp-priv) — gubi się, lease pozostaje 'offered'.

Naprawa: cleanup defconf NA POCZĄTKU skryptu, przed bridge:

```routeros
/ip dhcp-server remove [find where name="defconf"]
/ip dhcp-server network remove [find where comment="defconf"]
/ip pool remove [find where name="default-dhcp"]
/ip address remove [find where comment="defconf"]
/ip dns static remove [find where comment="defconf"]
```

### 5. `set disabled=no` ≠ `enable`

Po imporcie radia są `BOUND` (flag `B`) ale nie `RUNNING` (brak `R`).
Klienci nie asocjują, ramki nie płyną. `/interface wifi set $w disabled=no`
ustawia property ale **nie podnosi fizycznie radia**. Trzeba:

```routeros
/interface wifi enable $w
```

Po `enable`:
- 5GHz wchodzi w DFS check ~1 min
- 2.4GHz startuje natychmiast

Workaround dla zacietego stanu: `disable [find]; :delay 2s; enable [find]` —
restartuje wszystkie radia jednorazowo, eliminuje BOUND-bez-RUNNING.

### 6. wifi2 (2.4GHz) na hAP ax3 wymaga jawnej częstotliwości

W 7.20.8 auto-channel selection na 2.4GHz przy `country=Poland` często skutkuje
brakiem startu radia (BOUND, brak RUNNING). 5GHz startuje OK, 2.4GHz nie.

**Naprawa** — jawny kanał:
```routeros
/interface wifi set wifi2 channel.frequency=2437 channel.width=20mhz
```

(2437 = kanał 6, 20MHz = bez agregacji 40MHz która też potrafi blokować start)

Dopiero po jawnym kanale `/interface wifi enable wifi2` daje RUNNING.

### 7. LTE passthrough wyklucza service-mode na ether1

Patrz `configs/1-lhg-passthrough.rsc` i sekcje 12.5-bonus3 w skill
`mikrotik-rsc-config-audit`.

## Kanoniczna sekcja wifi w skrypcie hAP ax3

```routeros
# === Security profiles ===
:if ([:len [/interface wifi security find where name="sec-priv"]] = 0) do={
    /interface wifi security add name="sec-priv" \
        authentication-types=wpa2-psk,wpa3-psk \
        passphrase="<password>" \
        ft=yes ft-over-ds=yes ft-mobility-domain=0xa1b2
}
:if ([:len [/interface wifi security find where name="sec-open"]] = 0) do={
    /interface wifi security add name="sec-open" authentication-types=""
}

# === Datapath ===
:if ([:len [/interface wifi datapath find where name="dp-priv"]] = 0) do={
    /interface wifi datapath add name="dp-priv" bridge=bridge vlan-id=20 client-isolation=no
}
:if ([:len [/interface wifi datapath find where name="dp-guest"]] = 0) do={
    /interface wifi datapath add name="dp-guest" bridge=bridge vlan-id=40 client-isolation=yes
}

# === Configurations (po jednej per SSID per pasmo) ===
# UWAGA: country=Poland (PascalCase, NIE poland)
:if ([:len [/interface wifi configuration find where name="cfg-priv-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-priv-2g" ssid="Solej-priv" \
        mode=ap security=sec-priv datapath=dp-priv country=Poland
}
:if ([:len [/interface wifi configuration find where name="cfg-priv-5g"]] = 0) do={
    /interface wifi configuration add name="cfg-priv-5g" ssid="Solej-priv" \
        mode=ap security=sec-priv datapath=dp-priv country=Poland
}
:if ([:len [/interface wifi configuration find where name="cfg-guest-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-guest-2g" ssid="Solej-Guest" \
        mode=ap security=sec-open datapath=dp-guest country=Poland
}
:if ([:len [/interface wifi configuration find where name="cfg-guest-5g"]] = 0) do={
    /interface wifi configuration add name="cfg-guest-5g" ssid="Solej-Guest" \
        mode=ap security=sec-open datapath=dp-guest country=Poland
}

# === Cleanup virtual-AP po nazwach (master jest unremovable) ===
:foreach vname in={"wifi1-guest";"wifi2-guest"} do={
    :foreach w in=[/interface wifi find where name=$vname] do={
        /interface wifi remove $w
    }
}

# === Master radia: configuration + manager=local + UNSET defconf overrides ===
# wifi1 = 5GHz (hAP ax3), wifi2 = 2.4GHz
:if ([:len [/interface wifi find where name="wifi1"]] > 0) do={
    /interface wifi set wifi1 configuration=cfg-priv-5g configuration.manager=local
    /interface wifi set wifi1 \
        !configuration.ssid !configuration.mode \
        !security.passphrase !security.authentication-types \
        !security.ft !security.ft-over-ds
}
:if ([:len [/interface wifi find where name="wifi2"]] > 0) do={
    /interface wifi set wifi2 configuration=cfg-priv-2g configuration.manager=local
    /interface wifi set wifi2 \
        !configuration.ssid !configuration.mode \
        !security.passphrase !security.authentication-types \
        !security.ft !security.ft-over-ds
    # 2.4GHz w 7.20.8 wymaga jawnego kanału żeby ruszyć
    /interface wifi set wifi2 channel.frequency=2437 channel.width=20mhz
}

# === Slave virtual-AP ===
:if ([:len [/interface wifi find where name="wifi1-guest"]] = 0) do={
    /interface wifi add name=wifi1-guest master-interface=wifi1 configuration=cfg-guest-5g
}
:if ([:len [/interface wifi find where name="wifi2-guest"]] = 0) do={
    /interface wifi add name=wifi2-guest master-interface=wifi2 configuration=cfg-guest-2g
}

# === Master radia jako bridge port (jawny add — datapath nie auto-dodaje) ===
:foreach iface in={"wifi1";"wifi2"} do={
    :foreach bp in=[/interface bridge port find where interface=$iface] do={
        /interface bridge port remove $bp
    }
}
/interface bridge port add bridge=bridge interface=wifi1 pvid=20 frame-types=admit-all
/interface bridge port add bridge=bridge interface=wifi2 pvid=20 frame-types=admit-all

# === Restart radia żeby wymusić BOUND → RUNNING ===
:foreach w in=[/interface wifi find] do={ /interface wifi disable $w }
:delay 2s
:foreach w in=[/interface wifi find] do={ /interface wifi enable $w }
```

## Diagnostyka

Po imporcie sprawdź:

```routeros
# 1. Czy radia są RUNNING (flaga R, nie tylko B)
/interface wifi print
# Spodziewane: 0 MBR wifi1, 1 BR wifi1-guest, 2 MBR wifi2, 3 BR wifi2-guest

# 2. Czy SSID się zgadza (NIE MikroTik-XXXXXX)
/interface wifi print detail

# 3. Czy bridge port ma wifi1/wifi2 jako Dynamic-active (NIE Inactive)
/interface bridge port print where interface~"wifi"

# 4. Czy klienci asocjują
/interface wifi registration-table print

# 5. Czy DHCP wydaje IP klientom wifi
/ip dhcp-server lease print

# 6. Bridge host table — MAC klienta wifi musi być widoczny w VLAN 20
/interface bridge host print where vid=20
```

Jeśli klient asocjuje (`registration-table` pokazuje go), ale lease nie idzie:
- Sprawdź `bridge host print` — jeśli MAC klienta NIE ma → ramki nie wpadają
  do bridge → master radio nie jest poprawnym bridge port
- Sprawdź `bridge port print where interface~"wifi"` → jeśli wifi1/wifi2
  jako `Inactive` (`I`) → radio nie nadaje (BOUND-not-RUNNING) → enable cycle
- Sprawdź `frame-types` → musi być `admit-all`, NIE
  `admit-only-untagged-and-priority-tagged`

## 802.11r Fast Transition bez CAPsMAN

Dla małych deploy (≤5 AP) local mode + identyczne ustawienia security na każdym
AP wystarcza:
- ssid identyczne
- passphrase identyczne
- ft=yes
- ft-mobility-domain=0xa1b2 (lub inna 4-cyfrowa wartość, byle identyczna)
- ft-over-ds=yes (działa po air, nie wymaga DS w local mode)

Klient roamuje między AP bez powtórnego handshake'a. Bez identycznego
mobility-domain klient robi pełny re-auth (1-3s lag).

## Źródła

- https://help.mikrotik.com/docs/spaces/ROS/pages/224559147/WiFi (główna dokumentacja)
- https://help.mikrotik.com/docs/spaces/ROS/pages/85229843/Bridging+and+Switching (frame-types semantyka)
- forum.mikrotik.com — wyszukiwanie „wifi-qcom local mode bridge port master"
- Empirycznie zweryfikowane na hAP ax3 (C53UiG+5HPaxD2HPaxD), RouterOS 7.20.8 stable
