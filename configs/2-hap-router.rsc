# =============================================================================
# hAP ax3 — Solej Hotel (router główny)
# Rola: router LTE + DHCP + DNS + firewall + lokalne wifi (parter) + hotspot + VPN
# RouterOS: 7.20.8+
#
# PRZED IMPORTEM:
#   1. Reset to defaults BEZ default config (System -> Reset Configuration ->
#      "No Default Configuration").
#   2. Update firmware do 7.20.8 + RouterBOOT.
#   3. Wgraj plik hotspot/login.html do Files (drag & drop) PRZED importem
#      (skrypt do niego się odwołuje).
#   4. Podmień placeholdery:
#        __PLACEHOLDER_ADMIN_PASSWORD__       -> hasło admina
#        __PLACEHOLDER_PRIV_WIFI_PASSWORD__   -> hasło Solej-priv
#        __PLACEHOLDER_CAMS_WIFI_PASSWORD__   -> hasło Solej-Cams (na zapas)
#   5. Podłącz laptop do ether5 (access VLAN 20 -> dostaniesz IP 10.20.20.x).
#   6. WinBox/SSH przez aktualne IP/MAC, otwórz terminal.
#
# IMPORT:
#   /import file-name=2-hap-router.rsc verbose=yes
#
# PO IMPORCIE:
#   - Stracisz chwilowo łączność (włącza się VLAN filtering) — przeloguj.
#   - Aktywuj VPN: WinBox -> IP -> Cloud -> Back to Home -> zaloguj konto
#     mikrotik.com -> Enable. Aplikacja na telefon: skanuj QR.
#   - Sprawdź: /interface print (lista bridge/vlan), /ip address print,
#     /interface wifi print, /interface wifi registration-table print
# =============================================================================

:log info "hAP-Solej: start konfiguracji"

# === 1. Identity, czas, hasło ===============================================
/system identity set name="hap-solej-rtr"
/system clock set time-zone-name=Europe/Warsaw
/system note set show-at-login=no note=""
/user set [find name="admin"] password="__PLACEHOLDER_ADMIN_PASSWORD__"

# === 2. Bridge główny (vlan-filtering = na razie OFF) =======================
:if ([:len [/interface bridge find where name="bridge"]] = 0) do={
    /interface bridge add name="bridge" \
        protocol-mode=rstp \
        vlan-filtering=no \
        comment="Solej main bridge"
}

# === 3. Bridge ports =========================================================
# ether1 = WAN (NIE dołączamy do bridge, jest WAN-em)
# ether2, ether3 = trunki do cAP-ów (mgmt untagged, reszta tagged)
# ether4 = access VLAN 30 (kamery/NVR)
# ether5 = access VLAN 20 (serwis/laptop)
# Czyścimy WSZYSTKIE porty z DOWOLNEGO bridge'a (default config / poprzedni import).
# To jest agresywne ale konieczne — w przeciwnym razie `add` wywala się gdy port
# jest już w innym bridge.
:foreach iface in={"ether2";"ether3";"ether4";"ether5"} do={
    :foreach bp in=[/interface bridge port find where interface=$iface] do={
        /interface bridge port remove $bp
    }
}
/interface bridge port add bridge=bridge interface=ether2 pvid=10 \
    comment="solej-mgr: trunk -> cAP pietro 1 (mgmt VLAN 10 native)"
/interface bridge port add bridge=bridge interface=ether3 pvid=10 \
    comment="solej-mgr: trunk -> cAP pietro 2 (mgmt VLAN 10 native)"
/interface bridge port add bridge=bridge interface=ether4 pvid=30 \
    frame-types=admit-only-untagged-and-priority-tagged \
    comment="solej-mgr: access VLAN 30 -> NVR/kamery"
/interface bridge port add bridge=bridge interface=ether5 pvid=20 \
    frame-types=admit-only-untagged-and-priority-tagged \
    comment="solej-mgr: access VLAN 20 -> serwis/laptop"

# === 4. Bridge VLAN table ===================================================
/interface bridge vlan remove [find where bridge="bridge"]
/interface bridge vlan add bridge=bridge vlan-ids=10 \
    tagged=bridge untagged=ether2,ether3 \
    comment="solej-mgr: VLAN 10 mgmt (native na trunkach)"
/interface bridge vlan add bridge=bridge vlan-ids=20 \
    tagged=bridge,ether2,ether3 untagged=ether5 \
    comment="solej-mgr: VLAN 20 priv (Solej-priv)"
/interface bridge vlan add bridge=bridge vlan-ids=30 \
    tagged=bridge,ether2,ether3 untagged=ether4 \
    comment="solej-mgr: VLAN 30 cams (Solej-Cams)"
/interface bridge vlan add bridge=bridge vlan-ids=40 \
    tagged=bridge,ether2,ether3 \
    comment="solej-mgr: VLAN 40 guest (Solej-Guest hotspot)"

# === 5. VLAN interfaces (nad bridge) ========================================
:if ([:len [/interface vlan find where name="vlan-mgmt"]] = 0) do={
    /interface vlan add name="vlan-mgmt"  vlan-id=10 interface=bridge
}
:if ([:len [/interface vlan find where name="vlan-priv"]] = 0) do={
    /interface vlan add name="vlan-priv"  vlan-id=20 interface=bridge
}
:if ([:len [/interface vlan find where name="vlan-cams"]] = 0) do={
    /interface vlan add name="vlan-cams"  vlan-id=30 interface=bridge
}
:if ([:len [/interface vlan find where name="vlan-guest"]] = 0) do={
    /interface vlan add name="vlan-guest" vlan-id=40 interface=bridge
}

# === 6. Interface lists =====================================================
:foreach lname in={"WAN";"LAN";"MGMT";"PRIV";"CAMS";"GUEST";"VPN"} do={
    :if ([:len [/interface list find where name=$lname]] = 0) do={
        /interface list add name=$lname
    }
}
# Czyścimy WSZYSTKIE wpisy z naszych list (też te z default config, bez taggu)
:foreach lname in={"WAN";"LAN";"MGMT";"PRIV";"CAMS";"GUEST";"VPN"} do={
    :foreach m in=[/interface list member find where list=$lname] do={
        /interface list member remove $m
    }
}
/interface list member add list="WAN"   interface=ether1     comment="solej-mgr"
/interface list member add list="LAN"   interface=vlan-mgmt  comment="solej-mgr"
/interface list member add list="LAN"   interface=vlan-priv  comment="solej-mgr"
/interface list member add list="LAN"   interface=vlan-cams  comment="solej-mgr"
/interface list member add list="LAN"   interface=vlan-guest comment="solej-mgr"
/interface list member add list="MGMT"  interface=vlan-mgmt  comment="solej-mgr"
/interface list member add list="PRIV"  interface=vlan-priv  comment="solej-mgr"
/interface list member add list="CAMS"  interface=vlan-cams  comment="solej-mgr"
/interface list member add list="GUEST" interface=vlan-guest comment="solej-mgr"
# WireGuard "Back to Home" interface zostanie dodany automatycznie po
# aktywacji w GUI - dorzucimy go do listy VPN przez scheduler na końcu.

# === 7. IP addressing =======================================================
/ip address remove [find where comment~"solej-mgr"]
/ip address add address=10.20.10.1/24 interface=vlan-mgmt  comment="solej-mgr: mgmt gw"
/ip address add address=10.20.20.1/24 interface=vlan-priv  comment="solej-mgr: priv gw"
/ip address add address=10.20.30.1/24 interface=vlan-cams  comment="solej-mgr: cams gw"
/ip address add address=10.20.40.1/24 interface=vlan-guest comment="solej-mgr: guest gw"

# === 8. WAN: DHCP client na ether1 (LHG passthrough) ========================
:if ([:len [/ip dhcp-client find where interface=ether1]] = 0) do={
    /ip dhcp-client add interface=ether1 disabled=no \
        use-peer-dns=no use-peer-ntp=no \
        comment="WAN/LTE od LHG passthrough"
}

# === 9. DHCP servery ========================================================
# Pool-e
:foreach p in={
    {name="pool-mgmt";  range="10.20.10.100-10.20.10.199"};
    {name="pool-priv";  range="10.20.20.100-10.20.20.199"};
    {name="pool-cams";  range="10.20.30.100-10.20.30.199"};
    {name="pool-guest"; range="10.20.40.50-10.20.40.250"}
} do={
    :if ([:len [/ip pool find where name=($p->"name")]] = 0) do={
        /ip pool add name=($p->"name") ranges=($p->"range")
    }
}

# Servery
:if ([:len [/ip dhcp-server find where name="dhcp-mgmt"]] = 0) do={
    /ip dhcp-server add name="dhcp-mgmt"  interface=vlan-mgmt  address-pool="pool-mgmt"  lease-time=1d  disabled=no
}
:if ([:len [/ip dhcp-server find where name="dhcp-priv"]] = 0) do={
    /ip dhcp-server add name="dhcp-priv"  interface=vlan-priv  address-pool="pool-priv"  lease-time=1d  disabled=no
}
:if ([:len [/ip dhcp-server find where name="dhcp-cams"]] = 0) do={
    /ip dhcp-server add name="dhcp-cams"  interface=vlan-cams  address-pool="pool-cams"  lease-time=1d  disabled=no
}
:if ([:len [/ip dhcp-server find where name="dhcp-guest"]] = 0) do={
    /ip dhcp-server add name="dhcp-guest" interface=vlan-guest address-pool="pool-guest" lease-time=2h disabled=no
}

# DHCP networks (gateway + DNS)
/ip dhcp-server network remove [find where comment~"solej-mgr"]
/ip dhcp-server network add address=10.20.10.0/24 gateway=10.20.10.1 dns-server=10.20.10.1 comment="solej-mgr: mgmt"
/ip dhcp-server network add address=10.20.20.0/24 gateway=10.20.20.1 dns-server=10.20.20.1 comment="solej-mgr: priv"
/ip dhcp-server network add address=10.20.30.0/24 gateway=10.20.30.1 dns-server=10.20.30.1 comment="solej-mgr: cams"
# guest dostaje publiczne DNS (nie nasze) - mniej cache'owania, RODO friendly
/ip dhcp-server network add address=10.20.40.0/24 gateway=10.20.40.1 dns-server=1.1.1.1,8.8.8.8 comment="solej-mgr: guest"

# === 10. DNS server lokalny ================================================
/ip dns set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes

# === 11. NTP ================================================================
/system ntp client set enabled=yes servers="pl.pool.ntp.org,europe.pool.ntp.org"

# === 12. NAT (masquerade na WAN) ============================================
# Reguły taggowane "solej-mgr:" - kolejne uruchomienie skryptu wyczyści tylko nasze
/ip firewall nat remove [find where comment~"solej-mgr"]
/ip firewall nat add chain=srcnat action=masquerade out-interface=ether1 \
    src-address=10.20.0.0/16 comment="solej-mgr: LAN -> WAN/LTE"
# (poprzednia wersja miała tu drugą regułę masquerade out-interface=vlan-guest
# z komentarzem "hotspot hairpin" — w MikroTik hotspot redirect działa bez tego,
# a niepotrzebny SRC-NAT na interfejsie LAN tylko myli debugowanie. Usunięte.)

# === 13. Firewall: INPUT ====================================================
/ip firewall filter remove [find where comment~"solej-mgr"]

/ip firewall filter add chain=input action=accept connection-state=established,related,untracked \
    comment="solej-mgr: established/related/untracked"
/ip firewall filter add chain=input action=drop connection-state=invalid \
    comment="solej-mgr: invalid"
/ip firewall filter add chain=input action=accept protocol=icmp limit=50,5:packet \
    comment="solej-mgr: icmp limited"

# Zarządzanie z LAN ustawione przez interface lists
/ip firewall filter add chain=input action=accept in-interface-list=MGMT \
    comment="solej-mgr: admin z mgmt VLAN"
/ip firewall filter add chain=input action=accept in-interface-list=PRIV \
    comment="solej-mgr: admin z priv VLAN"
/ip firewall filter add chain=input action=accept in-interface-list=VPN \
    comment="solej-mgr: admin z VPN (Back to Home)"

# Goście: tylko DNS + DHCP + hotspot (do gateway)
/ip firewall filter add chain=input action=accept in-interface-list=GUEST \
    protocol=udp dst-port=53,67 comment="solej-mgr: guest DNS/DHCP"
/ip firewall filter add chain=input action=accept in-interface-list=GUEST \
    protocol=tcp dst-port=53,80,443,64872,64873 comment="solej-mgr: guest DNS/hotspot"

# Drop wszystkiego innego
/ip firewall filter add chain=input action=drop comment="solej-mgr: drop all other input"

# === 14. Firewall: FORWARD =================================================
# Kolejność: fasttrack PRZED accept established/related — accept jest terminalny,
# więc gdyby był pierwszy, pakiety nie dotarłyby do fasttrack i hw-offload by
# nigdy nie zadziałał. Default config MikroTika ma ten sam porządek.
/ip firewall filter add chain=forward action=fasttrack-connection \
    connection-state=established,related hw-offload=yes comment="solej-mgr: fasttrack"
/ip firewall filter add chain=forward action=accept connection-state=established,related,untracked \
    comment="solej-mgr: established/related/untracked"
/ip firewall filter add chain=forward action=drop connection-state=invalid \
    comment="solej-mgr: invalid"

# Kamery: DROP do internetu (mają być offline)
/ip firewall filter add chain=forward action=drop in-interface-list=CAMS \
    out-interface-list=WAN comment="solej-mgr: cams nie wychodzą do WAN"

# Goście: ZAKAZ klient-klient, ZAKAZ do innych VLANów (LAN-isolation)
/ip firewall filter add chain=forward action=drop in-interface-list=GUEST \
    out-interface-list=GUEST comment="solej-mgr: guest <-> guest BLOCK"
/ip firewall filter add chain=forward action=drop in-interface-list=GUEST \
    dst-address=10.20.0.0/16 comment="solej-mgr: guest -> any LAN BLOCK"
/ip firewall filter add chain=forward action=drop in-interface-list=GUEST \
    dst-address=192.168.0.0/16 comment="solej-mgr: guest -> 192.168/16 BLOCK"
/ip firewall filter add chain=forward action=drop in-interface-list=GUEST \
    dst-address=172.16.0.0/12 comment="solej-mgr: guest -> 172.16/12 BLOCK"

# LAN -> WAN i LAN -> LAN dla zaufanych
/ip firewall filter add chain=forward action=accept in-interface-list=PRIV \
    comment="solej-mgr: priv -> wszystko"
/ip firewall filter add chain=forward action=accept in-interface-list=MGMT \
    comment="solej-mgr: mgmt -> wszystko"
/ip firewall filter add chain=forward action=accept in-interface-list=VPN \
    comment="solej-mgr: VPN -> wszystko (zarządzanie zdalne)"

# Goście -> WAN (po zalogowaniu w hotspot)
/ip firewall filter add chain=forward action=accept in-interface-list=GUEST \
    out-interface-list=WAN comment="solej-mgr: guest -> internet"

# Drop wszystkiego innego
/ip firewall filter add chain=forward action=drop comment="solej-mgr: drop all other forward"

# === 15. Bridge VLAN filtering ON =========================================
# WŁĄCZENIE PO konfiguracji wszystkich VLAN-ów - od teraz bridge filtruje VLANy.
/interface bridge set [find name=bridge] vlan-filtering=yes

# === 16. WiFi (lokalne radia hAP) - parter recepcji ========================
# Na hAP ax3 w RouterOS 7.20 używamy LOCAL MODE (bez CAPsMAN):
# - hAP nadaje sam SSID Solej-priv + Solej-Guest na 2.4 i 5 GHz
# - cAP-y na piętrach mają WŁASNĄ lokalną konfigurację (configs/3-cap-*.rsc),
#   z TYM SAMYM passphrase + ft-mobility-domain w sec-priv → 802.11r FT
#   roaming działa pomiędzy hAP a cAP-ami bez CAPsMAN-a.
#
# DLACZEGO NIE CAPSMAN: w 7.20.8 wifi-qcom lokalny CAP nie kończy CAPWAP
# handshake do CAPsMAN-a na tym samym urządzeniu (radia stoją w stanie
# "no connection to CAPsMAN" — bez błędów w logu). Local mode + powtórzenie
# tych samych sec-priv/sec-open/sec-cams na każdym AP jest prostsze i działa.

# === 17. WiFi: security profiles ===========================================
:if ([:len [/interface wifi security find where name="sec-priv"]] = 0) do={
    /interface wifi security add name="sec-priv" \
        authentication-types=wpa2-psk,wpa3-psk \
        passphrase="__PLACEHOLDER_PRIV_WIFI_PASSWORD__" \
        ft=yes ft-over-ds=yes ft-mobility-domain=0xa1b2 \
        comment="Solej-priv WPA2/3 + 802.11r FT"
}
:if ([:len [/interface wifi security find where name="sec-open"]] = 0) do={
    /interface wifi security add name="sec-open" \
        authentication-types="" \
        comment="Solej-Guest open (hotspot na warstwie wyzej)"
}
:if ([:len [/interface wifi security find where name="sec-cams"]] = 0) do={
    /interface wifi security add name="sec-cams" \
        authentication-types=wpa2-psk \
        passphrase="__PLACEHOLDER_CAMS_WIFI_PASSWORD__" \
        comment="Solej-Cams WPA2"
}

# === 18. WiFi: datapath (bridge + VLAN) ====================================
:if ([:len [/interface wifi datapath find where name="dp-priv"]] = 0) do={
    /interface wifi datapath add name="dp-priv" bridge=bridge vlan-id=20 \
        client-isolation=no comment="datapath priv VLAN 20"
}
:if ([:len [/interface wifi datapath find where name="dp-guest"]] = 0) do={
    /interface wifi datapath add name="dp-guest" bridge=bridge vlan-id=40 \
        client-isolation=yes comment="datapath guest VLAN 40 (L2 isolation)"
}
:if ([:len [/interface wifi datapath find where name="dp-cams"]] = 0) do={
    /interface wifi datapath add name="dp-cams" bridge=bridge vlan-id=30 \
        client-isolation=no comment="datapath cams VLAN 30"
}

# === 19. WiFi: configurations (po jednej per SSID per pasmo) ===============
# WAŻNE w 7.20+: country MUSI być Pisane PascalCase (Poland), nie "poland".
# 2 GHz
:if ([:len [/interface wifi configuration find where name="cfg-priv-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-priv-2g" ssid="Solej-priv" \
        mode=ap security=sec-priv datapath=dp-priv country=Poland \
        comment="Solej-priv 2.4G"
}
:if ([:len [/interface wifi configuration find where name="cfg-guest-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-guest-2g" ssid="Solej-Guest" \
        mode=ap security=sec-open datapath=dp-guest country=Poland \
        comment="Solej-Guest 2.4G open + hotspot"
}
:if ([:len [/interface wifi configuration find where name="cfg-cams-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-cams-2g" ssid="Solej-Cams" \
        mode=ap security=sec-cams datapath=dp-cams country=Poland \
        disabled=yes comment="Solej-Cams 2.4G (DISABLED do czasu zakupu kamer wifi)"
}
# 5 GHz (Solej-priv + Solej-Guest, bez Cams)
:if ([:len [/interface wifi configuration find where name="cfg-priv-5g"]] = 0) do={
    /interface wifi configuration add name="cfg-priv-5g" ssid="Solej-priv" \
        mode=ap security=sec-priv datapath=dp-priv country=Poland \
        comment="Solej-priv 5G"
}
:if ([:len [/interface wifi configuration find where name="cfg-guest-5g"]] = 0) do={
    /interface wifi configuration add name="cfg-guest-5g" ssid="Solej-Guest" \
        mode=ap security=sec-open datapath=dp-guest country=Poland \
        comment="Solej-Guest 5G"
}

# === 20. Lokalne wifi hAP-a: local mode + multi-SSID =======================
# Defconf przypina wifi1 (5GHz) i wifi2 (2.4GHz) z hardcoded SSID
# "MikroTik-XXXXXX" i własnym security. Czyścimy te per-radio override-y
# przez `!`-syntax, żeby radia wzięły wartości z configuration=cfg-priv-*.
# Per-radio override jest silniejszy niż configuration= — `!` USUWA override
# (nie ustawia go na pusty string — to ważna różnica, sprawdzona empirycznie
# na 7.20.8: `set .ssid=""` daje SSID-not-set, a `!.ssid` przywraca z cfg).

# Najpierw kasujemy ewentualne virtual-AP z poprzednich importów (idempotencja).
# UWAGA: filter `master-interface!=""` w 7.20.8 matchuje też master radia
# (wifi1/wifi2 — fizyczne, których nie wolno usunąć). Zamiast tego filtrujemy
# po nazwach naszych virtual-AP — bezpieczniej, idempotentnie.
:foreach vname in={"wifi1-guest";"wifi2-guest";"wifi1-cams";"wifi2-cams"} do={
    :foreach w in=[/interface wifi find where name=$vname] do={
        /interface wifi remove $w
    }
}

# Master radia: przypisz configuration + wyczyść defconf override-y
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
}

# Slave virtual-AP: Solej-Guest na obu pasmach
:if ([:len [/interface wifi find where name="wifi1-guest"]] = 0) do={
    /interface wifi add name=wifi1-guest master-interface=wifi1 \
        configuration=cfg-guest-5g disabled=no \
        comment="Solej-Guest 5G (slave wifi1)"
}
:if ([:len [/interface wifi find where name="wifi2-guest"]] = 0) do={
    /interface wifi add name=wifi2-guest master-interface=wifi2 \
        configuration=cfg-guest-2g disabled=no \
        comment="Solej-Guest 2.4G (slave wifi2)"
}

# Master radia jako bridge port (datapath SAM auto-dodaje slaves, ale NIE
# auto-dodaje master fizycznych w 7.20.8). Bez tego DHCP/ruch z klientów
# Solej-priv nie wpada do bridge, mimo że radio nadaje i klienci asocjują.
# UWAGA: frame-types=admit-all (NIE admit-only-untagged) — datapath taguje
# ramki vlan-id=20 przed bridge, admit-only-untagged by je dropowało.
:foreach iface in={"wifi1";"wifi2"} do={
    :foreach bp in=[/interface bridge port find where interface=$iface] do={
        /interface bridge port remove $bp
    }
}
/interface bridge port add bridge=bridge interface=wifi1 pvid=20 frame-types=admit-all \
    comment="solej-mgr: wifi1 master Solej-priv VLAN 20"
/interface bridge port add bridge=bridge interface=wifi2 pvid=20 frame-types=admit-all \
    comment="solej-mgr: wifi2 master Solej-priv VLAN 20"

# Po zakupie kamer wifi: usuń `disabled=yes` z cfg-cams-2g (sekcja 19)
# i dodaj slave:
#   /interface wifi configuration set [find name=cfg-cams-2g] disabled=no
#   /interface wifi add name=wifi2-cams master-interface=wifi2 \
#       configuration=cfg-cams-2g disabled=no comment="Solej-Cams (slave wifi2)"

# Włączenie wszystkich radii (master + slave). UWAGA na 7.20.8: po świeżym
# imporcie `set disabled=no` ustawia property, ale radio zostaje BOUND a nie
# RUNNING — nie nadaje. Dopiero `enable` faktycznie podnosi radio. 5GHz po
# enable wchodzi w DFS check (~1 minuta), 2.4GHz startuje natychmiast.
:foreach w in=[/interface wifi find] do={
    /interface wifi enable $w
}

# === 23. Hotspot dla Solej-Guest (VLAN 40) =================================
# Hotspot reużywa puli pool-guest zdefiniowanej w sekcji 9 (DHCP servers) —
# ten sam zakres 10.20.40.50-10.20.40.250, więc nie ma sensu duplikować.

# Profil użytkownika "guest" (rate limit + sesja)
:if ([:len [/ip hotspot user profile find where name="guest"]] = 0) do={
    /ip hotspot user profile add name="guest" \
        rate-limit="10M/30M" \
        shared-users=3 \
        session-timeout=7d \
        idle-timeout=30m \
        keepalive-timeout=2m \
        status-autorefresh=10m
}
# (rate-limit "tx/rx" — tx z punktu widzenia routera = upload klienta -> 10M up, 30M down)

# Profil hotspot
# login-by zawiera https — RouterOS użyje wbudowanego self-signed certa.
# Browser pokaże ostrzeżenie przy pierwszym logowaniu, ale captive portal zadziała.
# Aby pozbyć się ostrzeżenia: wgraj cert z trusted CA i ustaw ssl-certificate=<name>.
:if ([:len [/ip hotspot profile find where name="solej-hs"]] = 0) do={
    /ip hotspot profile add name="solej-hs" \
        hotspot-address=10.20.40.1 \
        dns-name="hotspot.solej.local" \
        login-by=trial,https,http-pap \
        trial-uptime-limit=7d \
        trial-uptime-reset=7d \
        trial-user-profile=guest \
        html-directory=hotspot \
        http-cookie-lifetime=7d \
        rate-limit="" \
        use-radius=no
}

# Włączenie hotspot na vlan-guest
:if ([:len [/ip hotspot find where name="hotspot-guest"]] = 0) do={
    /ip hotspot add name="hotspot-guest" \
        interface=vlan-guest \
        profile="solej-hs" \
        address-pool="pool-guest" \
        addresses-per-mac=3 \
        idle-timeout=30m \
        keepalive-timeout=2m \
        disabled=no
}

# Walled garden — strony dostępne BEZ logowania (Apple/Android/Windows captive check)
/ip hotspot walled-garden remove [find where comment~"solej-mgr"]
/ip hotspot walled-garden add dst-host="*.apple.com" comment="solej-mgr: iOS captive detection"
/ip hotspot walled-garden add dst-host="captive.apple.com" comment="solej-mgr: iOS captive"
/ip hotspot walled-garden add dst-host="*.gstatic.com" comment="solej-mgr: Android captive detection"
/ip hotspot walled-garden add dst-host="connectivitycheck.gstatic.com" comment="solej-mgr: Android captive"
/ip hotspot walled-garden add dst-host="*.msftconnecttest.com" comment="solej-mgr: Windows captive"

# === 24. Cloud / Back to Home prep =========================================
/ip cloud set ddns-enabled=yes update-time=yes
# Aktywacja Back to Home VPN: WinBox -> IP -> Cloud -> Back to Home
# (ten skrypt nie aktywuje, bo wymaga konta MikroTik i interakcji)

# Po aktywacji Back to Home, scheduler doda interfejs do listy VPN.
# RouterOS 7.21 tworzy WG interface o nazwach typu "back-to-home", "BTHome", "bth-*"
# w zależności od buildu/wersji — szukamy wszystkich kandydatów (case-insensitive).
:if ([:len [/system scheduler find where name="add-bth-to-vpn-list"]] = 0) do={
    /system scheduler add name="add-bth-to-vpn-list" \
        interval=5m start-time=startup \
        on-event=":foreach i in=[/interface wireguard find] do={ :local n [/interface wireguard get \$i name]; :local ln [:tolower \$n]; :if ([:find \$ln \"back-to-home\"] >= 0 or [:find \$ln \"bthome\"] >= 0 or [:find \$ln \"bth-\"] >= 0) do={ :if ([:len [/interface list member find where list=\"VPN\" and interface=\$n]] = 0) do={ /interface list member add list=VPN interface=\$n; :log info (\"BtH (\" . \$n . \") dodane do listy VPN\") } } } " \
        comment="auto-add Back to Home VPN do listy VPN"
}

# === 25. Hardening services =================================================
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set www-ssl disabled=yes
# Winbox/SSH tylko z LAN (mgmt+priv) i Back-to-Home VPN — defense in depth.
# Firewall i tak filtruje, ale `address=` to drugi hamulec (np. gdyby filter
# został przypadkiem wyczyszczony).
/ip service set winbox disabled=no port=8291 \
    address=10.20.10.0/24,10.20.20.0/24,192.168.66.0/24
/ip service set ssh disabled=no port=22 \
    address=10.20.10.0/24,10.20.20.0/24,192.168.66.0/24

/tool mac-server set allowed-interface-list="MGMT"
/tool mac-server mac-winbox set allowed-interface-list="MGMT"
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list="MGMT"
/tool bandwidth-server set enabled=no
/tool romon set enabled=no

# Disable IPv6 jeśli operator nie daje (uproszczenie firewalla)
/ipv6 settings set disable-ipv6=yes

:log info "hAP-Solej: konfiguracja zakończona"
:put "OK. Aktywuj Back to Home: WinBox -> IP -> Cloud -> Back to Home -> Enable"
:put "Sprawdź: /interface wifi print, /ip dhcp-server lease print"
