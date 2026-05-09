# =============================================================================
# cAP ax — Solej Hotel (access point — piętro)
# Rola: bridge VLAN trunk + lokalne wifi (Solej-priv + Solej-Guest)
# RouterOS: 7.20.8+
#
# UWAGA: Ten skrypt jest IDENTYCZNY dla obu cAP-ów (piętro 1 i 2).
# Różni się tylko identity — render.sh podstawia __PLACEHOLDER_IDENTITY__
# z .env (CAP1_IDENTITY / CAP2_IDENTITY).
#
# MODEL: local mode (BEZ CAPsMAN). Każdy cAP ma własną kopię konfiguracji
# wifi z TYM SAMYM passphrase i ft-mobility-domain co hAP — dzięki temu
# 802.11r FT roaming działa pomiędzy hAP a cAP-ami.
# Dlaczego nie CAPsMAN: w 7.20.8 wifi-qcom buggy bind lokalnego CAP do
# CAPsMAN-a; local mode jest stabilny i prostszy w debugowaniu.
#
# PRZED IMPORTEM:
#   1. Reset to defaults BEZ default config (System -> Reset Configuration ->
#      "No Default Configuration").
#   2. Update firmware do 7.20.8+ + RouterBOOT.
#   3. Podłącz cAP do hAP (ether1 cAP -> ether2 hAP dla pietra 1,
#                        ether1 cAP -> ether3 hAP dla pietra 2).
#      Zasilanie z PoE injectora cAP (jest w zestawie).
#   4. render.sh podstawi placeholdery — wgraj OUT/3-cap-pietroN.rsc
#
# IMPORT:
#   /import file-name=3-cap-pietro1.rsc verbose=yes
#
# PO IMPORCIE:
#   - cAP dostanie IP od hAP w sieci 10.20.10.0/24 (mgmt VLAN).
#   - Sprawdź na cAP: /interface wifi print — wifi1/wifi2 BOUND, nie INACTIVE
#   - Sprawdź na cAP: /interface wifi registration-table print — klienci
#   - Z laptopa na hAP: /ip dhcp-server lease print — cAP widoczny w mgmt
# =============================================================================

:log info "cAP-Solej: start konfiguracji"

# === 1. Identity i hasło ====================================================
/system identity set name="__PLACEHOLDER_IDENTITY__"
/system clock set time-zone-name=Europe/Warsaw
/user set [find name="admin"] password="__PLACEHOLDER_ADMIN_PASSWORD__"

# === 2. Bridge główny (vlan-filtering=OFF na czas konfiguracji) =============
:if ([:len [/interface bridge find where name="bridge"]] = 0) do={
    /interface bridge add name="bridge" vlan-filtering=no \
        comment="Solej cAP bridge"
}

# === 3. Bridge ports ========================================================
# ether1 = uplink trunk do hAP (mgmt VLAN 10 native, reszta tagged)
# ether2 = access VLAN 20 opcjonalnie (np. TV/PS5 w pokoju)
# wifi1/wifi2 są dynamicznie dodawane do bridge przez datapath= w cfg-*.
:foreach iface in={"ether1";"ether2"} do={
    :foreach bp in=[/interface bridge port find where interface=$iface] do={
        /interface bridge port remove $bp
    }
}
/interface bridge port add bridge=bridge interface=ether1 pvid=10 \
    comment="solej-mgr: trunk uplink (mgmt VLAN 10 native)"
/interface bridge port add bridge=bridge interface=ether2 pvid=20 \
    frame-types=admit-only-untagged-and-priority-tagged \
    comment="solej-mgr: access VLAN 20 -> TV/PS5 w pokoju"

# === 4. Bridge VLAN table ===================================================
/interface bridge vlan remove [find where comment~"solej-mgr"]
/interface bridge vlan add bridge=bridge vlan-ids=10 \
    tagged=bridge untagged=ether1 \
    comment="solej-mgr: VLAN 10 mgmt native"
/interface bridge vlan add bridge=bridge vlan-ids=20 \
    tagged=bridge,ether1 untagged=ether2 \
    comment="solej-mgr: VLAN 20 priv"
/interface bridge vlan add bridge=bridge vlan-ids=30 \
    tagged=bridge,ether1 \
    comment="solej-mgr: VLAN 30 cams"
/interface bridge vlan add bridge=bridge vlan-ids=40 \
    tagged=bridge,ether1 \
    comment="solej-mgr: VLAN 40 guest"

# === 5. VLAN interface dla mgmt (żeby cAP dostał IP z hAP) =================
:if ([:len [/interface vlan find where name="vlan-mgmt"]] = 0) do={
    /interface vlan add name="vlan-mgmt" vlan-id=10 interface=bridge
}

# === 6. DHCP client na vlan-mgmt (IP od hAP) ===============================
/ip dhcp-client remove [find where interface=vlan-mgmt]
/ip dhcp-client add interface=vlan-mgmt disabled=no \
    use-peer-dns=yes use-peer-ntp=yes \
    comment="mgmt IP z hAP"

# === 7. Bridge VLAN filtering ON ===========================================
/interface bridge set [find name=bridge] vlan-filtering=yes

# === 8. WiFi: security profiles ============================================
# IDENTYCZNE jak na hAP (sec-priv przede wszystkim — passphrase + mobility-
# domain MUSZĄ się zgadzać, bo to one decydują czy klient roamuje bez
# powtórnego handshake'a).
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

# === 9. WiFi: datapath (bridge + VLAN) =====================================
:if ([:len [/interface wifi datapath find where name="dp-priv"]] = 0) do={
    /interface wifi datapath add name="dp-priv" bridge=bridge vlan-id=20 \
        client-isolation=no comment="datapath priv VLAN 20"
}
:if ([:len [/interface wifi datapath find where name="dp-guest"]] = 0) do={
    /interface wifi datapath add name="dp-guest" bridge=bridge vlan-id=40 \
        client-isolation=yes comment="datapath guest VLAN 40 (L2 isolation)"
}

# === 10. WiFi: configurations ==============================================
# country=Poland (PascalCase — w 7.20+ "poland" lowercase nie przechodzi).
:if ([:len [/interface wifi configuration find where name="cfg-priv-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-priv-2g" ssid="Solej-priv" \
        mode=ap security=sec-priv datapath=dp-priv country=Poland \
        comment="Solej-priv 2.4G"
}
:if ([:len [/interface wifi configuration find where name="cfg-guest-2g"]] = 0) do={
    /interface wifi configuration add name="cfg-guest-2g" ssid="Solej-Guest" \
        mode=ap security=sec-open datapath=dp-guest country=Poland \
        comment="Solej-Guest 2.4G"
}
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

# === 11. WiFi: local mode + multi-SSID (jak na hAP) ========================
# Czyścimy stare virtual-AP (idempotencja przy re-imporcie)
:foreach w in=[/interface wifi find where master-interface!=""] do={
    /interface wifi remove $w
}

# Master radia: Solej-priv. Per-radio defconf override-y kasujemy przez `!`,
# żeby radio wzięło SSID/security/passphrase z configuration=cfg-priv-*.
# UWAGA: cAP ax ma wifi1=2.4GHz i wifi2=5GHz (odwrotnie niż hAP ax3!) —
# sprawdź `:put [/interface wifi get wifi1 channel.band]` po pierwszym imporcie.
# Jeśli na Twoim cAP jest odwrotnie, zamień cfg-*-2g <-> cfg-*-5g poniżej.
:if ([:len [/interface wifi find where name="wifi1"]] > 0) do={
    /interface wifi set wifi1 configuration=cfg-priv-2g configuration.manager=local
    /interface wifi set wifi1 \
        !configuration.ssid !configuration.mode \
        !security.passphrase !security.authentication-types \
        !security.ft !security.ft-over-ds
}
:if ([:len [/interface wifi find where name="wifi2"]] > 0) do={
    /interface wifi set wifi2 configuration=cfg-priv-5g configuration.manager=local
    /interface wifi set wifi2 \
        !configuration.ssid !configuration.mode \
        !security.passphrase !security.authentication-types \
        !security.ft !security.ft-over-ds
}

# Slave virtual-AP: Solej-Guest na obu pasmach
:if ([:len [/interface wifi find where name="wifi1-guest"]] = 0) do={
    /interface wifi add name=wifi1-guest master-interface=wifi1 \
        configuration=cfg-guest-2g disabled=no \
        comment="Solej-Guest 2.4G (slave wifi1)"
}
:if ([:len [/interface wifi find where name="wifi2-guest"]] = 0) do={
    /interface wifi add name=wifi2-guest master-interface=wifi2 \
        configuration=cfg-guest-5g disabled=no \
        comment="Solej-Guest 5G (slave wifi2)"
}

# Włączenie wszystkich radii
:foreach w in=[/interface wifi find] do={
    /interface wifi set $w disabled=no
}

# === 12. Interface lists ===================================================
:if ([:len [/interface list find where name="MGMT"]] = 0) do={
    /interface list add name="MGMT"
}
:if ([:len [/interface list member find where list="MGMT" and interface="vlan-mgmt"]] = 0) do={
    /interface list member add list="MGMT" interface=vlan-mgmt
}

# === 13. Firewall (cAP nie routuje, ale chronimy input) ====================
/ip firewall filter remove [find where comment~"solej-mgr"]
/ip firewall filter add chain=input action=accept connection-state=established,related,untracked \
    comment="solej-mgr: established"
/ip firewall filter add chain=input action=drop connection-state=invalid \
    comment="solej-mgr: invalid"
/ip firewall filter add chain=input action=accept protocol=icmp limit=10,5:packet \
    comment="solej-mgr: icmp"
/ip firewall filter add chain=input action=accept in-interface-list=MGMT \
    comment="solej-mgr: admin tylko z mgmt VLAN"
/ip firewall filter add chain=input action=drop comment="solej-mgr: drop everything else"

# === 14. Hardening ==========================================================
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set www-ssl disabled=yes
/ip service set winbox disabled=no
/ip service set ssh disabled=no port=22

/tool mac-server set allowed-interface-list="MGMT"
/tool mac-server mac-winbox set allowed-interface-list="MGMT"
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list="MGMT"
/tool bandwidth-server set enabled=no
/tool romon set enabled=no
/ipv6 settings set disable-ipv6=yes
/ip cloud set ddns-enabled=no

:log info "cAP-Solej: konfiguracja zakończona"
:put "OK. Sprawdź: /interface wifi print (wifi* powinny być B, nie BI)"
:put "Sprawdź: /ip address print (mgmt IP od hAP w 10.20.10.0/24)"
